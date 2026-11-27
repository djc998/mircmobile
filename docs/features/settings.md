# Settings

Available on iOS, Android and macOS. Phase 5 of the
[IRCage UI redesign](../design/ui-redesign.md).

Open **Settings** from **You**, or **IRCage → Settings…** (⌘,) on a Mac.
Grouped lists, like the system settings:

- **Look:** Appearance (theme, accent, density, message font, text size;
  see [appearance.md](appearance.md)).
- **Notifications** (iOS, Android, macOS): private messages and mentions
  while the app is in the background; on Android, **Stay connected in
  the background**; on iOS, a note that staying online needs a bouncer
  ([background.md](background.md)).
- **Safety:** hide offensive words; hide adult rooms in Discover
  ([safety.md](safety.md)).
- **Chat history:** save chat history on this device; delete saved
  history ([chat-history.md](chat-history.md)).
- **Calls:** hide my IP address on calls; camera and microphone access
  ([calls.md](calls.md)).
- **Ignored people:** everyone you've ignored, with **Stop ignoring**.
- **Muted chats:** every muted room and private chat, with **Unmute**.
- **About:** version, **Terms of use**, contact address and open-source
  licenses.

The same history and call switches are still under the welcome screen's
Advanced options.

## Code

`lib/features/settings/presentation/settings_screen.dart` (route
`/settings`).

## Tests

`test/features/polish/polish_test.dart` (ignored people, muted chats);
`test/features/notifications/notifications_test.dart` (Notifications);
`test/accessibility/a11y_test.dart` (settings meets the guidelines).
