// Files: uploaded like photos with X-Kind: file, kept until they expire.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { route, sweepExpired } from '../src/index.js';
import { MAX_FILE_BYTES } from '../src/limits.js';

class FakeBucket {
  constructor() { this.items = new Map(); }
  async put(key, value, opts = {}) {
    this.items.set(key, { bytes: new Uint8Array(value), customMetadata: opts.customMetadata ?? {} });
  }
  async get(key) {
    const item = this.items.get(key);
    if (!item) return null;
    return { customMetadata: item.customMetadata, arrayBuffer: async () => item.bytes.slice().buffer };
  }
  async delete(keys) { for (const k of [].concat(keys)) this.items.delete(k); }
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
const env = () => ({ PICTURES: new FakeBucket() });
const upload = (e, body, headers = {}, now = 1000) =>
  route(new Request(`${base}/upload`, { method: 'POST', body, headers }), e, now);

test('a file upload gets an /f/ link and can be downloaded again', async () => {
  const e = env();
  const res = await upload(e, new Uint8Array(64).fill(3), { 'x-kind': 'file', 'x-expires-in': '3600' });
  assert.equal(res.status, 201);
  const { id, url } = await res.json();
  assert.equal(url, `${base}/f/${id}`);
  for (const _ of [1, 2]) {
    const got = await route(new Request(`${url}/raw`), e, 2000);
    assert.equal(got.status, 200);
    assert.equal(got.headers.get('x-view-once'), null);
    assert.equal(new Uint8Array(await got.arrayBuffer())[0], 3);
  }
  // Gone once expired, and swept.
  const late = await route(new Request(`${url}/raw`), e, 1000 + 3600 * 1000 + 1);
  assert.equal(late.status, 404);
  assert.match((await late.json()).error, /file has expired/);
});

test('files may be bigger than photos, up to 25 MB', async () => {
  const e = env();
  const big = new Uint8Array(12 * 1024 * 1024);
  assert.equal((await upload(e, big)).status, 413);
  assert.equal((await upload(e, big, { 'x-kind': 'file' })).status, 201);
  const tooBig = await upload(e, new Uint8Array(MAX_FILE_BYTES + 1), { 'x-kind': 'file' });
  assert.equal(tooBig.status, 413);
  assert.match((await tooBig.json()).error, /25 MB/);
});

test('the download page is served, and the sweep removes old files', async () => {
  const e = env();
  const { url } = await (await upload(e, new Uint8Array(64), { 'x-kind': 'file', 'x-expires-in': '3600' })).json();
  const page = await route(new Request(url), e, 2000);
  assert.equal(page.status, 200);
  const html = await page.text();
  assert.match(html, /Download/);
  assert.doesNotMatch(page.headers.get('content-security-policy'), /img-src/);
  assert.equal(await sweepExpired(e, 1000 + 3600 * 1000 + 1), 1);
  assert.equal(e.PICTURES.items.size, 0);
});

test('a file link can be reported', async () => {
  const e = env();
  const { url } = await (await upload(e, new Uint8Array(64), { 'x-kind': 'file' })).json();
  const rep = await route(
    new Request(`${base}/report`, {
      method: 'POST',
      body: JSON.stringify({ link: `${url}#k=x&n=a.zip`, sender: 'troll', reason: 'Spam' }),
    }),
    e,
    3000,
  );
  assert.equal(rep.status, 201);
});
