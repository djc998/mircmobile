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
npx wrangler r2 bucket lifecycle add irc-pictures expire-files f/ --expire-days 1
npx wrangler secret put ADMIN_TOKEN     # long random string, for reviewing reports
npx wrangler deploy
```

`wrangler deploy` prints the addresses. IRCage's Worker answers at
`https://share.ircage.com` (a custom domain in `wrangler.toml`; ircage.com's
DNS is on Cloudflare, which creates the record and certificate) and still at
`https://irc-pictures.irc-pictures.workers.dev` for builds from before the
move. The app's address is `defaultPictureHost` in
`lib/features/pictures/data/picture_service.dart` (or build with
`--dart-define=PICTURE_HOST=...`).

Optional: `npx wrangler secret put APP_TOKEN` makes uploads require an
`x-app-token` header; build the app with `--dart-define=PICTURE_APP_TOKEN=...`.

## Calls

The same Worker runs call signaling (`src/calls.js`): one `CallRoom`
Durable Object per call, created by `wrangler deploy` (see the
`[[migrations]]` in `wrangler.toml`). It passes connection messages between
the two people and keeps nothing after the call.

For the relay that hides people's IP addresses, create a TURN key in the
Cloudflare dashboard (**Realtime → TURN Server → Create**) and add it:

Easiest: run `./set-turn-key.sh`. It asks for the Turn Token ID and API
Token (without showing them), checks them with Cloudflare, and only then
saves them as the `TURN_KEY_ID` and `TURN_KEY_API_TOKEN` secrets. Or by hand:

```sh
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
```

Both values must come from **Realtime → TURN Server** (a Serverless SFU
app's ID and secret look similar but don't work). Without them, calls
still work but connect directly (STUN only).

## Reviewing reports

```sh
./check-reports.sh          # readable list, newest first, last 24 hours marked NEW
./check-reports.sh --json   # the raw JSON
```

It asks for the admin token (or uses `$ADMIN_TOKEN` if it's set) and
checks `https://share.ircage.com`; set `PICTURE_HOST`
for another deployment. The raw endpoint is
`GET /admin/reports` with `Authorization: Bearer <ADMIN_TOKEN>`.

Each report has the picture's address (without its key), the sender,
network, reason and time. No copy of the picture is kept, so reports are
about who sent what, not the picture itself.

Reports of chat messages have `"kind": "message"` with the message `text`
as the reporter saw it, the `sender`, `network`, `room` (null for a private
chat), reason and time.

The app's terms promise reports are reviewed **within 24 hours** (Apple
asks for this), so check this list at least daily. Redeploy the Worker
(`npx wrangler deploy`) to accept message reports.

## Test

```sh
npm test
```
