// Runs with Node 20+: `npm test`. Uses in-memory stand-ins for the Durable
// Object runtime (storage, hibernatable WebSockets) and WebSocketPair.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route } from '../src/index.js';
import { CallRoom, RING_MS, iceServers } from '../src/calls.js';

class FakeSocket {
  constructor() {
    this.sent = [];
    this.closed = false;
  }
  send(data) {
    if (this.closed) throw new Error('closed');
    this.sent.push(JSON.parse(data));
  }
  close() {
    this.closed = true;
  }
}

// Node has no WebSocketPair; the room only needs two linked ends.
globalThis.WebSocketPair = class {
  constructor() {
    this[0] = new FakeSocket();
    this[1] = new FakeSocket();
  }
};

// Node's Response refuses status 101; the runtime allows it for upgrades.
const RealResponse = globalThis.Response;
globalThis.Response = class extends RealResponse {
  constructor(body, init = {}) {
    if (init.status === 101) {
      super(body, { ...init, status: 200 });
      Object.defineProperty(this, 'status', { value: 101 });
      this.webSocket = init.webSocket;
    } else {
      super(body, init);
    }
  }
};

class FakeCtx {
  constructor() {
    this.data = new Map();
    this.alarmAt = null;
    this.sockets = [];
    this.storage = {
      get: async (k) => this.data.get(k),
      put: async (k, v) => void this.data.set(k, structuredClone(v)),
      deleteAll: async () => void this.data.clear(),
      setAlarm: async (t) => void (this.alarmAt = t),
      deleteAlarm: async () => void (this.alarmAt = null),
    };
  }
  acceptWebSocket(ws, tags) {
    ws.tags = tags;
    this.sockets.push(ws);
  }
  getWebSockets(tag) {
    return this.sockets.filter((s) => !s.closed && (!tag || s.tags.includes(tag)));
  }
  getTags(ws) {
    return ws.tags;
  }
}

// A namespace that hands out one CallRoom per call id.
function env(extra = {}) {
  const rooms = new Map();
  return {
    rooms,
    CALLS: {
      idFromName: (name) => name,
      get: (id) => {
        if (!rooms.has(id)) {
          const ctx = new FakeCtx();
          rooms.set(id, { ctx, room: new CallRoom(ctx, {}) });
        }
        const { room } = rooms.get(id);
        return { fetch: (req) => room.fetch(req) };
      },
    },
    ...extra,
  };
}

const base = 'https://pics.test';

async function startCall(e, video = true, now = 1000) {
  const res = await route(
    new Request(`${base}/call`, { method: 'POST', body: JSON.stringify({ video }) }),
    e,
    now,
  );
  return { res, body: await res.json() };
}

function wsRequest(id) {
  return new Request(`${base}/c/${id}/ws`, { headers: { upgrade: 'websocket' } });
}

async function join(e, id) {
  const res = await route(wsRequest(id), e);
  return { res, server: e.rooms.get(id).ctx.sockets.at(-1) };
}

