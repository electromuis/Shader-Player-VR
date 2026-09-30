"""Tests for resolve/VJ Sync.py, with a fake Resolve and a real loopback
WebSocket playing the player. Run: python -m unittest discover resolve/tests"""

import base64
import importlib.util
import json
import os
import socket
import struct
import tempfile
import time
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("vj_sync", os.path.join(_HERE, "..", "VJ Sync.py"))
vj = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(vj)


# ---------- fake Resolve ----------

class FakeMediaPoolItem:
    def __init__(self, path):
        self.path = path

    def GetClipProperty(self, key=None):
        props = {"File Path": self.path, "FPS": 25}
        return props if key is None else props[key]


class FakeItem:
    def __init__(self, name, start, end, path, source_start=0.0, speed=100.0):
        self.name, self.start, self.end = name, start, end
        self.mpi = FakeMediaPoolItem(path) if path else None
        self.source_start, self.speed = source_start, speed

    def GetName(self):
        return self.name

    def GetStart(self, subframe=False):
        return self.start

    def GetEnd(self, subframe=False):
        return self.end

    def GetMediaPoolItem(self):
        return self.mpi

    def GetSourceStartTime(self):
        return self.source_start

    def GetSpeed(self):
        return {"Percentage": self.speed}


class FakeTimeline:
    """25 fps, starting at 01:00:00:00 = frame 90000."""

    def __init__(self, tracks, markers=None):
        self.tracks = tracks  # list of item lists, V1 first
        self.markers = markers or {}
        self.frame = 90000
        self.set_calls = []

    def GetUniqueId(self):
        return "tl1"

    def GetSettings(self):
        return {"timelineFrameRate": 25.0, "timelineDropFrameTimecode": "0"}

    def GetStartFrame(self):
        return 90000

    def GetStartTimecode(self):
        return "01:00:00:00"

    def GetTrackCount(self, kind):
        return len(self.tracks) if kind == "video" else 0

    def GetItemListInTrack(self, kind, index):
        return self.tracks[index - 1]

    def GetCurrentTimecode(self):
        return vj.frames_to_tc(self.frame, 25)

    def SetCurrentTimecode(self, tc):
        self.set_calls.append(tc)
        self.frame = vj.tc_to_frames(tc, 25)
        return True

    def GetMarkers(self):
        return self.markers


class FakeResolve:
    def __init__(self, timeline):
        self.timeline = timeline

    def GetProjectManager(self):
        return self

    def GetCurrentProject(self):
        return self

    def GetCurrentTimeline(self):
        return self.timeline


class FakeClock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


# ---------- a WebSocket client standing in for the player ----------

