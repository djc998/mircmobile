# Sending files

Available on iOS, Android and macOS (shared Flutter code), in private
chats, like photos. Uses the same picture host
([picture-sharing.md](picture-sharing.md)).

## What the user sees

- **Send:** **+** → **Send a file** in a private chat, pick any file (25 MB
  at most), choose how long the link works (**1 hour** or **4 hours**) and
  tap **Send file**. The message box shows the upload, and the other person
  gets `📎 File from you: notes.pdf (1.2 MB) <link>`.
- **Receive:** a card under the message with the file's name, size and who
  sent it, and **Save**. Saving downloads and decrypts it, then opens the
  share sheet on iPhone and Android (Save to Files, Drive, Downloads, or
  another app) or a save dialog on the Mac.
- **Other IRC apps** see the link; opening it shows a download page that
  decrypts the file in the browser and saves it under its name.
- Unlike photos, files aren't view-once: if a save fails it can be tried
  again until the link expires.
- Ignored people's messages (and files) aren't shown. Only open files from
  people you trust.

## Privacy

The file is encrypted on the device (AES-256-GCM) before it's uploaded. The
key and the file's name are only in the part of the link after `#`, which
is never sent to the server, so the server stores an unnamed, scrambled
blob and deletes it when it expires (the cron sweep removes leftovers every
15 minutes).

## Server

`POST /upload` with `X-Kind: file` stores up to 25 MB under `f/<id>` (not
view-once) and returns `https://host/f/<id>`. `GET /f/<id>/raw` serves the
encrypted bytes until expiry; `GET /f/<id>` is the download page. Reports
accept file links too. **Redeploy the picture host** (`npx wrangler
deploy` in `server/picture-host`) before using this.

The upload limits now live in `src/limits.js`: the Workers runtime treats
every named export of the entry module as an entry point, and newer
versions (including `wrangler dev`) refuse ones that aren't handlers.

## Code

- `lib/features/pictures/domain/file_link.dart`: `FileLink` (`find`,
  `message`, `raw`), `safeFileName`, `formatFileSize`, `maxFileBytes`.
- `lib/features/pictures/data/picture_service.dart`: `uploadFile`,
  `downloadFile`.
- `lib/features/pictures/presentation/file_widgets.dart`: `sendFile`,
  `FileBubble`, `filePickerProvider` (`file_selector`), `fileSaverProvider`
  (`share_plus` on phones, a save dialog on the Mac).
- `ChatController.sendFile`; the composer's `onSendFile`; files shown under
  their message in `chat_screen.dart`.
- macOS: `com.apple.security.files.user-selected.read-write` (was
  read-only) so the save dialog can write.

## Tests

`test/features/pictures/files_test.dart` (links, safe names, sizes,
encrypted upload and download, sending from the + menu and saving one) and
`server/picture-host/test/files.test.js`. Checked against the Worker
running locally with `wrangler dev`: a 3 MB file went up and came back
byte for byte, twice.
