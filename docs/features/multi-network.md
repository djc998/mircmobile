# Several networks at once

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

- **Stay on several networks.** Connecting to another network no longer
  closes the current one. Use **Add a network** (chat menu, or the bottom of
  the conversation list) to open the start screen, which then reads
  "Add a network" and has a back button to the chat. Networks that are
  already open show a **Connected** (or **Disconnected**) chip.
- **Connect to all.** The start screen has a **Connect to all** button that
  opens every listed network that isn't open yet.
- **Continue reopens everything.** The app remembers every network that was
  open, so the next launch shows **Continue on Libera.Chat and OFTC** (for
  example) and reconnects them all with their favorite rooms.
- **Conversation list grouped by network.** Each network has a header with
  a status dot (green connected, orange connecting, grey disconnected), its
  **Server messages** tab, its rooms and private chats. Favorite rooms that
  aren't open are listed under their network with **Join**, one tap away.
- **Room browser across networks.** Opening **Browse rooms** asks every
  connected network for its room list. Each room shows which network it is
  on, and chips (**All networks**, or one network) narrow the list. Search,
  size, sort, favorites and recent rooms work across all of them. Joining
  a room joins it on its own network.
- **Per-network menu.** The chat menu acts on the open conversation's
  network: **Disconnect from X**, **Reconnect to X**, and **Close X**
  (disconnects and removes its conversations).
- **Reconnecting keeps conversations.** Disconnecting and reconnecting a
  network (or trusting its certificate, or falling back to an unencrypted
  connection) keeps its open conversations and their messages.

## Account login with several networks

The account and password on the start screen apply to the network you tap.
With **Continue** or **Connect to all**, the app logs in on each network
where a password for that account was saved earlier, and connects without
login elsewhere. An empty password field never deletes a saved password;
turning off **Remember password** does.

## Code

- `lib/features/chat/application/chat_controller.dart`:
  - `NetworkSession`: one per network (id = lower-cased host). Holds the
    `IrcClient`, status, network name, nick, the room list (`rooms`,
    `roomsLoading`, `roomsFetchedAt`, `roomsError`) and connection problems
    (`untrustedCertificate`, `secureConnectFailed`).
  - `ChatBuffer.networkId`; buffers are keyed by `ChatState.bufferKey(id,
    name)`. `ChatState.activeNetwork` is the open conversation's network.
  - `ChatState.allRooms` returns `NetworkRoom`s from every network.
  - `ChatController.connect()` adds a network (or replaces the connection of
    one that is already open, keeping its buffers); `disconnect()`,
    `reconnect()`, `removeNetwork()`, `fetchRooms([id])`,
    `fetchMissingRooms()`, `joinRoom(name, networkId:)`.
- `lib/features/connection/data/saved_connection.dart`:
  `SavedConnection.networkHosts` / `openNetworks`,
  `SavedConnectionRepository.removeNetwork()`.
- Screens: `network_picker_screen.dart`, `chat_screen.dart` (`_BufferList`),
  `room_browser_screen.dart`.

## Tests

- `test/features/chat_flow_test.dart`: "stay on several networks; rooms and
  favorites span them all".
- `test/features/connection/saved_connection_test.dart`.