class WsClient:
    def __init__(self, port):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=2)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall(("GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                           "Sec-WebSocket-Key: %s\r\nSec-WebSocket-Version: 13\r\n\r\n" % key).encode())
        self.buf = b""
        self.handshake_done = False

    def send(self, obj):
        payload = json.dumps(obj).encode()
        mask = os.urandom(4)
        head = bytes([0x81])
        head += bytes([0x80 | len(payload)]) if len(payload) < 126 else bytes([0x80 | 126]) + struct.pack(">H", len(payload))
        self.sock.sendall(head + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def read(self, pump):
        """Messages available after pumping the server a few times."""
        out = []
        self.sock.settimeout(0.02)
        for _ in range(20):
            pump()
            try:
                self.buf += self.sock.recv(65536)
            except socket.timeout:
                pass
            if not self.handshake_done and b"\r\n\r\n" in self.buf:
                head, _, self.buf = self.buf.partition(b"\r\n\r\n")
                assert b"101" in head.split(b"\r\n")[0]
                self.handshake_done = True
            while self.handshake_done and len(self.buf) >= 2:
                n = self.buf[1] & 0x7F
                pos = 2
                if n == 126:
                    n = struct.unpack(">H", self.buf[2:4])[0]
                    pos = 4
                if len(self.buf) < pos + n:
                    break
                out.append(json.loads(self.buf[pos:pos + n].decode()))
                self.buf = self.buf[pos + n:]
            if out:
                break
        return out

    def close(self):
        self.sock.close()


# ---------- tests ----------

class TimecodeTest(unittest.TestCase):
    def test_non_drop(self):
        self.assertEqual(vj.tc_to_frames("01:00:00:00", 25), 90000)
        self.assertEqual(vj.frames_to_tc(90012, 25), "01:00:00:12")

    def test_drop_frame_round_trip(self):
        fps = vj.exact_fps("29.97")
        self.assertEqual(vj.frames_to_tc(1800, fps, True), "00:01:00;02")
        self.assertEqual(vj.tc_to_frames("00:01:00;02", fps), 1800)
        self.assertEqual(vj.tc_to_frames("00:10:00;00", fps), 17982)
        for frames in (0, 1799, 1800, 17981, 17982, 107892, 123456):
            self.assertEqual(vj.tc_to_frames(vj.frames_to_tc(frames, fps, True), fps), frames)

    def test_exact_fps(self):
        self.assertAlmostEqual(vj.exact_fps(23.976), 24000 / 1001)
        self.assertAlmostEqual(vj.exact_fps("29.97 DF"), 30000 / 1001)
        self.assertEqual(vj.exact_fps(25), 25.0)


class ScriptsTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.video = os.path.join(self.dir, "clip.mp4")
        open(self.video, "w").close()

    def _write(self, name, data):
        path = os.path.join(self.dir, name)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        return path

    def test_sibling_json(self):
        script = self._write("clip.spscript", {"format_version": 1, "tracks": []})
        self.assertEqual(vj.ScriptIndex().script_for(self.video), script)

    def test_added_script_matched_by_media_video(self):
        os.makedirs(os.path.join(self.dir, "piece"))
        script = self._write(os.path.join("piece", "piece.spscript"), {"media": {"video": "../clip.mp4"}, "tracks": []})
        self.assertEqual(vj.ScriptIndex([script]).script_for(self.video), script)
        self.assertEqual(vj.ScriptIndex([]).script_for(self.video), "")

    def test_non_script_json_ignored(self):
        self._write("clip.spscript", {"something": "else"})
        self.assertEqual(vj.ScriptIndex().script_for(self.video), "")


class MarkerTest(unittest.TestCase):
    def test_actions(self):
        ev, off = vj.marker_to_event("despawn cube_1", "", 2.0)
        self.assertEqual((ev["action"], ev["target"], ev["transition"]), ("despawn", "cube_1", {"type": "fade", "duration": 2.0}))
        ev, off = vj.marker_to_event("spawn cube_2 cube", '{"transform": {"position": [0, 1, 0]}}', 0.0)
        self.assertEqual((ev["id"], ev["prefab"], ev["transform"]["position"]), ("cube_2", "cube", [0, 1, 0]))
        self.assertIsNone(vj.marker_to_event("Marker 1", "", 0.0))
        self.assertIn("needs", vj.marker_to_event("vr_cut", "", 0.0))
        self.assertIn("JSON", vj.marker_to_event("vr_cut", "{nope", 0.0))

    def test_cut_fades(self):
        to = '{"to": {"position": [0, 2, 8]}}'
        ev, off = vj.marker_to_event("vr_cut", to, 1.0)
        self.assertEqual((ev["transition"], off), ({"type": "fade_to_black", "duration": 1.0}, 0.0))
        note = '{"to": {"position": [0, 2, 8]}, "transition": {"type": "fade_to_black", "duration": 0.5}}'
        ev, off = vj.marker_to_event("VR_CUT", note, 0.0)
        self.assertEqual((ev["action"], off), ("vr_cut", 0.25))

    def test_markers_map_through_clips(self):
        # Clip on V1 at timeline frames 90025..90525 (1 s in), from 10 s into its media.
        seg = vj.Segment(90025, 90525, 10.0, 1.0, 25.0, "a.spscript", "a")
        markers = {
            50: {"name": "despawn cube_1", "note": "", "duration": 1},  # frame 90050 -> 11 s
            75.0: {"name": "vr_cut", "note": '{"to": {}, "transition": {"type": "fade_to_black", "duration": 1}}', "duration": 1},
            0: {"name": "despawn x", "note": "", "duration": 1},  # before the clip
            10: {"name": "Marker 3", "note": "", "duration": 1},
        }
        out, problems = vj.markers_to_events(markers, 90000, [seg])
        self.assertEqual([(e["action"], e["t"]) for e in out["a.spscript"]], [("despawn", 11.0), ("vr_cut", 11.5)])
        self.assertEqual(list(out["a.spscript"][0])[:3], ["type", "t", "action"])
        self.assertEqual(len(problems), 1)
        self.assertIn("despawn x", problems[0])

    def test_merge_replaces_only_resolve_events(self):
        data = {"tracks": [
            {"type": "event", "t": 1.0, "action": "despawn", "target": "a"},
            {"type": "event", "t": 2.0, "action": "despawn", "target": "b", "source": "resolve"},
        ]}
        new = [{"type": "event", "t": 5.0, "action": "despawn", "target": "c", "source": "resolve"},
               {"type": "event", "t": 3.0, "action": "despawn", "target": "d", "source": "resolve"}]
        self.assertEqual(vj.merge_events(data, new), 1)
        self.assertEqual([tr["target"] for tr in data["tracks"]], ["a", "d", "c"])


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        media = os.path.join(self.dir, "clip.mp4")
        self.script = os.path.join(self.dir, "clip.spscript")
        with open(self.script, "w") as f:
            json.dump({"format_version": 1, "media": {"video": "clip.mp4"}, "tracks": []}, f)
        # V1: the clip from 01:00:02:00 for 20 s, starting 4 s into the media.
        self.fake_tl = FakeTimeline([[FakeItem("clip", 90050, 90550, media, source_start=4.0)]])
        self.clock = FakeClock()
        self.tl = vj.ResolveTimeline(FakeResolve(self.fake_tl), vj.ScriptIndex())
        self.server = vj.WsServer()
        self.assertTrue(self.server.start(23990))
        self.sync = vj.Sync(self.tl, self.server, clock=self.clock)
        self.player = WsClient(self.server.port)

    def tearDown(self):
        self.player.close()
        self.server.stop()

    def _step(self, frames=0, seconds=0.04):
        self.fake_tl.frame += frames
        self.clock.now += seconds
        self.sync.tick()

    def _messages(self):
        return self.player.read(self.sync.tick)

    def test_open_on_connect_then_play_seek_pause(self):
        self.fake_tl.frame = 90100  # 2 s into the clip = 6 s into the media
        msgs = self._messages()
        self.assertEqual(msgs[0]["type"], "open")
        self.assertTrue(vj.same_path(msgs[0]["path"], self.script))
        self.assertAlmostEqual(msgs[0]["t"], 6.0)
        self.assertFalse(msgs[0]["playing"])

        for _ in range(4):  # playback: one frame per 40 ms poll
            self._step(1)
        msgs = self._messages()
        self.assertEqual(msgs[-1]["type"], "play")

        self._step(250)  # a click further on while playing
        self.assertEqual(self._messages()[-1]["type"], "seek")

        for _ in range(10):  # stopped
            self._step(0)
        msgs = self._messages()
        self.assertEqual(msgs[-1]["type"], "pause")

    def test_single_steps_are_seeks_not_play(self):
        self.fake_tl.frame = 90100
        self._messages()
        for _ in range(4):
            self._step(1, seconds=0.3)  # arrow key presses
        types = [m["type"] for m in self._messages()]
        self.assertNotIn("play", types)
        self.assertIn("seek", types)
        self.assertFalse(self.sync.playing)

    def test_paused_player_moves_resolve(self):
        self.fake_tl.frame = 90100
        self._messages()
        self.player.send({"type": "state", "script": self.script, "t": 10.0, "playing": False, "ack": self.sync.seq})
        self._messages()
        self._step(0)
        # 10 s in the media = 6 s into the clip = 150 frames after 90050.
        self.assertEqual(self.fake_tl.set_calls[-1], "01:00:08:00")
        self.assertEqual(self.fake_tl.frame, 90200)
        # A stale state (acking an older command) doesn't move it.
        self.player.send({"type": "state", "script": self.script, "t": 12.0, "playing": False, "ack": self.sync.seq - 1})
        self._messages()
        self.assertEqual(len(self.fake_tl.set_calls), 1)

    def test_leaving_the_clip(self):
        self.fake_tl.frame = 90100
        self._messages()
        self.fake_tl.frame = 90600  # past the clip
        self._step(0)
        self.assertIsNone(self.sync.segment)
        self.fake_tl.frame = 90100
        self._step(0)
        self.assertEqual(self._messages()[-1]["type"], "open")


if __name__ == "__main__":
    unittest.main()
