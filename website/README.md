# ircage.com

The IRCage website: a static site with no build step, hosted on Netlify.

- `index.html`: home page.
- `privacy.html`, `terms.html`, `support.html`, `404.html`.
- `styles.css`: the app's colours (`lib/core/theme/tokens.dart`), light and
  dark.
- `assets/`: icons made from the app icon.
- `netlify.toml`: security headers, caching, `www` → `ircage.com`.

The terms here match the ones in the app (`lib/app/legal.dart`); change both
together. The privacy policy describes what the app and
`server/picture-host` do; update it when either changes.

## Netlify

New site → import this GitHub repository → **Base directory** `website`,
**Build command** empty, **Publish directory** `website` (Netlify fills it
in from the base). Netlify serves `/privacy` for `privacy.html` on its own.

Preview locally: `python3 -m http.server -d website 8090` and open
http://127.0.0.1:8090 (use `/privacy.html` there, the short URLs are
Netlify's).
