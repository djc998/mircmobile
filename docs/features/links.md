# Links, and image and video previews

Available on iOS, Android, macOS, Windows and Linux. Videos play inside
the app on iOS, Android and macOS; on Windows and Linux they open in the
browser (the `video_player` plugin has no Windows or Linux version).

## Tappable links

- Web links in messages (`http://…`, `https://…` and `www.…`) are
  underlined in the accent colour and open in the browser when tapped or
  clicked. The mouse pointer becomes a hand over them on computers.
- Punctuation that ends a sentence isn't part of the link
  (`see https://x.org.`), and neither is a closing bracket with no opening
  one, so `(https://x.org)` works and Wikipedia's `Dart_(language)` links
  stay whole.
- IRCage's own photo, file and call links (`share.ircage.com/p/…#k=…`)
  aren't made tappable: they have their own cards, and opening a
  view-once photo in a browser would use up its one view.
- Offensive words are still masked inside links when the filter is on;
  the link opens the real address.

## Image and video previews

When a message links straight to an image (`.png`, `.jpg`, `.jpeg`,
`.gif`, `.webp`, `.bmp`) or a video (`.mp4`, `.m4v`, `.mov`, `.webm`),
a card appears under it. Only the first such link in a message gets one.

- **Nothing loads until you tap it:** "Show image from i.imgur.com",
  "Play video from example.com". Loading it lets that website see your IP
  address, so the card names the website first.
- **Show images from links automatically** (Appearance, off by default)
  loads images without the tap. Videos always wait for a tap. Your own
  links always load.
- Images show up to 320×240 and open full screen with pinch to zoom, the
  same viewer as photos. Videos play inline: tap to pause or play, drag
  the bar to seek.
- The ⋮ menu has **Open in browser** and **Copy link**.
- Only `https` links get a preview, so nothing is loaded unencrypted.
- Limits: the server must say it's an image (`Content-Type: image/…`),
  at most 15 MB, 20 seconds; otherwise the card says why ("That link isn't
  an image.", "The image is too big to preview."). Images are decoded at
  the size they're shown, so a huge one can't use up memory. The last 30
  images are kept in memory so scrolling back doesn't load them again.
- Nothing is fetched to decide whether a link is an image: it's judged by
  the end of the address only.

## Code

- `lib/core/links/chat_link.dart`: `findLinks`, `mediaOf`, `isShareLink`,
  `firstMediaLink`.
- `lib/core/links/open_link.dart`: `openLink` (url_launcher, in the
  browser).
- `lib/core/ui/mirc_text.dart`: `mircSpans(links:, linkStyle:)` and
  `LinkTaps`, which owns the tap handlers for one message.
- `lib/features/links/data/link_media_service.dart`: `LinkMediaService`.
- `lib/features/links/presentation/link_preview.dart`: `LinkPreview`.
- Tests: `test/core/links/chat_link_test.dart`,
  `test/features/links/link_preview_test.dart`.
