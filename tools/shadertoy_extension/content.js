// Send to Godot on shadertoy.com: a button next to a shader's title, and
// one on each card in lists (browse, search, profiles, playlists). It
// fetches the shader's JSON the way the page does (/shadertoy, which needs
// no API key because it's your own browser) plus its thumbnail, and hands
// both to background.js for Godot.

const ICON = '⇩';

// Shadertoy answers 429 when asked too often; wait and ask again.
const RETRY_WAITS = [1500, 4000, 8000];

async function fetchShader(id) {
  const body = 's=' + encodeURIComponent(JSON.stringify({shaders: [id]})) + '&nt=1&nl=1&np=1';
  let r;
  for (let attempt = 0; ; attempt++) {
    r = await fetch('/shadertoy', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body,
      credentials: 'same-origin',
    });
    if (r.status !== 429 || attempt >= RETRY_WAITS.length) break;
    await new Promise((done) => setTimeout(done, RETRY_WAITS[attempt]));
  }
  if (r.status === 429) throw new Error('Shadertoy is busy, try again in a minute');
  if (!r.ok) throw new Error('Shadertoy said ' + r.status);
  const list = await r.json();
  if (!Array.isArray(list) || !list.length) throw new Error('Shadertoy has no such shader (or it is private)');
  return list[0];
}

async function fetchThumbnail(id) {
  try {
    const r = await fetch(`/media/shaders/${id}.jpg`, {credentials: 'same-origin'});
    if (!r.ok) return '';
    const bytes = new Uint8Array(await r.arrayBuffer());
    let s = '';
    for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    return btoa(s);
  } catch (e) {
    return '';
  }
}

function setState(button, state, label, title) {
  button.dataset.state = state;
  button.textContent = label;
  button.title = title || '';
}

async function sendToGodot(id, button) {
  setState(button, 'busy', 'Sending…');
  try {
    const [shader, thumbnail] = await Promise.all([fetchShader(id), fetchThumbnail(id)]);
    const res = await chrome.runtime.sendMessage({type: 'send', shader, thumbnail});
    if (!res || !res.ok) {
      setState(button, 'offline', '✕ ' + ((res && res.error) || 'Not sent'), 'Click to try again');
      return;
    }
    const where = res.app || 'Godot';
    if (res.errors && res.errors.length) {
      setState(button, 'bad', "✕ Sent, but won't run", `In ${where}, but it won't run as a layer: ${res.errors.join('; ')}`);
    } else if (res.edits && res.edits.length) {
      setState(button, 'edit', '✎ Sent, needs editing', `In ${where}. Needs editing: ${res.edits.join('; ')}`);
    } else {
      const notes = (res.warnings || []).join('; ');
      setState(button, 'ok', '✓ In Godot', `In ${where}` + (notes ? `. Note: ${notes}` : '. Runs as a layer as it is.'));
    }
  } catch (e) {
    setState(button, 'offline', '✕ ' + e.message, 'Click to try again');
  }
}

function makeButton(id, extraClass) {
  const b = document.createElement('button');
  b.type = 'button';
  b.className = 'vjgodot-button' + (extraClass ? ' ' + extraClass : '');
  b.dataset.vjgodotId = id;
  setState(b, 'idle', ICON + ' Send to Godot', 'Send this shader to the VJ editor');
  b.addEventListener('click', (ev) => {
    ev.preventDefault();
    ev.stopPropagation();
    if (b.dataset.state !== 'busy') sendToGodot(id, b);
  });
  return b;
}

function viewId() {
  const m = location.pathname.match(/^\/(?:view|embed)\/([A-Za-z0-9]+)/);
  return m ? m[1] : null;
}

function addViewButton() {
  const id = viewId();
  if (!id || document.querySelector('.vjgodot-button.vjgodot-main')) return;
  const title = document.getElementById('shaderTitle');
  const b = makeButton(id, 'vjgodot-main');
  if (title && title.parentElement) {
    title.parentElement.appendChild(b);
  } else {
    b.classList.add('vjgodot-floating');
    document.body.appendChild(b);
  }
  // Say up front whether Godot is there.
  chrome.runtime.sendMessage({type: 'ping'}).then((godot) => {
    if (b.dataset.state !== 'idle') return;
    if (godot) {
      b.title = 'Send this shader to ' + godot.app;
    } else {
      setState(b, 'offline', ICON + ' Send to Godot', "Godot isn't running: open the VJ editor, then click");
    }
  }).catch(() => {});
}

function addCardButtons() {
  for (const card of document.querySelectorAll('.searchResultContainer')) {
    if (card.querySelector(':scope > .vjgodot-button')) continue;
    const link = card.querySelector('a[href*="/view/"]');
    const m = link && link.getAttribute('href').match(/\/view\/([A-Za-z0-9]+)/);
    if (!m) continue;
    card.classList.add('vjgodot-card');
    card.appendChild(makeButton(m[1], 'vjgodot-small'));
  }
}

function scan() {
  addViewButton();
  addCardButtons();
}

scan();
// Lists fill in after load and when paging.
new MutationObserver(() => {
  clearTimeout(scan.timer);
  scan.timer = setTimeout(scan, 300);
}).observe(document.body, {childList: true, subtree: true});
