# Picture host (Cloudflare Worker + R2)

Stores the app's shared pictures. Pictures arrive already encrypted (the
key stays in the link after `#`), are deleted on their first view, and are
never kept longer than 4 hours (the 15-minute cron removes expired ones). See [docs/features/picture-sharing.md](../../docs/features/picture-sharing.md).

Free-tier friendly: Workers free plan, R2 free up to 10 GB stored.

## Deploy

Needs Node.js 20 or newer and a Cloudflare account with R2 turned on.

```sh
cd server/picture-host
npm install
npx wrangler login                      # approve in the browser
npx wrangler r2 bucket create irc-pictures
# Backstop: R2's shortest lifecycle rule is 1 day, so anything the cron
# somehow misses is still deleted within a day.
npx wrangler r2 bucket lifecycle add irc-pictures expire-pictures p/ --expire-days 1
npx wrangler secret put ADMIN_TOKEN     # long random string, for reviewing reports
npx wrangler deploy
```

`wrangler deploy` prints the address, for example
`https://irc-pictures.<you>.workers.dev`. Put it in `defaultPictureHost` in
`lib/features/pictures/data/picture_service.dart` (or build with
`--dart-define=PICTURE_HOST=...`).

To use your own domain, add a route or custom domain to the Worker in the
Cloudflare dashboard and use that address instead.

Optional: `npx wrangler secret put APP_TOKEN` makes uploads require an
`x-app-token` header; build the app with `--dart-define=PICTURE_APP_TOKEN=...`.

## Calls

The same Worker runs call signaling (`src/calls.js`): one `CallRoom`
Durable Object per call, created by `wrangler deploy` (see the
`[[migrations]]` in `wrangler.toml`). It passes connection messages between
the two people and keeps nothing after the call.

For the relay that hides people's IP addresses, create a TURN key in the
Cloudflare dashboard (**Realtime → TURN Server → Create**) and add it:

```sh
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
```

Without it, calls still work but connect directly (STUN only).

## Reviewing reports

```sh
curl -H "Authorization: Bearer $ADMIN_TOKEN" https://<host>/admin/reports
```

Each report has the picture's address (without its key), the sender,
network, reason and time. No copy of the picture is kept, so reports are
about who sent what, not the picture itself.

## Test

```sh
npm test
```
