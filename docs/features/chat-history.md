# Saved chat history

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

- **Conversations keep their messages.** Rooms and private chats are saved
  on the device. After a disconnect, a reconnect, or quitting and reopening
  the app, the saved messages appear again, with a **Saved messages above**
  marker where new messages start.
- **Open conversations come back.** The app remembers which rooms and
  private chats were open on each network. **Continue** rejoins those rooms
  (after your favorites) and reopens those private chats. Closing a network
  (**Close X** in the chat menu) forgets its open conversations, but keeps
  their saved messages.
- **What is saved:** messages, actions (`/me`), notices and your own
  messages, up to the last 1,000 per conversation shown and about 2,000 kept
  on disk. Joins, quits, errors and the server tab are not saved.
- **Settings** (start screen, **More options**):
  - **Save chat history on this device** (on by default). Turning it off
    stops saving and loading history; what is already saved stays until
    deleted.
  - **Delete saved history** deletes every saved conversation after a
    confirmation.
- **Clear history** in the chat menu deletes the open conversation's saved
  messages and clears it on screen.

## Where it is stored

Files live in the app's private support folder
(`getApplicationSupportDirectory()/history/<network>/<conversation>.jsonl`),
one JSON object per line. Other apps can't read it, and it isn't shown in
Files or Finder. Nothing is sent to a server.

## Code

- `lib/features/chat/data/chat_history_store.dart`: `ChatHistoryStore`
  (load, append, clear, clearAll), `FileChatHistoryStore` (queued appends
  per file, trimming, skips damaged lines), `MemoryChatHistoryStore` (tests
  and default), `chatHistoryStoreProvider` (overridden in `main.dart`).
- `lib/features/chat/application/chat_controller.dart`: `ChatLine.isSaved`,
  `toStored()` / `fromStored()`; new conversations load history in
  `_restoreHistory` (lines that arrive meanwhile wait in `pendingSave` so
  nothing is saved twice); open conversations are kept under the
  `openConversations` setting; `saveHistory`, `setSaveHistory`,
  `clearHistory`, `clearAllHistory`.
- `IrcConnectionConfig.copyWith(autoJoin:)` adds rooms to rejoin.

## Tests

- `test/features/chat/chat_history_store_test.dart`: file store round trip,
  trimming, damaged lines, clearing.
- `test/features/chat_flow_test.dart`: "chat history survives disconnects
  and app restarts".
