# Change your nickname

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

- Tap your name next to a network in **You** (the tab on phones, the rail
  on tablets, your name at the bottom of the sidebar on iPad and Mac), or
  **Change nickname (yourname)** in a server tab's Chat info.
- The dialog has your current name selected. It checks the name (letters,
  numbers and `_-[]{}|^`, starting with a letter) before sending.
- With several networks open, **Change it on all my networks** changes it
  everywhere at once. Otherwise it changes on the network you're looking at.
- Networks that are disconnected use the new name when they reconnect.
- The new name is remembered for the next launch (start screen nickname).
- If the server refuses the name (taken, not allowed or temporarily
  unavailable: 432, 433, 436, 437), the chat says "Couldn't change your
  nickname: … You're still alice." and you keep your current name.
- `/nick newname` still works.

## Code

- `ChatController.changeNick(nick, {networkId, everywhere})` returns an
  error message or null; `IrcConnectionConfig.copyWith(nick:)`;
  `SavedConnectionRepository.rememberNick()`.
- `lib/features/chat/presentation/change_nick_dialog.dart`:
  `showChangeNickDialog()`.
- `chat_screen.dart`: menu item and the name chip on each network header.

## Tests

- `test/features/chat_flow_test.dart`: "change nickname from the menu".
