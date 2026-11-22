// Runs with Node 20+: `npm test`. Uses an in-memory stand-in for R2.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route, sweepExpired } from '../src/index.js';

class FakeBucket {
  constructor() { this.items = new Map(); }
  async put(key, value, opts = {}) {
    const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : new Uint8Array(value);
    this.items.set(key, { bytes, customMetadata: opts.customMetadata ?? {} });
  }
  async get(key) {
    const item = this.items.get(key);
    if (!item) return null;
    return {
      customMetadata: item.customMetadata,
      arrayBuffer: async () => item.bytes.slice().buffer,
      json: async () => JSON.parse(new TextDecoder().decode(item.bytes)),
    };
  }
  async delete(keys) {
    for (const k of [].concat(keys)) this.items.delete(k);
  }
  async list({ prefix }) {
    return {
      objects: [...this.items.entries()]
        .filter(([k]) => k.startsWith(prefix))
        .map(([key, v]) => ({ key, customMetadata: v.customMetadata })),
      truncated: false,
    };
  }
}

const base = 'https://pics.test';
const sealed = new Uint8Array(64).fill(7);

function env(extra = {}) {
  return { PICTURES: new FakeBucket(), ...extra };
}

async function upload(e, headers = {}, now = 1000) {
  const res = await route(
    new Request(`${base}/upload`, { method: 'POST', body: sealed, headers }),
    e,
    now,
  );
  return { res, body: await res.json() };
}

test('upload then download the encrypted bytes', async () => {
  const e = env();
  const { res, body } = await upload(e, { 'x-expires-in': '3600' });
  assert.equal(res.status, 201);
  assert.match(body.id, /^[A-Za-z0-9_-]{22}$/);
  assert.equal(body.url, `${base}/p/${body.id}`);
  assert.equal(body.expiresAt, 1000 + 3600 * 1000);
  const defaulted = await upload(e, {}, 0);
  assert.equal(defaulted.body.expiresAt, 4 * 3600 * 1000);
  const got = await route(new Request(`${body.url}/raw`), e, 2000);
  assert.equal(got.status, 200);
  assert.deepEqual(new Uint8Array(await got.arrayBuffer()), sealed);
  assert.equal(got.headers.get('access-control-allow-origin'), '*');
});

test('expired pictures are refused and deleted', async () => {
  const e = env();
  const { body } = await upload(e, { 'x-expires-in': '3600' });
  const later = 1000 + 3600 * 1000 + 1;
  const got = await route(new Request(`${body.url}/raw`), e, later);
  assert.equal(got.status, 404);
  assert.equal(e.PICTURES.items.size, 0);
});

test('every picture is deleted after the first view', async () => {
  const e = env();
  const { body } = await upload(e);
  assert.equal((await route(new Request(`${body.url}/raw`), e, 2000)).status, 200);
  assert.equal((await route(new Request(`${body.url}/raw`), e, 2000)).status, 404);
});

test('rejects unsupported expiry, empty and oversized uploads', async () => {
  const e = env();
  assert.equal((await upload(e, { 'x-expires-in': '999999' })).res.status, 400);
  // Nothing is kept longer than 4 hours.
  assert.equal((await upload(e, { 'x-expires-in': '86400' })).res.status, 400);
  const empty = await route(
    new Request(`${base}/upload`, { method: 'POST', body: new Uint8Array(3) }),
    e,
  );
  assert.equal(empty.status, 400);
  const big = await route(
    new Request(`${base}/upload`, {
      method: 'POST',
      body: new Uint8Array(10 * 1024 * 1024 + 1),
    }),
    e,
  );
  assert.equal(big.status, 413);
});

test('app token and rate limit are enforced when configured', async () => {
  const e = env({ APP_TOKEN: 'secret' });
  assert.equal((await upload(e)).res.status, 403);
  assert.equal((await upload(e, { 'x-app-token': 'secret' })).res.status, 201);
  const limited = env({ UPLOAD_LIMIT: { limit: async () => ({ success: false }) } });
  assert.equal((await upload(limited)).res.status, 429);
});

test('a report is stored as text only and listed for the admin', async () => {
  const e = env({ ADMIN_TOKEN: 'adm' });
  const { body } = await upload(e);
  const link = `${body.url}#k=abc`;
  const rep = await route(
    new Request(`${base}/report`, {
      method: 'POST',
      body: JSON.stringify({ link, sender: 'troll', network: 'irc.libera.chat', reason: 'spam' }),
    }),
    e,
    5000,
  );
  assert.equal(rep.status, 201);
  assert.ok(![...e.PICTURES.items.keys()].some((k) => k.startsWith('reported/')));

  const denied = await route(new Request(`${base}/admin/reports`), e);
  assert.equal(denied.status, 401);
  const list = await route(
    new Request(`${base}/admin/reports`, { headers: { authorization: 'Bearer adm' } }),
    e,
  );
  const { reports } = await list.json();
  assert.equal(reports.length, 1);
  assert.equal(reports[0].link, body.url);
  assert.equal(reports[0].sender, 'troll');
  assert.equal(reports[0].kept, undefined);
});

test('the viewer page is served without the key reaching the server', async () => {
  const e = env();
  const { body } = await upload(e);
  const page = await route(new Request(body.url), e);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type'), /text\/html/);
  assert.match(await page.text(), /AES-GCM/);
});

test('the sweep removes only expired pictures', async () => {
  const e = env();
  await upload(e, { 'x-expires-in': '3600' }, 0);
  await upload(e, { 'x-expires-in': '14400' }, 0);
  assert.equal(await sweepExpired(e, 3600 * 1000 + 1), 1);
  assert.equal(e.PICTURES.items.size, 1);
});
