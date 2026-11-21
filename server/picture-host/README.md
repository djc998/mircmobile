# Picture host (Cloudflare Worker + R2)

Stores the app's shared pictures. Pictures arrive already encrypted (the
key stays in the link after `#`), expire after 1 hour to 3 days, and can be
view-once. See [docs/features/picture-sharing.md](../../docs/features/picture-sharing.md).

Free-tier friendly: Workers free plan, R2 free up to 10 GB stored.

## Deploy

Needs Node.js 20 or newer and a Cloudflare account with R2 turned on.

```sh
cd server/picture-host
npm install
npx wrangler login                      # approve in the browser
npx wrangler r2 bucket create irc-pictures
# Backstop: anything older than 4 days is deleted even if the cron misses it.
npx wrangler r2 bucket lifecycle add irc-pictures expire-pictures p/ --expire-days 4
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

## Reviewing reports

```sh
curl -H "Authorization: Bearer $ADMIN_TOKEN" https://<host>/admin/reports
```

Each report has the full link (open it in a browser to see the picture),
the sender, network, reason and time. A reported picture is kept under
`reported/<id>` past its expiry. Delete it with
`npx wrangler r2 object delete irc-pictures/reported/<id>` when done.

## Test

```sh
npm test
```
