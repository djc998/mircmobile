# Discover (room browser)

Status: done (unreleased). Platforms: iOS, Android, macOS. Restyled in
Phase 4 of the [IRCage UI redesign](../design/ui-redesign.md).

Discover is the app's main way to find somewhere to chat. It lists every
public room on the connected networks as cards.

## Using it

- **Open it:** the Discover tab on phones, the rail on tablets, **Discover
  rooms** in the sidebar on iPad and Mac (⇧⌘B), **Browse rooms** (the
  compass) at the top of Rooms home, **Browse** in You, or **Discover
  rooms** on Rooms home before you've joined anything.
- The first time, the app asks the server for its room list (`LIST`). Big
  networks send tens of thousands of rooms, so this can take a few seconds;
  grey placeholder cards and a progress bar show while it loads.
- **Network chips** (with more than one network): All networks, or one.
- **Search** ("Search 4,812 rooms") matches room names and topics. Every
  word must match, case doesn't matter, and a leading `#` is ignored. Rooms
  whose name matches come before rooms that only mention the word in their
  topic.
- **Category chips:** **Popular** (every room, most people first), **Tech**,
  **Gaming**, **Music**, **Help** and **Social**. IRC has no categories, so
  each room's is guessed from keywords in its name (which count most) and
  topic; rooms that match nothing are only in Popular.
- **Filters** (the sliders button, with a count of active filters):
  **Favorites only**, room size (Any, 10+, 50+, 200+ people) and sort
  (Most people or A–Z).
- **Recent:** chips for rooms you joined recently, one tap to rejoin.
- **Room cards:** avatar, name, network chip (several networks), people
  count, category, **Busy now** (100 or more people in it right now), the
  topic on two lines with mIRC colour codes and `[+nt]` prefixes removed, a
  ☆ to favorite it, and **Join**. Rooms you're in say **Open** instead and
  just open the chat.
- **Tap a card** for a preview sheet: the full topic, people, category,
  **Join room** (or **Open room**) and **Add to favorites**. The buttons
  stay at the bottom of the sheet and stack when the text is large.
- Joining goes back to Rooms and opens the room when the server confirms.
- **Tablets and the Mac:** two columns of cards.
- **Refresh** or pull down to fetch the list again. Otherwise it's kept
  until you disconnect, so reopening Discover is instant. Typing `/list` in
  the server tab also fills it.
- **Create room** (the button at the bottom) makes a new room
  ([private-rooms.md](private-rooms.md)).

## Edge cases

- Opened before login finishes: "Not connected", and it fetches
  automatically once connected.
- Server refuses or limits LIST (numerics 263 or 416): the server's reason
  and a **Try again** button.
- A room restored from saved history but not joined yet shows **Join**, not
  Open.
- Categories are worked out once per room, so typing in search stays fast
  with tens of thousands of rooms.

## Code

- `lib/features/discovery/domain/room_filter.dart`: `filterRooms()`.
- `lib/features/discovery/domain/room_category.dart`: `RoomCategory`,
  `categorizeRoom()`, `categoryOf()` (cached), `DiscoverFilter`,
  `isBusyRoom()` / `busyRoomMinPeople`.
- `lib/features/discovery/presentation/room_browser_screen.dart`: the
  screen (a tab in `ChatShell`, or route `/chat/rooms`), the Filters sheet.
- `lib/features/discovery/presentation/room_preview.dart`:
  `showRoomPreview()`.
- `lib/core/ui/room_card.dart`: `RoomCard`, `groupedCount()`;
  `lib/core/ui/empty_state.dart`: `EmptyState`, `SkeletonList`.
- `ChatController.fetchRooms()` / `fetchMissingRooms()` / `joinRoom()`,
  `NetworkSession.rooms` and `ChatState.allRooms` (rooms from every
  connected network; see [multi-network.md](multi-network.md)).

## Tests

- `test/features/discovery/room_filter_test.dart`
- `test/features/discovery/room_category_test.dart`: categories (including
  the mockup's rooms), Busy now, filters.
- `test/features/discovery/discover_test.dart`: categories, Filters,
  preview sheet, Join becoming Open, two columns on wide screens.
- `test/core/ui/room_card_test.dart`: Join and Open, readable "Busy now" in
  every theme, large text, `EmptyState`, `SkeletonList`.
- `test/features/chat_flow_test.dart`: "browse rooms, search and join with
  one tap".
- `test/goldens/components_golden_test.dart`: `room_card` and
  `empty_state` goldens (macOS only).