test('starting a call returns a link and rings for ten minutes', async () => {
  const e = env();
  const { res, body } = await startCall(e, true, 1000);
  assert.equal(res.status, 201);
  assert.match(body.id, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(body.url, `${base}/c/${body.id}#video`);
  assert.equal(body.expiresAt, 1000 + RING_MS);
  assert.equal(e.rooms.get(body.id).ctx.alarmAt, 1000 + RING_MS);
  const voice = await startCall(e, false);
  assert.ok(voice.body.url.endsWith('#voice'));
});

test('caller and callee are matched and signaling is forwarded', async () => {
  const e = env();
  const { body } = await startCall(e);
  const { room, ctx } = e.rooms.get(body.id);

  const caller = await join(e, body.id);
  assert.equal(caller.res.status, 101);
  assert.deepEqual(caller.server.sent[0], { type: 'hello', role: 'caller', video: true });

  const callee = await join(e, body.id);
  assert.equal(callee.res.status, 101);
  assert.deepEqual(callee.server.sent[0], { type: 'hello', role: 'callee', video: true });
  assert.deepEqual(caller.server.sent.at(-1), { type: 'joined' });
  // Answered: no more ringing timeout.
  assert.equal(ctx.alarmAt, null);

  const offer = { type: 'offer', description: { type: 'offer', sdp: 'v=0' } };
  await room.webSocketMessage(caller.server, JSON.stringify(offer));
  assert.deepEqual(callee.server.sent.at(-1), offer);
  const ice = { type: 'ice', candidate: { candidate: 'c', sdpMid: '0' } };
  await room.webSocketMessage(callee.server, JSON.stringify(ice));
  assert.deepEqual(caller.server.sent.at(-1), ice);

  // Unknown message types and junk are dropped.
  await room.webSocketMessage(callee.server, JSON.stringify({ type: 'evil' }));
  await room.webSocketMessage(callee.server, 'not json');
  assert.deepEqual(caller.server.sent.at(-1), ice);
});

test('a third person cannot join', async () => {
  const e = env();
  const { body } = await startCall(e);
  await join(e, body.id);
  await join(e, body.id);
  const third = await route(wsRequest(body.id), e);
  assert.equal(third.status, 409);
});

test('hanging up ends the call for both and the link stops working', async () => {
  const e = env();
  const { body } = await startCall(e);
  const { room } = e.rooms.get(body.id);
  const caller = await join(e, body.id);
  const callee = await join(e, body.id);
  await room.webSocketMessage(callee.server, JSON.stringify({ type: 'bye' }));
  assert.deepEqual(caller.server.sent.at(-1), { type: 'bye' });
  assert.ok(caller.server.closed && callee.server.closed);
  assert.equal((await route(wsRequest(body.id), e)).status, 410);
});

test('closing the connection counts as hanging up', async () => {
  const e = env();
  const { body } = await startCall(e);
  const { room } = e.rooms.get(body.id);
  const caller = await join(e, body.id);
  const callee = await join(e, body.id);
  callee.server.closed = true;
  await room.webSocketClose(callee.server);
  assert.deepEqual(caller.server.sent.at(-1), { type: 'bye' });
  assert.equal(e.rooms.get(body.id).ctx.data.size, 0);
});

test('declining tells the caller', async () => {
  const e = env();
  const { body } = await startCall(e);
  const caller = await join(e, body.id);
  const res = await route(new Request(`${base}/c/${body.id}/decline`, { method: 'POST' }), e);
  assert.equal(res.status, 200);
  assert.deepEqual(caller.server.sent.at(-1), { type: 'declined' });
  assert.equal((await route(wsRequest(body.id), e)).status, 410);
});

test('nobody answering ends the call', async () => {
  const e = env();
  const { body } = await startCall(e);
  const { room } = e.rooms.get(body.id);
  const caller = await join(e, body.id);
  await room.alarm();
  assert.deepEqual(caller.server.sent.at(-1), { type: 'timeout' });
  assert.equal((await route(wsRequest(body.id), e)).status, 410);
});

test('unknown calls and bad ids are refused; the call page is served', async () => {
  const e = env();
  assert.equal((await route(wsRequest('AAAAAAAAAAAAAAAAAAAAAA'), e)).status, 410);
  assert.equal((await route(new Request(`${base}/c/bad`), e)).status, 404);
  const page = await route(new Request(`${base}/c/AAAAAAAAAAAAAAAAAAAAAA`), e);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /RTCPeerConnection/);
});

test('calls respect the rate limit and app token', async () => {
  const limited = env({ CALL_LIMIT: { limit: async () => ({ success: false }) } });
  assert.equal((await startCall(limited)).res.status, 429);
  const tokened = env({ APP_TOKEN: 'secret' });
  assert.equal((await startCall(tokened)).res.status, 403);
});

test('relay servers are used when a TURN key is set up', async () => {
  assert.deepEqual(await iceServers({}), {
    iceServers: [{ urls: ['stun:stun.cloudflare.com:3478'] }],
    relay: false,
  });
  let called;
  const fake = async (url, init) => {
    called = { url, init };
    return new Response(
      JSON.stringify({ iceServers: { urls: ['turn:turn.cloudflare.com:3478'], username: 'u', credential: 'p' } }),
    );
  };
  const result = await iceServers({ TURN_KEY_ID: 'k', TURN_KEY_API_TOKEN: 't' }, fake);
  assert.equal(result.relay, true);
  assert.equal(result.iceServers[0].username, 'u');
  assert.match(called.url, /\/turn\/keys\/k\/credentials\/generate-ice-servers$/);
  assert.equal(called.init.headers.authorization, 'Bearer t');
  // A failing TURN service falls back to direct connections.
  const broken = await iceServers(
    { TURN_KEY_ID: 'k', TURN_KEY_API_TOKEN: 't' },
    async () => new Response('', { status: 500 }),
  );
  assert.equal(broken.relay, false);
});
