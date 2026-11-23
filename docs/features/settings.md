# Settings

Available on iOS, Android and macOS. Phase 5 of the
[IRCage UI redesign](../design/ui-redesign.md).

Open **Settings** from **You**, or **IRCage → Settings…** (⌘,) on a Mac.
Grouped lists, like the system settings:

- **Look:** Appearance (theme, accent, density, message font, text size;
  see [appearance.md](appearance.md)).
- **Chat history:** save chat history on this device; delete saved
  history ([chat-history.md](chat-history.md)).
- **Calls:** hide my IP address on calls; camera and microphone access
  ([calls.md](calls.md)).
- **Ignored people:** everyone you've ignored, with **Stop ignoring**.
- **Muted chats:** every muted room and private chat, with **Unmute**.
- **About:** version and open-source licenses.

The same history and call switches are still under the welcome screen's
Advanced options.

## Code

`lib/features/settings/presentation/settings_screen.dart` (route
`/settings`).

## Tests

`test/features/polish/polish_test.dart` (ignored people, muted chats);
`test/accessibility/a11y_test.dart` (settings meets the guidelines).
