// Voice and video calls: signaling and the browser call page.
//
// Calls are WebRTC, so audio and video go straight between the two devices
// (or through Cloudflare's TURN relay), encrypted end to end. This Worker
// only passes the short "how to reach me" messages between the two sides
// and then gets out of the way. Nothing about a call is kept after it ends.
//
// Routes
//   POST /call               {"video": bool} -> 201 {"id","url","expiresAt"}
//   GET  /c/<id>             browser call page, for people on other IRC apps
//   GET  /c/<id>/ice         {"iceServers": [...], "relay": bool}
//   GET  /c/<id>/ws          WebSocket, upgraded by the CallRoom object
//   POST /c/<id>/decline     tells the caller the call was declined
//
// Each call is one CallRoom (a Durable Object). It takes two people: the
// caller, who connects first, and whoever opens the link next. A call nobody
// answers ends after RING_MS. Once a call ends, its link stops working.

export const RING_MS = 10 * 60 * 1000;
const ID_PATTERN = /^[A-Za-z0-9_-]{22}$/;
const MAX_SIGNAL_BYTES = 64 * 1024;
const RELAY_TTL_SECONDS = 4 * 3600;

export async function callRoute(request, env, url, now = Date.now()) {
  const path = url.pathname;
  if (request.method === 'POST' && path === '/call') {
    return createCall(request, env, url, now);
  }
  const m = path.match(/^\/c\/([^/]+)(\/(ice|ws|decline))?$/);
  if (!m || !ID_PATTERN.test(m[1])) return null;
  const id = m[1];
  const action = m[3];
  if (!action && request.method === 'GET') return callPage();
  if (action === 'ice' && request.method === 'GET') {
    return json(await iceServers(env));
  }
  if (!env.CALLS) return json({ error: 'Calls are not set up' }, 503);
  const stub = env.CALLS.get(env.CALLS.idFromName(id));
  if (action === 'ws' && request.method === 'GET') return stub.fetch(request);
  if (action === 'decline' && request.method === 'POST') {
    return stub.fetch(new Request('https://room/decline', { method: 'POST' }));
  }
  return json({ error: 'Not found' }, 404);
}

async function createCall(request, env, url, now) {
  if (!env.CALLS) return json({ error: 'Calls are not set up' }, 503);
  if (env.CALL_LIMIT) {
    const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
    const { success } = await env.CALL_LIMIT.limit({ key: ip });
    if (!success) return json({ error: 'Too many calls. Try again in a minute.' }, 429);
  }
  if (env.APP_TOKEN && request.headers.get('x-app-token') !== env.APP_TOKEN) {
    return json({ error: 'Not allowed' }, 403);
  }
  let video = false;
  try {
    video = (await request.json())?.video === true;
  } catch {
    // An empty body means a voice call.
  }
  const id = randomId();
  const stub = env.CALLS.get(env.CALLS.idFromName(id));
  const res = await stub.fetch(
    new Request('https://room/create', {
      method: 'POST',
      body: JSON.stringify({ now, video }),
    }),
  );
  if (!res.ok) return json({ error: 'Could not start the call' }, 500);
  const expiresAt = now + RING_MS;
  const link = `${url.origin}/c/${id}${video ? '#video' : '#voice'}`;
  return json({ id, url: link, expiresAt }, 201);
}

/// STUN always; TURN relay addresses when a Cloudflare TURN key is set up.
export async function iceServers(env, fetcher = fetch) {
  const stun = { urls: ['stun:stun.cloudflare.com:3478'] };
  if (!env.TURN_KEY_ID || !env.TURN_KEY_API_TOKEN) {
    return { iceServers: [stun], relay: false };
  }
  try {
    const res = await fetcher(
      `https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`,
      {
        method: 'POST',
        headers: {
          authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ ttl: RELAY_TTL_SECONDS }),
      },
    );
    if (!res.ok) throw new Error(`TURN ${res.status}`);
    const body = await res.json();
    const servers = [].concat(body.iceServers ?? []);
    if (!servers.length) throw new Error('No TURN servers');
    return { iceServers: servers, relay: true };
  } catch (e) {
    console.error(e);
    return { iceServers: [stun], relay: false };
  }
}

