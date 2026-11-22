// Picture host for the IRC app: short-lived, end-to-end encrypted pictures.
//
// The app encrypts each picture (AES-256-GCM) before uploading. The key is
// only ever in the part of the link after `#`, which browsers and apps never
// send to a server, so this Worker stores and serves scrambled bytes only.
//
// Routes
//   POST /upload            body = encrypted bytes. Headers:
//                             X-Expires-In: seconds (3600 or 14400; 4 hours
//                             is the most a picture is ever kept)
//                           Every picture is view-once: it is deleted as soon
//                           as it has been downloaded the first time.
//                           -> 201 {"id","url","expiresAt"}
//   GET  /p/<id>/raw        encrypted bytes (404 when expired or viewed)
//   GET  /p/<id>            viewer page: decrypts in the browser, for people
//                           on other IRC apps who just click the link
//   POST /report            {"link","sender","network","reason"} -> 201.
//                           Records the report as text only (no key, no copy
//                           of the picture is kept).
//   GET  /admin/reports     reports list (Authorization: Bearer ADMIN_TOKEN)
//
// Expired pictures are refused on read and removed by the cron below, which
// runs every 15 minutes. An R2 lifecycle rule (see README) is the backstop.

export const MAX_BYTES = 10 * 1024 * 1024;
export const EXPIRY_CHOICES = [3600, 14400];
export const DEFAULT_EXPIRY = 14400;
const ID_PATTERN = /^[A-Za-z0-9_-]{22}$/;

export default {
  async fetch(request, env) {
    try {
      return await route(request, env);
    } catch (e) {
      console.error(e);
      return json({ error: 'Something went wrong' }, 500);
    }
  },

  async scheduled(_event, env) {
    await sweepExpired(env, Date.now());
  },
};

export async function route(request, env, now = Date.now()) {
  const url = new URL(request.url);
  const path = url.pathname;
  if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));

  if (request.method === 'POST' && path === '/upload') {
    return cors(await upload(request, env, url, now));
  }
  if (request.method === 'POST' && path === '/report') {
    return cors(await report(request, env, now));
  }
  let m = path.match(/^\/p\/([^/]+)\/raw$/);
  if (request.method === 'GET' && m) return cors(await raw(env, m[1], now));
  m = path.match(/^\/p\/([^/]+)$/);
  if (request.method === 'GET' && m && ID_PATTERN.test(m[1])) {
    return viewerPage();
  }
  if (path.startsWith('/admin/')) return admin(request, env, path);
  if (request.method === 'GET' && path === '/') {
    return new Response('Picture host is running.\n', {
      headers: { 'content-type': 'text/plain; charset=utf-8' },
    });
  }
  return json({ error: 'Not found' }, 404);
}

async function upload(request, env, url, now) {
  if (env.UPLOAD_LIMIT) {
    const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
    const { success } = await env.UPLOAD_LIMIT.limit({ key: ip });
    if (!success) return json({ error: 'Too many uploads. Try again in a minute.' }, 429);
  }
  if (env.APP_TOKEN && request.headers.get('x-app-token') !== env.APP_TOKEN) {
    return json({ error: 'Not allowed' }, 403);
  }
  const expiresIn = Number(request.headers.get('x-expires-in') ?? DEFAULT_EXPIRY);
  if (!EXPIRY_CHOICES.includes(expiresIn)) {
    return json({ error: 'Unsupported expiry' }, 400);
  }
  const declared = Number(request.headers.get('content-length') ?? 0);
  if (declared > MAX_BYTES) return json({ error: 'Picture is too large' }, 413);
  const body = await request.arrayBuffer();
  // 12-byte nonce + 16-byte tag at least.
  if (body.byteLength < 29) return json({ error: 'Empty upload' }, 400);
  if (body.byteLength > MAX_BYTES) return json({ error: 'Picture is too large' }, 413);

  const id = randomId();
  const expiresAt = now + expiresIn * 1000;
  await env.PICTURES.put(`p/${id}`, body, {
    httpMetadata: { contentType: 'application/octet-stream' },
    customMetadata: { expiresAt: String(expiresAt), viewOnce: '1' },
  });
  return json({ id, url: `${url.origin}/p/${id}`, expiresAt }, 201);
}

async function raw(env, id, now) {
  if (!ID_PATTERN.test(id)) return json({ error: 'Not found' }, 404);
  const key = `p/${id}`;
  const object = await env.PICTURES.get(key);
  if (!object) return json({ error: 'This picture has expired' }, 404);
  const meta = object.customMetadata ?? {};
  if (Number(meta.expiresAt ?? 0) <= now) {
    await env.PICTURES.delete(key);
    return json({ error: 'This picture has expired' }, 404);
  }
  const bytes = await object.arrayBuffer();
  // Every picture is view-once: gone after the first download.
  await env.PICTURES.delete(key);
  return new Response(bytes, {
    headers: {
      'content-type': 'application/octet-stream',
      'cache-control': 'no-store',
      'x-expires-at': String(meta.expiresAt),
      'x-view-once': '1',
    },
  });
}

