// Talks to Godot: the VJ editor (or Studio) runs a small server on
// 127.0.0.1, on the first free port from 47811 (ShadertoyReceiver). The
// content script can't reach it itself (the page's rules apply to it), so
// it asks here.

const PORTS = [47811, 47812, 47813, 47814, 47815];

async function findGodot() {
  for (const port of PORTS) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/vj/ping`, {signal: AbortSignal.timeout(700)});
      if (r.ok) {
        const info = await r.json();
        if (info.app) return {port, app: info.app};
      }
    } catch (e) {
      // Nothing there; try the next port.
    }
  }
  return null;
}

async function send(shader, thumbnail) {
  const godot = await findGodot();
  if (!godot) return {ok: false, error: "Godot isn't running (open the VJ editor or Studio)"};
  try {
    const r = await fetch(`http://127.0.0.1:${godot.port}/vj/shadertoy`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({shader, thumbnail}),
    });
    return await r.json();
  } catch (e) {
    return {ok: false, error: "Godot didn't answer: " + e.message};
  }
}

chrome.runtime.onMessage.addListener((msg, sender, reply) => {
  if (msg.type === 'ping') {
    findGodot().then(reply);
    return true;
  }
  if (msg.type === 'send') {
    send(msg.shader, msg.thumbnail).then(reply);
    return true;
  }
  return false;
});
