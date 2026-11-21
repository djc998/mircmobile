# Replies and mentions

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

- **Reply to a message.** In a room, every message from someone else has a
  Reply button (↩) at its end. On a Mac it brightens when you hover the
  line. On a phone, **swipe the message right**, or **long-press** it for
  **Reply** and **Copy message**. Tapping a name (in the chat or the people
  list) also offers **Reply to bob here**.
- **"Replying to bob" bar.** A bar above the message box shows who you are
  replying to and what they said, with ✕ to cancel. The box is focused and
  its hint reads "Reply to bob".
- **They get notified.** Sending puts the name in front the usual IRC way:
  `bob: sounds good`. Every IRC app alerts the person when a line starts
  with (or contains) their name. If you already typed their name first, or
  typed a /command, nothing is added. Private chats don't need this, so
  they have no Reply button.
- **Tab completes names** (Mac or a hardware keyboard): type the first
  letters and press Tab. At the start of the line it becomes `alice: `.
- **Mentions are easier to spot.** Lines that mention you are highlighted
  with a coloured band. Matching is by whole word, so someone named "al"
  is no longer alerted by "also". The conversation list still marks
  conversations with a mention in red.
- Each conversation keeps its own draft and reply, so switching rooms
  doesn't carry a reply over.

## Code

- `lib/core/irc/formatting.dart`: `mentions(text, nick)` (whole-word,
  nickname characters aware) and `completeNick(text, nicks)`.
- `lib/features/chat/application/chat_controller.dart`: `ChatBuffer.replyTo`,
  `startReply`, `cancelReply`, `ChatController.addressTo`; `submit` adds
  `nick: ` in rooms; mention detection uses `mentions()`.
- `lib/features/chat/presentation/chat_screen.dart`: `_MessageTile` (reply
  button, hover, swipe via `Dismissible`, long-press sheet on phones,
  selectable text on computers, mention highlight), `_InputBar` (reply bar,
  Tab completion), `showUserActions(onReply:)`.

## Tests

- `test/core/irc/formatting_test.dart`: `mentions`, `completeNick`.
- `test/features/chat_flow_test.dart`: "reply to someone so they are
  notified".