async function report(request, env, now) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Bad report' }, 400);
  }
  const link = String(body.link ?? '').slice(0, 500);
  const id = link.match(/\/p\/([A-Za-z0-9_-]{22})/)?.[1];
  if (!id) return json({ error: 'Bad report' }, 400);
  // Text only: the key (after `#`) is dropped and no copy of the picture is
  // kept, so nothing viewable is stored past the picture's own expiry.
  const record = {
    link: link.split('#')[0],
    id,
    sender: String(body.sender ?? '').slice(0, 64),
    network: String(body.network ?? '').slice(0, 128),
    reason: String(body.reason ?? '').slice(0, 1000),
    reportedAt: new Date(now).toISOString(),
  };
  await env.PICTURES.put(`reports/${now}-${randomId()}.json`, JSON.stringify(record), {
    httpMetadata: { contentType: 'application/json' },
  });
  return json({ ok: true }, 201);
}

async function admin(request, env, path) {
  const auth = request.headers.get('authorization') ?? '';
  if (!env.ADMIN_TOKEN || auth !== `Bearer ${env.ADMIN_TOKEN}`) {
    return json({ error: 'Not allowed' }, 401);
  }
  if (path === '/admin/reports') {
    const listed = await env.PICTURES.list({ prefix: 'reports/', limit: 1000 });
    const reports = [];
    for (const o of listed.objects) {
      const r = await env.PICTURES.get(o.key);
      if (r) reports.push(await r.json());
    }
    reports.sort((a, b) => (a.reportedAt < b.reportedAt ? 1 : -1));
    return json({ reports });
  }
  return json({ error: 'Not found' }, 404);
}

/** Deletes expired pictures. Returns how many were removed. */
export async function sweepExpired(env, now) {
  let cursor;
  let removed = 0;
  do {
    const page = await env.PICTURES.list({
      prefix: 'p/',
      cursor,
      limit: 1000,
      include: ['customMetadata'],
    });
    const expired = page.objects
      .filter((o) => Number(o.customMetadata?.expiresAt ?? 0) <= now)
      .map((o) => o.key);
    if (expired.length) {
      await env.PICTURES.delete(expired);
      removed += expired.length;
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  return removed;
}

function randomId() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return base64url(bytes);
}

function base64url(bytes) {
  let s = '';
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'content-type': 'application/json' },
  });
}

function cors(response) {
  const r = new Response(response.body, response);
  r.headers.set('access-control-allow-origin', '*');
  r.headers.set('access-control-allow-methods', 'GET, POST, OPTIONS');
  r.headers.set(
    'access-control-allow-headers',
    'content-type, x-expires-in, x-view-once, x-app-token',
  );
  r.headers.set('access-control-expose-headers', 'x-expires-at, x-view-once');
  return r;
}

// The viewer decrypts with the key from the link's `#k=` part, in the
// browser. The key never reaches this server.
function viewerPage() {
  return new Response(VIEWER_HTML, {
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'content-security-policy':
        "default-src 'none'; img-src blob:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'",
    },
  });
}

const VIEWER_HTML = `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Shared picture</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center;
         font: 16px system-ui, sans-serif; background: #111; color: #eee; }
  img { max-width: 100vw; max-height: 100vh; object-fit: contain; }
  p { padding: 16px; text-align: center; }
</style></head>
<body><p id="msg">Opening picture…</p>
<script>
(async () => {
  const msg = document.getElementById('msg');
  try {
    const key = new URLSearchParams(location.hash.slice(1)).get('k');
    if (!key) throw new Error('This link is missing its key.');
    // Every picture is view-once.
    if (!confirm('This picture can be viewed only once. Show it now?')) {
      msg.textContent = 'Not opened. Reload to view it.';
      return;
    }
    const res = await fetch(location.pathname + '/raw', { cache: 'no-store' });
    if (!res.ok) throw new Error('This picture has expired or was already viewed.');
    const data = new Uint8Array(await res.arrayBuffer());
    const b64 = key.replace(/-/g, '+').replace(/_/g, '/');
    const raw = Uint8Array.from(atob(b64 + '='.repeat((4 - b64.length % 4) % 4)), c => c.charCodeAt(0));
    const k = await crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['decrypt']);
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: data.slice(0, 12) }, k, data.slice(12));
    const img = document.createElement('img');
    img.alt = 'Shared picture';
    img.src = URL.createObjectURL(new Blob([plain], { type: 'image/jpeg' }));
    msg.replaceWith(img);
  } catch (e) {
    msg.textContent = e.message || 'Could not open this picture.';
  }
})();
</script></body></html>`;
