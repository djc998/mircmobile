# Missed and older messages (IRCv3 chathistory)

Available on iOS, Android and macOS (shared Flutter code), on servers and
bouncers that keep history and offer the `draft/chathistory` (or
`chathistory`) capability: Ergo, soju, and others. Elsewhere nothing
changes: no requests, no button.

## What the user sees

- **Joining a room** (including rejoining after a reconnect) brings back
  what was said since the newest message the app already has, or the last
  50 messages when it has none. They appear in time order above "You
  joined", and anything already shown isn't repeated.
- **Private chats you missed:** after logging in, the app asks which people
  wrote to you since it last saw the network (up to a day back the first
  time). Each one opens with its messages, counted as unread. Private chats
  that were already open get what they missed too.
- **Older messages:** scrolling to the top of a chat fetches 50 older
  messages; a **Load earlier messages** button at the top does the same
  (for screen readers, and when the chat is too short to scroll). A
  spinner shows while they load. When the server has nothing older, the
  button goes away.
- Messages missed while away are saved to the device's chat history like
  any other; older messages fetched from the top are shown but not saved.

## How it works

- `IrcClient` asks for `draft/chathistory` and `chathistory` alongside
  `batch`, `server-time` and `message-tags`, and reads the server's
  `CHATHISTORY=` limit (100 at most per request).
- Requests: `CHATHISTORY LATEST <target> <timestamp=…|*> <n>`,
  `CHATHISTORY BEFORE <target> timestamp=… <n>` and
  `CHATHISTORY TARGETS timestamp=… timestamp=… <n>`.
- Replies come in `chathistory` batches. Messages in them become
  `MessageEvent`s with `history` set; the batch end is a
  `HistoryBatchEvent`; `chathistory-targets` batches become a
  `HistoryTargetsEvent`. `FAIL CHATHISTORY` ends any request.
- CTCP requests in history are never answered again. Ergo's `HistServ`
  lines ("bob joined the channel", sent to clients without
  event-playback) are left out.
- `ChatController` puts history lines in time order and skips repeats by
  `msgid` (now kept on lines and in saved history), or by sender, text and
  a few seconds when there's no id. It keeps a "seen until" time per
  network (`historySeen`, written at most once a minute) for the TARGETS
  request.

## Code

- `lib/core/irc/irc_client.dart`: `supportsHistory`, `historyLimit`,
  `requestHistory`, `requestHistoryBefore`, `requestHistoryTargets`,
  batch tracking (`_Batch`).
- `lib/core/irc/irc_events.dart`: `MessageEvent.history` and `.msgid`,
  `HistoryBatchEvent`, `HistoryTargetsEvent`.
- `lib/features/chat/application/chat_controller.dart`: `_catchUp`,
  `_fetchMissed`, `loadOlder`, `canLoadOlder`, `_addHistoryLine`,
  `ChatLine.sameMessage`, `ChatBuffer.historyWant` / `historyExhausted`.
- `lib/features/chat/presentation/chat_screen.dart`: the top row and
  loading on scroll in `_MessageList`.

## Tests

`test/core/irc/chathistory_test.dart` (capability, request format and
limits, batches, TARGETS, FAIL, HistServ, no CTCP replies) and
`test/features/chat/chathistory_flow_test.dart` (join, repeats, missed
private chats, older messages until exhausted, servers without history).
Checked live against Ergo's test server (`testnet.ergo.chat`).
