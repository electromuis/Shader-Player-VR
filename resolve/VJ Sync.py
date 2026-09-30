#!/usr/bin/env python3
"""VJ Sync: DaVinci Resolve <-> Scripted VJ Video Player.

Put this file in Resolve's Scripts/Utility folder and run it from
Workspace > Scripts > Utility > VJ Sync (see resolve/README.md).

Two things:

- Playhead sync. A small WebSocket server on 127.0.0.1 (DEFAULT_PORT) that
  speaks the player's live-sync protocol, the one the Godot addon's
  Preview uses (project_engine/player/live_sync/ws_client.gd documents it).
  The player connects to it on its own. Playing, pausing and scrubbing in
  Resolve drive the player; pausing or scrubbing the paused player moves
  Resolve's playhead. The player shows the script of the clip under the
  playhead: a clip's script is the `.spscript` next to its media file
  (`clip.mp4` + `clip.spscript`, the player's own convention), or an added
  script whose `media.video` is that file.

- Markers -> script events. Timeline markers named after an event action
  (`vr_cut`, `vr_teleport`, `spawn <id> [prefab]`, `despawn <id>`) become
  event tracks in the script of the clip they sit on, with the marker's
  note as the event's other fields in JSON. They are written with
  `"source": "resolve"`, and exporting again replaces exactly those, so
  events from Godot stay; the Godot exporter keeps them in turn.

Needs no packages: the WebSocket server is the standard library's socket.
"""

import base64
import hashlib
import json
import os
import re
import socket
import struct
import subprocess
import sys
import time

DEFAULT_PORT = 47820
PORT_TRIES = 10
TICK_MSEC = 40
## Same thresholds as addon_vj/live_sync/live_sync.gd.
SEEK_INTERVAL = 0.033
PLAY_JUMP = 0.25
## Resolve says nothing about playback: the playhead moving forward this
## many polls in a row (no gap longer than RUN_GAP) means playing, standing
## still this long means paused.
PLAY_STEPS = 3
RUN_GAP = 0.15
PAUSE_AFTER = 0.25
## After moving Resolve's playhead, readings of the old frame for this long
## are Resolve catching up, not the user scrubbing back.
SETTLE_TIME = 0.3
## The timeline's clips and their scripts are re-read this often.
REFRESH_INTERVAL = 2.0
EVENT_ACTIONS = ("spawn", "despawn", "vr_cut", "vr_teleport")
SOURCE = "resolve"
SETTINGS_PATH = os.path.join(os.environ.get("APPDATA") or os.path.expanduser("~"), "VJ Resolve Sync.json")


# ---------- timecode ----------

_EXACT_FPS = {23.976: 24000 / 1001, 29.97: 30000 / 1001, 47.952: 48000 / 1001,
              59.94: 60000 / 1001, 119.88: 120000 / 1001}


def exact_fps(value):
    """Resolve's rounded rate ('23.976', 29.97) as the exact NTSC rate."""
    v = float(str(value).split()[0])
    for rounded, exact in _EXACT_FPS.items():
        if abs(v - rounded) < 0.01:
            return exact
    return v


