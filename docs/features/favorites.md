# Favorites, recent rooms and saved settings

Status: done (unreleased). Platforms: iOS, Android, macOS.

## Favorites
- Star a room with the ☆ button in the chat screen's top bar, or the star
  next to any room in the room browser. Tap again to unstar.
- Favorites are kept per network (by server host), so `#help` on Libera.Chat
  and `#help` on OFTC are separate.
- With **Rejoin my favorite rooms** on (the default), connecting joins every
  favorite on that network, plus any rooms typed into "Rooms to join".
- The room browser's **Favorites** chip shows only starred rooms.
- Favorite rooms show a ★ in the conversation list.

## Recent rooms
- Every room you join is added to that network's recent list (newest first,
  no duplicates, last 10 kept).
- The room browser shows them as **Recent:** chips above the list when the
  search box is empty; tap one to join.

## Saved settings
- The nickname, last network, account name and the two switches are saved
  when you connect.
- Next launch, a **Continue on <network>** card at the top of the start
  screen reconnects in one tap and says which favorites it will rejoin.
- Account passwords are saved only if **Remember password** is on, and only
  in secure storage: the Keychain on iPhone/iPad/Mac and encrypted storage on
  Android. Turning the switch off deletes the saved password on the next
  connect.

## Code
- `lib/core/storage/app_storage.dart`: `KeyValueStore`, `SecretStore`,
  real and in-memory implementations, providers overridden in `main.dart`.
- `lib/features/connection/data/saved_connection.dart`: `SavedConnection`
  and its repository.
- `lib/features/favorites/application/room_prefs_controller.dart`:
  `RoomPrefs` and `RoomPrefsController` (JSON in key-value storage).
- `ChatController` records recents on every self-JOIN.

## Tests
- `test/features/favorites/room_prefs_test.dart`
- `test/features/chat_flow_test.dart`: "favorites and recents are
  remembered for the next launch".
