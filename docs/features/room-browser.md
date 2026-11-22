# Room browser

Status: done (unreleased). Platforms: iOS, Android, macOS.

The room browser is the app's main way to find somewhere to chat. It lists
every public room on the connected network.

## Using it
- **Discover**: a tab on phones, on the rail on tablets, and **Discover
  rooms** in the sidebar on iPad and Mac (⇧⌘B). **Browse rooms** (the
  compass) at the top of Rooms home and **Browse** in You open it too.
  Joining a room from it goes back to Rooms and opens the room.
- The first time, the app asks the server for its room list (`LIST`). Big
  networks send tens of thousands of rooms, so this can take a few seconds;
  a progress bar shows while it loads.
- **Search** matches room names and topics. Every word must match, case
  doesn't matter, and a leading `#` is ignored. Rooms whose name matches are
  shown before rooms that only mention the word in their topic.
- **Size chips** hide small rooms: Any size, 10+, 50+ or 200+ people.
- **Sort chips**: Most people (default) or A–Z.
- Tap a room or its **Join** button to join it and go back to the chat. If
  you're already in that room, it just opens it.
- Tap **Refresh** or pull down to fetch the list again. Otherwise the list is
  kept until you disconnect, so reopening the browser is instant.
- Typing `/list` in the status window also fills the browser.

## Edge cases
- Opened before login finishes: shows "Connect to a network…" and fetches
  automatically once connected.
- Server refuses or limits LIST (numerics 263 or 416): the browser shows the
  server's reason and asks to try again later.
- mIRC colour codes and `[+nt]` mode prefixes are removed from topics.

## Code
- `lib/features/discovery/domain/room_filter.dart`: `filterRooms()`, pure
  and unit tested.
- `lib/features/discovery/presentation/room_browser_screen.dart`: the screen,
  route `/chat/rooms`.
- `ChatController.fetchRooms()` / `fetchMissingRooms()` / `joinRoom()`,
  `NetworkSession.rooms` and `ChatState.allRooms` (rooms from every
  connected network; see [multi-network.md](multi-network.md)).

## Tests
- `test/features/discovery/room_filter_test.dart`
- `test/features/chat_flow_test.dart`: "browse rooms, search and join with
  one tap".
