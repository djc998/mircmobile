# Welcome (onboarding)

Available on iOS, Android and macOS (shared Flutter code). Phase 4 of the
[IRCade UI redesign](../design/ui-redesign.md).

## What the user sees

The first screen welcomes you and walks through three numbered steps:

- **Welcome to IRCade** with the app's mark and the line "Chat rooms, the
  way they used to be. Only better."
- **1 Pick a nickname.** The help under the field says what's allowed
  (letters, numbers and `_-[]{}|^`, starting with a letter).
- **2 Choose a network.** A card per network with its description; tap one
  to connect, or **Connect to all**. Networks that are already open show
  **Connected** or **Disconnected**.
- **3 Find your first room.** Explains Discover. After connecting with no
  rooms to join, Rooms home says **Find your first room** with a
  **Discover rooms** button.

Everything else is behind **Advanced options**: rooms to join, rejoin
favorites, account login (account name, password, remember password),
username, real name, saving chat history, camera and microphone access,
hiding your IP on calls, and deleting saved history. It opens by itself
when you log in with an account.

Returning users get **Continue on Libera.Chat as dennis** at the top, which
reconnects every network that was open with its favorite rooms
([multi-network.md](multi-network.md)).

**Add a network** (from You) opens the same screen without the welcome and
step 3, titled "Add a network", with a back button to the chat.

On wide screens the form stays 560 points wide in the middle.

## Accessibility

- Each step's number is read as "Step 1" and its title is a heading.
- The whole page is built at once, so screen readers reach Advanced options
  and every network without scrolling first.

## Code

- `lib/features/connection/presentation/network_picker_screen.dart`:
  `NetworkPickerScreen` (route `/`), `_Hero`, `_Step`, `_NetworkCard`,
  `_advanced()`.
- `lib/features/chat/presentation/chat_shell.dart`: the "Find your first
  room" empty state in `RoomsHome`.

## Tests

- `test/features/discovery/discover_test.dart`: "welcome: three steps,
  advanced options folded away" and "step 3: Rooms home sends you to
  Discover".
- `test/features/chat_flow_test.dart`: connecting, rooms to join, account
  login, rejoin favorites (through Advanced options).