def _drop_count(fps):
    return 2 * (round(fps) // 30)  # 2 frame numbers per minute at 29.97, 4 at 59.94


def tc_to_frames(tc, fps, drop=False):
    """'01:00:05:12' (';' before the frames = drop frame) -> frame count."""
    parts = [int(p) for p in re.split(r"[:;.,]", tc.strip())]
    if len(parts) != 4:
        raise ValueError("not a timecode: %r" % tc)
    h, m, s, f = parts
    drop = drop or ";" in tc
    nominal = round(fps)
    frames = ((h * 60 + m) * 60 + s) * nominal + f
    if drop:
        minutes = h * 60 + m
        frames -= _drop_count(fps) * (minutes - minutes // 10)
    return frames


def frames_to_tc(frames, fps, drop=False):
    nominal = round(fps)
    frames = int(frames)
    if drop:
        d = _drop_count(fps)
        per_10min = nominal * 600 - d * 9
        per_min = nominal * 60 - d
        tens, rem = divmod(frames, per_10min)
        frames += d * 9 * tens
        if rem > d:
            frames += d * ((rem - d) // per_min)
    f = frames % nominal
    s = frames // nominal % 60
    m = frames // (nominal * 60) % 60
    h = frames // (nominal * 3600)
    return "%02d:%02d:%02d%s%02d" % (h, m, s, ";" if drop else ":", f)


# ---------- scripts ----------

def same_path(a, b):
    """Windows paths: separators and case don't matter (as LiveSyncClient.same_path)."""
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


class ScriptIndex:
    """Which SPScript goes with a media file. Files are re-read when they change."""

    def __init__(self, extra_scripts=()):
        self.extra_scripts = list(extra_scripts)
        self._cache = {}  # path -> (mtime, parsed dict or None)

    def load(self, path):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            return None
        cached = self._cache.get(path)
        if cached is not None and cached[0] == mtime:
            return cached[1]
        data = None
        try:
            with open(path, encoding="utf-8") as f:
                parsed = json.load(f)
            if isinstance(parsed, dict) and ("tracks" in parsed or "format_version" in parsed):
                data = parsed
        except (OSError, ValueError):
            pass
        self._cache[path] = (mtime, data)
        return data

    def video_of(self, script_path):
        """The script's media.video as an absolute path ('' if none or a URL)."""
        data = self.load(script_path)
        video = (data or {}).get("media", {}).get("video", "")
        if not isinstance(video, str) or not video or "://" in video:
            return ""
        return os.path.normpath(os.path.join(os.path.dirname(script_path), video))

    def script_for(self, media_path):
        if not media_path:
            return ""
        sibling = os.path.splitext(media_path)[0] + ".spscript"
        if self.load(sibling) is not None:
            return sibling
        for script in self.extra_scripts:
            video = self.video_of(script)
            if video and same_path(video, media_path):
                return script
        return ""


class Segment:
    """A timeline clip that has a script: timeline frames [start, end) map
    to script time `src_start + (frame - start) / fps * speed`."""

    def __init__(self, start, end, src_start, speed, fps, script, name=""):
        self.start = start
        self.end = end
        self.src_start = src_start
        self.speed = speed
        self.fps = fps
        self.script = script
        self.name = name

    def contains(self, frame):
        return self.start <= frame < self.end

    def time_at(self, frame):
        return self.src_start + (frame - self.start) / self.fps * self.speed

    def frame_at(self, t):
        if self.speed <= 0.0:
            return None
        frame = self.start + round((t - self.src_start) * self.fps / self.speed)
        return min(max(frame, self.start), self.end - 1)


def segment_at(segments, frame):
    for seg in segments:  # topmost track first
        if seg.contains(frame):
            return seg
    return None


# ---------- markers -> events ----------

def marker_to_event(name, note, duration_sec):
    """A marker as a script event (without `t`), None when its name isn't an
    event action, or an error string. `offset` in the result is how far
    before the marker the event starts (half a fade_to_black: the marker is
    the cut, at peak black, as the Godot exporter does for VJViewer keys)."""
    words = (name or "").split()
    if not words or words[0].lower() not in EVENT_ACTIONS:
        return None
    action = words[0].lower()
    event = {}
    note = (note or "").strip()
    if note.startswith("{"):
        try:
            extra = json.loads(note)
        except ValueError as e:
            return "note isn't valid JSON (%s)" % e
        if not isinstance(extra, dict):
            return "note must be a JSON object"
        event.update(extra)
    event["type"] = "event"
    event["action"] = action
    offset = 0.0
    if action == "spawn":
        if len(words) > 1:
            event["id"] = words[1]
        if len(words) > 2:
            event["prefab"] = words[2]
        if not isinstance(event.get("id"), str) or not isinstance(event.get("prefab"), str):
            return "spawn needs an id and a prefab: 'spawn <id> <prefab>'"
        if "config" in event and not isinstance(event["config"], dict):
            return "config must be an object"
    elif action == "despawn":
        if len(words) > 1:
            event["target"] = words[1]
        if not isinstance(event.get("target"), str):
            return "despawn needs a target: 'despawn <id>'"
        if "transition" not in event and duration_sec > 0.0:
            event["transition"] = {"type": "fade", "duration": round(duration_sec, 3)}
    else:  # vr_cut, vr_teleport
        if not isinstance(event.get("to"), dict):
            return '%s needs "to" in the note, e.g. {"to": {"position": [0, 2, 8], "rotation_deg": [0, 0, 0]}}' % action
        tr = event.get("transition")
        if tr is None and duration_sec > 0.0:
            # A ranged marker is the fade itself.
            event["transition"] = {"type": "fade_to_black", "duration": round(duration_sec, 3)}
        elif isinstance(tr, dict) and tr.get("type") == "fade_to_black":
            offset = float(tr.get("duration", 0.0)) * 0.5
    event["source"] = SOURCE
    return event, offset


def markers_to_events(markers, timeline_start, segments):
    """Timeline.GetMarkers() -> ({script: [events]}, [problems]). Markers
    whose names aren't actions are skipped silently."""
    out = {}
    problems = []
    for frame_id in sorted(markers, key=float):
        info = markers[frame_id]
        frame = timeline_start + float(frame_id)
        seg = segment_at(segments, frame)
        label = "%s at frame %d" % (info.get("name", "?"), int(float(frame_id)))
        fps = seg.fps if seg is not None else 24.0
        length = int(info.get("duration", 1) or 1)
        result = marker_to_event(info.get("name", ""), info.get("note", ""), length / fps if length > 1 else 0.0)
        if result is None:
            continue
        if isinstance(result, str):
            problems.append("%s: %s" % (label, result))
            continue
        if seg is None:
            problems.append("%s: not on a clip that has an SPScript" % label)
            continue
        event, offset = result
        event["t"] = round(max(0.0, seg.time_at(frame) - offset), 3)
        ordered = {"type": event.pop("type"), "t": event.pop("t"), "action": event.pop("action")}
        ordered.update(event)
        out.setdefault(seg.script, []).append(ordered)
    return out, problems


def merge_events(script_data, events):
    """Replaces the script's Resolve events with `events` (in place).
    Returns how many were replaced."""
    tracks = script_data.setdefault("tracks", [])
    kept = [tr for tr in tracks if not (isinstance(tr, dict) and tr.get("source") == SOURCE)]
    removed = len(tracks) - len(kept)
    tracks[:] = kept + sorted(events, key=lambda e: e["t"])
    return removed


def write_events(script_path, events):
    with open(script_path, encoding="utf-8") as f:
        data = json.load(f)
    removed = merge_events(data, events)
    tmp = script_path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    os.replace(tmp, script_path)
    return removed


# ---------- WebSocket server (RFC 6455, text frames only) ----------

_WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


class WsPeer:
    def __init__(self, sock):
        sock.setblocking(False)
        self.sock = sock
        self.open = False
        self.closed = False
        self._in = b""
        self._out = b""
        self._fragments = b""

    def send_text(self, text):
        if self.open:
            self._out += _frame(0x1, text.encode("utf-8"))

    def close(self):
        if not self.closed:
            try:
                if self.open:
                    self.sock.send(_frame(0x8, b""))
            except OSError:
                pass
            self.sock.close()
        self.closed = True
        self.open = False

    def poll(self):
        """Reads what arrived; returns the complete text messages."""
        messages = []
        if self.closed:
            return messages
        try:
            while True:
                chunk = self.sock.recv(65536)
                if not chunk:
                    self.close()
                    return messages
                self._in += chunk
        except (BlockingIOError, InterruptedError):
            pass
        except OSError:
            self.close()
            return messages
        if not self.open:
            self._handshake()
        while self.open:
            frame = self._read_frame()
            if frame is None:
                break
            fin, opcode, payload = frame
            if opcode == 0x8:
                self.close()
                break
            if opcode == 0x9:
                self._out += _frame(0xA, payload)
            elif opcode in (0x0, 0x1):
                self._fragments += payload
                if fin:
                    messages.append(self._fragments.decode("utf-8", "replace"))
                    self._fragments = b""
        self._flush()
        return messages

    def _handshake(self):
        end = self._in.find(b"\r\n\r\n")
        if end < 0:
            if len(self._in) > 16384:
                self.close()
            return
        head = self._in[:end].decode("latin-1")
        self._in = self._in[end + 4:]
        key = ""
        for line in head.split("\r\n")[1:]:
            name, _, value = line.partition(":")
            if name.strip().lower() == "sec-websocket-key":
                key = value.strip()
        if not key:
            self.close()
            return
        accept = base64.b64encode(hashlib.sha1((key + _WS_GUID).encode()).digest()).decode()
        self._out += ("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                      "Sec-WebSocket-Accept: %s\r\n\r\n" % accept).encode()
        self.open = True
        self._flush()

    def _read_frame(self):
        buf = self._in
        if len(buf) < 2:
            return None
        fin = bool(buf[0] & 0x80)
        opcode = buf[0] & 0x0F
        masked = bool(buf[1] & 0x80)
        length = buf[1] & 0x7F
        pos = 2
        if length == 126:
            if len(buf) < 4:
                return None
            length = struct.unpack(">H", buf[2:4])[0]
            pos = 4
        elif length == 127:
            if len(buf) < 10:
                return None
            length = struct.unpack(">Q", buf[2:10])[0]
            pos = 10
        mask = b""
        if masked:
            if len(buf) < pos + 4:
                return None
            mask = buf[pos:pos + 4]
            pos += 4
        if len(buf) < pos + length:
            return None
        payload = buf[pos:pos + length]
        if masked:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self._in = buf[pos + length:]
        return fin, opcode, payload

    def _flush(self):
        try:
            while self._out:
                sent = self.sock.send(self._out)
                self._out = self._out[sent:]
        except (BlockingIOError, InterruptedError):
            pass
        except OSError:
            self.close()


def _frame(opcode, payload):
    head = bytes([0x80 | opcode])
    n = len(payload)
    if n < 126:
        head += bytes([n])
    elif n < 65536:
        head += bytes([126]) + struct.pack(">H", n)
    else:
        head += bytes([127]) + struct.pack(">Q", n)
    return head + payload


class WsServer:
    def __init__(self):
        self.port = 0
        self.peers = []
        self._sock = None

    def start(self, preferred=DEFAULT_PORT):
        for port in range(preferred, preferred + PORT_TRIES):
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                sock.bind(("127.0.0.1", port))
            except OSError:
                sock.close()
                continue
            sock.listen(4)
            sock.setblocking(False)
            self._sock = sock
            self.port = port
            return True
        return False

    def stop(self):
        for peer in self.peers:
            peer.close()
        self.peers = []
        if self._sock is not None:
            self._sock.close()
            self._sock = None

    def poll(self):
        """Accepts and reads. Returns (new peers, [(peer, message)])."""
        new = []
        if self._sock is not None:
            while True:
                try:
                    conn, _ = self._sock.accept()
                except (BlockingIOError, InterruptedError):
                    break
                except OSError:
                    break
                peer = WsPeer(conn)
                self.peers.append(peer)
        messages = []
        for peer in list(self.peers):
            was_open = peer.open
            for text in peer.poll():
                messages.append((peer, text))
            if peer.open and not was_open:
                new.append(peer)
            if peer.closed:
                self.peers.remove(peer)
        return new, messages

    def connected(self):
        return any(p.open for p in self.peers)

    def broadcast(self, text):
        for peer in self.peers:
            peer.send_text(text)
            peer._flush()


# ---------- Resolve ----------

class ResolveTimeline:
    """What the sync needs from Resolve's current timeline."""

    def __init__(self, resolve, scripts):
        self.resolve = resolve
        self.scripts = scripts
        self.timeline = None
        self.timeline_id = None
        self.fps = 24.0
        self.drop = False
        self.start = 0
        self.tc_offset = 0  # GetStartFrame() minus the start timecode's frame count
        self.segments = []
        self._refreshed = 0.0

    def current_timeline(self):
        pm = self.resolve.GetProjectManager()
        project = pm.GetCurrentProject() if pm else None
        return project.GetCurrentTimeline() if project else None

    def update(self, force=False):
        """Picks up a changed timeline, and re-reads clips every REFRESH_INTERVAL."""
        tl = self.current_timeline()
        if tl is None:
            self.timeline = None
            self.timeline_id = None
            self.segments = []
            return False
        tl_id = tl.GetUniqueId()
        now = time.monotonic()
        if force or tl_id != self.timeline_id or now - self._refreshed >= REFRESH_INTERVAL:
            self.timeline = tl
            self.timeline_id = tl_id
            self._refreshed = now
            self._read_settings()
            self.segments = self._read_segments()
        return True

    def _read_settings(self):
        tl = self.timeline
        settings = _settings(tl)
        self.fps = exact_fps(settings.get("timelineFrameRate", 24) or 24)
        self.drop = str(settings.get("timelineDropFrameTimecode", "0")) == "1" \
            or "DF" in str(settings.get("timelineFrameRate", ""))
        self.start = int(tl.GetStartFrame())
        try:
            self.tc_offset = self.start - tc_to_frames(tl.GetStartTimecode(), self.fps, self.drop)
        except (ValueError, TypeError, AttributeError):
            self.tc_offset = 0

    def _read_segments(self):
        tl = self.timeline
        segments = []
        for track in range(int(tl.GetTrackCount("video") or 0), 0, -1):
            for item in tl.GetItemListInTrack("video", track) or []:
                mpi = item.GetMediaPoolItem()
                if mpi is None:
                    continue
                script = self.scripts.script_for(_file_path(mpi))
                if not script:
                    continue
                segments.append(Segment(
                    start=int(item.GetStart()), end=int(item.GetEnd()),
                    src_start=_source_start(item, mpi, self.fps), speed=_speed(item),
                    fps=self.fps, script=script, name=item.GetName()))
        return segments

    def frame(self):
        tc = self.timeline.GetCurrentTimecode()
        return tc_to_frames(tc, self.fps, self.drop) + self.tc_offset

    def set_frame(self, frame):
        return bool(self.timeline.SetCurrentTimecode(frames_to_tc(frame - self.tc_offset, self.fps, self.drop)))

    def markers(self):
        return self.timeline.GetMarkers() or {}


def _settings(tl):
    try:
        return tl.GetSettings() or {}
    except (AttributeError, TypeError):  # before GetSettings()
        return {k: tl.GetSetting(k) for k in ("timelineFrameRate", "timelineDropFrameTimecode")}


def _clip_props(mpi):
    try:
        props = mpi.GetClipProperty()
        if isinstance(props, dict):
            return props
    except TypeError:
        pass
    return {k: mpi.GetClipProperty(k) for k in ("File Path", "FPS")}


def _file_path(mpi):
    return _clip_props(mpi).get("File Path", "") or ""


def _source_start(item, mpi, timeline_fps):
    """Seconds into the media file where the clip starts."""
    try:
        t = item.GetSourceStartTime()
        if isinstance(t, (int, float)):
            return float(t)
    except (AttributeError, TypeError):
        pass
    try:
        clip_fps = exact_fps(_clip_props(mpi).get("FPS") or timeline_fps)
        return float(item.GetSourceStartFrame()) / clip_fps
    except (AttributeError, TypeError, ValueError):
        return float(item.GetLeftOffset()) / timeline_fps


def _speed(item):
    try:
        opts = item.GetSpeed()
        if isinstance(opts, dict) and "Percentage" in opts:
            return float(opts["Percentage"]) / 100.0
    except (AttributeError, TypeError):
        pass
    return 1.0


# ---------- sync ----------

class Sync:
    """Resolve's playhead -> the player, and the paused player -> Resolve.
    Mirrors addon_vj/live_sync/live_sync.gd, with the play state guessed
    from the playhead since Resolve doesn't report it."""

    def __init__(self, timeline, server, clock=time.monotonic):
        self.tl = timeline
        self.server = server
        self.clock = clock
        self.seq = 0
        self.segment = None
        self.playing = False
        self.t = 0.0
        self.status = ""
        self._last_frame = None
        self._last_poll = 0.0
        self._forward_steps = 0
        self._moved_at = 0.0
        self._seek_pending = False
        self._last_seek = 0.0
        self._settle_frame = None
        self._settle_until = 0.0

    def tick(self):
        new_peers, messages = self.server.poll()
        if not self.tl.update():
            self.status = "No timeline open"
            self._last_frame = None
            return
        now = self.clock()
        frame = self.tl.frame()
        if self._settle_frame is not None:
            if frame == self._settle_frame or now >= self._settle_until:
                self._settle_frame = None
            else:
                frame = self._settle_frame
        self._follow_resolve(frame, now, new_peers)
        for _peer, text in messages:
            try:
                msg = json.loads(text)
            except ValueError:
                continue
            if isinstance(msg, dict) and msg.get("type") == "state":
                self._on_player_state(msg)

    def _follow_resolve(self, frame, now, new_peers):
        first = self._last_frame is None
        if first:
            self._last_frame = frame
            self._last_poll = now
            self._moved_at = now
        elapsed = max(now - self._last_poll, 1e-3)
        step = frame - self._last_frame
        if step > 0 and step <= elapsed * self.tl.fps * 2.5 + 2:
            if now - self._moved_at > RUN_GAP:
                self._forward_steps = 0  # separate steps (arrow keys), not playback
            self._forward_steps += 1
            self._moved_at = now
        elif step != 0:
            self._forward_steps = 0
            self._moved_at = now
        playing = self.playing
        if self._forward_steps >= PLAY_STEPS:
            playing = True
        if step <= 0 and now - self._moved_at >= PAUSE_AFTER:
            playing = False
            self._forward_steps = 0
        if step < 0:
            playing = False

        seg = segment_at(self.tl.segments, frame)
        t = seg.time_at(frame) if seg is not None else 0.0
        prev_t = self.t
        changed_clip = (seg is None) != (self.segment is None) or \
            (seg is not None and not same_path(seg.script, self.segment.script))
        if changed_clip or new_peers:
            self.segment = seg
            if seg is not None:
                self._send("open", {"path": seg.script, "t": t, "playing": playing})
            elif self.playing:
                self._send("pause", {"t": prev_t})
            self._seek_pending = False
        elif seg is not None:
            if playing != self.playing:
                self._send("play" if playing else "pause", {"t": t})
                self._seek_pending = False
            elif playing:
                if abs(t - (prev_t + elapsed * seg.speed)) > PLAY_JUMP:
                    self._send("seek", {"t": t})
            elif step != 0:
                self._seek_pending = True
            if self._seek_pending and now - self._last_seek >= SEEK_INTERVAL:
                self._seek_pending = False
                self._last_seek = now
                self._send("seek", {"t": t})
        self.segment = seg
        self.playing = playing
        self.t = t
        self._last_frame = frame
        self._last_poll = now
        self.status = self._describe()

    def _on_player_state(self, msg):
        """The paused player moved: take Resolve's playhead there, if the
        state answers our latest command (not a stale mid-scrub reply)."""
        if msg.get("playing") or int(msg.get("ack", -1)) != self.seq:
            return
        seg = self.segment
        if seg is None or self.playing or not same_path(str(msg.get("script", "")), seg.script):
            return
        t = float(msg.get("t", 0.0))
        if abs(t - self.t) < 0.5 / seg.fps:
            return
        frame = seg.frame_at(t)
        if frame is None or frame == self._last_frame:
            return
        if self.tl.set_frame(frame):
            self._last_frame = frame
            self.t = seg.time_at(frame)
            self._seek_pending = False
            self._settle_frame = frame
            self._settle_until = self.clock() + SETTLE_TIME

    def resend_open(self):
        """After rewriting the script: the player reloads it in place."""
        if self.segment is not None:
            self._send("open", {"path": self.segment.script, "t": self.t, "playing": self.playing})

    def _send(self, type_, fields):
        self.seq += 1
        fields["type"] = type_
        fields["seq"] = self.seq
        if "t" in fields:
            fields["t"] = round(float(fields["t"]), 3)
        self.server.broadcast(json.dumps(fields))

    def _describe(self):
        player = ("Player connected" if self.server.connected()
                  else "Waiting for the player on port %d" % self.server.port)
        if self.segment is None:
            clip = "no clip with an SPScript under the playhead"
        else:
            clip = "%s -> %s at %.2f s%s" % (self.segment.name, os.path.basename(self.segment.script),
                                            self.t, " (playing)" if self.playing else "")
        return "%s; %s" % (player, clip)


def export_markers(tl):
    """Writes the timeline's action markers into their clips' scripts.
    Returns a report line."""
    tl.update(force=True)
    per_script, problems = markers_to_events(tl.markers(), tl.start, tl.segments)
    lines = []
    for script, events in per_script.items():
        try:
            removed = write_events(script, events)
        except (OSError, ValueError) as e:
            problems.append("%s: %s" % (os.path.basename(script), e))
            continue
        lines.append("%s: %d event(s) (replaced %d)" % (os.path.basename(script), len(events), removed))
    if not lines and not problems:
        lines.append("No markers named vr_cut, vr_teleport, spawn or despawn on this timeline.")
    return "\n".join(lines + problems)


# ---------- settings ----------

def load_settings():
    try:
        with open(SETTINGS_PATH, encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except (OSError, ValueError):
        pass
    return {}


def save_settings(data):
    try:
        with open(SETTINGS_PATH, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except OSError:
        pass


def launch_player(exe, port):
    # Godot passes arguments after `--` to the game.
    subprocess.Popen([exe, "--", "--live-sync", str(port)], cwd=os.path.dirname(exe) or None)


# ---------- UI ----------

def get_resolve():
    g = globals()
    if "resolve" in g and hasattr(g["resolve"], "GetVersion"):
        return g["resolve"]
    if "bmd" in g:
        return g["bmd"].scriptapp("Resolve")
    import DaVinciResolveScript as dvr_script
    return dvr_script.scriptapp("Resolve")


def run_window(resolve, sync, tl, scripts, settings):
    fusion = resolve.Fusion()
    ui = fusion.UIManager
    disp = globals()["bmd"].UIDispatcher(ui)
    win = disp.AddWindow({"ID": "VJSync", "WindowTitle": "VJ Sync", "Geometry": [200, 200, 560, 300]}, ui.VGroup([
        ui.Label({"ID": "Status", "Text": "Starting...", "WordWrap": True}),
        ui.HGroup({"Weight": 0}, [
            ui.Label({"Text": "Player", "Weight": 0}),
            ui.LineEdit({"ID": "PlayerExe", "Text": settings.get("player", ""),
                         "PlaceholderText": "Player.exe, for Launch (optional: a running player finds this on its own)"}),
            ui.Button({"ID": "BrowsePlayer", "Text": "...", "Weight": 0}),
            ui.Button({"ID": "Launch", "Text": "Launch player", "Weight": 0}),
        ]),
        ui.HGroup({"Weight": 0}, [
            ui.Label({"ID": "Scripts", "Text": "", "WordWrap": True}),
            ui.Button({"ID": "AddScript", "Text": "Add script...", "Weight": 0}),
            ui.Button({"ID": "ClearScripts", "Text": "Clear", "Weight": 0}),
        ]),
        ui.HGroup({"Weight": 0}, [
            ui.Button({"ID": "ExportMarkers", "Text": "Markers -> script events"}),
        ]),
        ui.Label({"ID": "Report", "Text": "", "WordWrap": True}),
    ]))
    items = win.GetItems()

    def show_scripts():
        names = ", ".join(os.path.basename(s) for s in scripts.extra_scripts)
        items["Scripts"].Text = ("Added scripts: " + names) if names else \
            "Scripts: the .spscript next to each clip's media. Add others whose media.video is the clip."

    def on_close(ev):
        disp.ExitLoop()

    def on_tick(ev):
        try:
            sync.tick()
            items["Status"].Text = sync.status
        except Exception as e:  # keep syncing through Resolve hiccups
            items["Status"].Text = "Error: %s" % e

    def on_browse_player(ev):
        path = fusion.RequestFile(items["PlayerExe"].Text or "")
        if path:
            items["PlayerExe"].Text = str(path)

    def on_launch(ev):
        exe = items["PlayerExe"].Text.strip()
        if not os.path.isfile(exe):
            items["Report"].Text = "Pick the player's executable first."
            return
        settings["player"] = exe
        save_settings(settings)
        launch_player(exe, sync.server.port)
        items["Report"].Text = "Launched %s" % os.path.basename(exe)

    def on_add_script(ev):
        path = fusion.RequestFile("")
        if path and str(path) not in scripts.extra_scripts:
            scripts.extra_scripts.append(str(path))
            settings["scripts"] = scripts.extra_scripts
            save_settings(settings)
            tl.update(force=True)
            show_scripts()

    def on_clear_scripts(ev):
        scripts.extra_scripts = []
        settings["scripts"] = []
        save_settings(settings)
        tl.update(force=True)
        show_scripts()

    def on_export(ev):
        items["Report"].Text = export_markers(tl)
        sync.resend_open()

    win.On.VJSync.Close = on_close
    win.On.BrowsePlayer.Clicked = on_browse_player
    win.On.Launch.Clicked = on_launch
    win.On.AddScript.Clicked = on_add_script
    win.On.ClearScripts.Clicked = on_clear_scripts
    win.On.ExportMarkers.Clicked = on_export
    timer = ui.Timer({"ID": "VJSyncTick", "Interval": TICK_MSEC})
    disp.On.VJSyncTick.Timeout = on_tick

    show_scripts()
    win.Show()
    timer.Start()
    disp.RunLoop()
    timer.Stop()
    win.Hide()


def _is_resolve_menu_run():
    return "bmd" in globals() and "resolve" in globals()


def run_headless(sync, tl):
    """Without Resolve's UI (run from a terminal): sync until Ctrl+C.
    `--export-markers` exports and exits instead."""
    if "--export-markers" in sys.argv:
        print(export_markers(tl))
        return
    last = ""
    try:
        while True:
            sync.tick()
            if sync.status != last:
                last = sync.status
                print(last)
            time.sleep(TICK_MSEC / 1000.0)
    except KeyboardInterrupt:
        pass


def main():
    resolve = get_resolve()
    if resolve is None:
        print("VJ Sync: DaVinci Resolve isn't reachable.")
        return
    settings = load_settings()
    scripts = ScriptIndex(settings.get("scripts", []))
    tl = ResolveTimeline(resolve, scripts)
    server = WsServer()
    if not server.start(int(settings.get("port", DEFAULT_PORT))):
        print("VJ Sync: no free port in %d-%d." % (DEFAULT_PORT, DEFAULT_PORT + PORT_TRIES - 1))
        return
    print("VJ Sync: listening on 127.0.0.1:%d" % server.port)
    sync = Sync(tl, server)
    try:
        if _is_resolve_menu_run():
            run_window(resolve, sync, tl, scripts, settings)
        else:
            run_headless(sync, tl)
    finally:
        server.stop()


# Resolve's Scripts menu defines `bmd` and `resolve` for the script; tests
# import it without them.
if __name__ == "__main__" or _is_resolve_menu_run():
    main()
