# Sharing temporary pictures

Available on iOS, Android and macOS (shared Flutter code).

IRC can only carry text, so pictures travel as links to a small picture
server you run on Cloudflare. Pictures are encrypted on the sender's device
and delete themselves after a set time.

## Using it

- **Send:** in a private chat, tap the picture button left of the message
  box. On phones choose **Choose a photo** or **Take a photo**; on the Mac a
  file picker opens. Then pick how long it lasts (**1 hour** or **4 hours**,
  the default) and tap **Send picture**. Every picture is view-once: the
  server deletes it the first time it is downloaded. The message box shows "Encrypting and sending picture…" while
  it uploads.
- The message sent looks like
  `📷 Photo from dennis: https://<host>/p/<id>#k=<key>&o=1`. How long it
  lasts isn't shown; opening an expired photo says **This photo has expired.**
- **Receive:** the picture shows under the message.
  - It loads straight away for your own pictures and in private chats where
    you've already written to the person.
  - Otherwise it shows **Show photo from bob** first, because loading a
    picture tells its server your IP address.
  - View-once pictures always wait for a tap and are deleted from the
    server when opened (the app keeps it on screen until you leave).
  - Tap a picture to see it full size; pinch to zoom.
  - Expired or already-viewed pictures say so.
- **People on other IRC apps** see the link. It opens a page that decrypts
  the picture in their browser.
- **Report and block:** the ⋮ next to someone else's picture offers
  **Report picture** (pick a reason, optional details) and **Block bob**.
  Reporting also blocks the sender. Blocking is the same as **Ignore** on a
  profile card (tap a name), and Settings → Ignored people lists everyone
  blocked. Their messages, pictures and room invitations are hidden on
  every network.

## Privacy and safety

- Photos are re-encoded as JPEG at most 2048 px on the long side, turned
  upright, and stripped of EXIF (GPS location, camera, time), ICC and text
  metadata before anything leaves the device.
- Each picture gets a new random AES-256-GCM key. The key is only in the
  part of the link after `#`, which browsers and the app never send to a
  server, so the server stores and serves only encrypted bytes.
- Nothing is kept: the server never stores a picture longer than 4 hours,
  deletes it on its first download, and a report is stored as text only
  (the address without its key, the sender, network and reason). No copy
  of a reported picture is kept.
- The server refuses expired pictures, deletes them every 15 minutes, and has a
  rate limit of 20 uploads a minute per address and a 10 MB size limit.

## Setup

Picture sharing is off until the app knows the server address. Deploy the
Worker (steps in [server/picture-host/README.md](../../server/picture-host/README.md)),
then either set `defaultPictureHost` in
`lib/features/pictures/data/picture_service.dart` or build with
`--dart-define=PICTURE_HOST=https://your-host`. Until then the picture
button says "Picture sharing isn't set up yet."

## Implementation

- `lib/features/pictures/domain/picture_link.dart`: `PictureLink`
  (`find`, `raw`, `message`), `PictureExpiry`.
- `lib/features/pictures/data/picture_prep.dart`: `preparePicture` (runs in
  an isolate).
- `lib/features/pictures/data/picture_crypto.dart`: `sealPicture`,
  `openPicture`. Format: 12-byte nonce, ciphertext, 16-byte tag.
- `lib/features/pictures/data/picture_service.dart`: `PictureService`
  (`upload`, `download` with a small memory cache, `report`),
  `pictureServiceProvider`.
- `lib/features/pictures/presentation/picture_widgets.dart`: `sendPicture`,
  `PictureBubble`, report dialog, `PictureViewer`.
- `ChatController`: `sendPicture`, `reportPicture`, `blockUser`,
  `unblockUser`, `isBlocked` (saved under `blockedNicks`).
- Platform setup: iOS `NSPhotoLibraryUsageDescription` and
  `NSCameraUsageDescription`; macOS
  `com.apple.security.files.user-selected.read-only`. Android needs none.
- Tests: `test/features/pictures/pictures_test.dart`, the "pictures in a
  private chat" widget test, and `server/picture-host/test`.