/// One call. Keeps two WebSockets and forwards signaling messages between
/// them. State lives only while the call is ringing or running.
export class CallRoom {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname === '/create') {
      const { now, video } = await request.json();
      await this.ctx.storage.put('call', { createdAt: now, video, answered: false });
      await this.ctx.storage.setAlarm(now + RING_MS);
      return new Response('ok');
    }
    const call = await this.ctx.storage.get('call');
    if (!call) return json({ error: 'This call has ended' }, 410);
    if (url.pathname === '/decline') {
      this.send('caller', { type: 'declined' });
      await this.end();
      return json({ ok: true });
    }
    if (request.headers.get('upgrade') !== 'websocket') {
      return json({ error: 'Expected a WebSocket' }, 426);
    }
    const sockets = this.ctx.getWebSockets();
    if (sockets.length >= 2 || (sockets.length === 1 && call.answered)) {
      return json({ error: 'This call already has two people' }, 409);
    }
    const role = sockets.length === 0 && !call.answered ? 'caller' : 'callee';
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, [role]);
    if (role === 'callee') {
      call.answered = true;
      await this.ctx.storage.put('call', call);
      // Ringing is over; the call now lasts as long as both stay connected.
      await this.ctx.storage.deleteAlarm();
      this.send('caller', { type: 'joined' });
    }
    server.send(JSON.stringify({ type: 'hello', role, video: call.video }));
    return new Response(null, { status: 101, webSocket: client });
  }

  async webSocketMessage(ws, message) {
    if (typeof message !== 'string' || message.length > MAX_SIGNAL_BYTES) return;
    let msg;
    try {
      msg = JSON.parse(message);
    } catch {
      return;
    }
    const role = this.ctx.getTags(ws)[0];
    if (msg.type === 'bye') {
      this.send(other(role), { type: 'bye' });
      await this.end();
      return;
    }
    // Only signaling passes through; anything else is dropped.
    if (!['offer', 'answer', 'ice', 'media'].includes(msg.type)) return;
    this.send(other(role), msg);
  }

  async webSocketClose(ws) {
    const role = this.ctx.getTags(ws)[0];
    this.send(other(role), { type: 'bye' });
    await this.end();
  }

  async webSocketError(ws) {
    await this.webSocketClose(ws);
  }

  // Nobody answered in time.
  async alarm() {
    this.send('caller', { type: 'timeout' });
    await this.end();
  }

  send(role, msg) {
    for (const ws of this.ctx.getWebSockets(role)) {
      try {
        ws.send(JSON.stringify(msg));
      } catch {
        // Already closed.
      }
    }
  }

  // Closes both sides and forgets the call, so its link stops working.
  async end() {
    for (const ws of this.ctx.getWebSockets()) {
      try {
        ws.close(1000, 'Call ended');
      } catch {
        // Already closed.
      }
    }
    await this.ctx.storage.deleteAlarm();
    await this.ctx.storage.deleteAll();
  }
}

function other(role) {
  return role === 'caller' ? 'callee' : 'caller';
}

function randomId() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
  });
}

function callPage() {
  return new Response(CALL_HTML, {
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'permissions-policy': 'camera=(self), microphone=(self)',
      'content-security-policy':
        "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; " +
        "connect-src 'self' wss:; media-src blob: mediastream:",
    },
  });
}

// The browser side of a call, for people who aren't using the app. It always
// answers (calls are started from the app).
const CALL_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Call</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin: 0; min-height: 100vh; font: 16px system-ui, sans-serif;
         background: #111; color: #eee; display: flex; flex-direction: column; }
  main { flex: 1; position: relative; display: grid; place-items: center; }
  #remote { width: 100%; height: 100%; max-height: calc(100vh - 88px); object-fit: contain; background: #000; }
  #local { position: absolute; right: 16px; bottom: 16px; width: 28vw; max-width: 200px;
           border-radius: 8px; background: #222; }
  #status { position: absolute; top: 16px; left: 16px; right: 16px; text-align: center; }
  nav { display: flex; gap: 12px; justify-content: center; padding: 16px; }
  button { font: inherit; padding: 12px 20px; border-radius: 999px; border: 0;
           background: #333; color: #eee; cursor: pointer; min-width: 96px; }
  button.primary { background: #1e8e3e; }
  button.end { background: #c62828; }
  [hidden] { display: none !important; }
</style></head>
<body>
<main>
  <video id="remote" autoplay playsinline></video>
  <video id="local" autoplay playsinline muted hidden></video>
  <p id="status">Opening call…</p>
</main>
<nav>
  <button id="join" class="primary" hidden>Join call</button>
  <button id="mute" hidden>Mute</button>
  <button id="camera" hidden>Camera off</button>
  <button id="hangup" class="end" hidden>Hang up</button>
</nav>
<script>
(() => {
  const $ = (id) => document.getElementById(id);
  const status = (t) => { $('status').textContent = t; $('status').hidden = !t; };
  const video = location.hash === '#video';
  const base = location.pathname;
  let pc, ws, local, ended = false;

  status(video ? 'You have been invited to a video call.' : 'You have been invited to a voice call.');
  $('join').hidden = false;

  function end(text) {
    if (ended) return;
    ended = true;
    try { ws && ws.readyState === 1 && ws.send(JSON.stringify({ type: 'bye' })); } catch (e) {}
    try { ws && ws.close(); } catch (e) {}
    try { pc && pc.close(); } catch (e) {}
    if (local) local.getTracks().forEach((t) => t.stop());
    ['mute', 'camera', 'hangup', 'join'].forEach((b) => ($(b).hidden = true));
    $('local').hidden = true;
    status(text);
  }

  $('join').onclick = async () => {
    $('join').hidden = true;
    status('Connecting…');
    try {
      local = await navigator.mediaDevices.getUserMedia({ audio: true, video });
    } catch (e) {
      end('Your browser blocked the ' + (video ? 'camera or microphone.' : 'microphone.'));
      return;
    }
    if (video) { $('local').srcObject = local; $('local').hidden = false; }
    const ice = await (await fetch(base + '/ice', { cache: 'no-store' })).json();
    pc = new RTCPeerConnection({ iceServers: ice.iceServers });
    local.getTracks().forEach((t) => pc.addTrack(t, local));
    pc.ontrack = (e) => { $('remote').srcObject = e.streams[0]; };
    pc.onicecandidate = (e) => {
      if (e.candidate) ws.send(JSON.stringify({ type: 'ice', candidate: e.candidate.toJSON() }));
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === 'connected') status('');
      if (pc.connectionState === 'failed') end('The call could not connect.');
    };
    ws = new WebSocket((location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + base + '/ws');
    ws.onmessage = async (e) => {
      const msg = JSON.parse(e.data);
      if (msg.type === 'offer') {
        await pc.setRemoteDescription(msg.description);
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        ws.send(JSON.stringify({ type: 'answer', description: pc.localDescription.toJSON() }));
      } else if (msg.type === 'ice' && msg.candidate) {
        try { await pc.addIceCandidate(msg.candidate); } catch (err) {}
      } else if (msg.type === 'bye') {
        end('The call has ended.');
      }
    };
    ws.onclose = () => end('The call has ended.');
    ws.onerror = () => end('This call has ended or the link is no longer valid.');
    ['mute', 'hangup'].forEach((b) => ($(b).hidden = false));
    $('camera').hidden = !video;
  };

  $('mute').onclick = () => {
    const t = local.getAudioTracks()[0];
    t.enabled = !t.enabled;
    $('mute').textContent = t.enabled ? 'Mute' : 'Unmute';
  };
  $('camera').onclick = () => {
    const t = local.getVideoTracks()[0];
    if (!t) return;
    t.enabled = !t.enabled;
    $('camera').textContent = t.enabled ? 'Camera off' : 'Camera on';
  };
  $('hangup').onclick = () => end('You left the call.');
  addEventListener('pagehide', () => end(''));
})();
</script></body></html>`;
