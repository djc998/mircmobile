# Replies and mentions

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

- **Reply to a message.** In a room, on a phone, **swipe a message from
  someone else right**, or **long-press** it for **Reply** and **Copy
  message**; screen readers get a Reply action on the message. On a Mac a
  Reply button (↩) appears at the end of the line when you hover it.
  Tapping a name (in the chat or the people list) also offers **Reply to
  bob here**.
- **"Replying to bob" bar.** A bar above the message box shows who you are
  replying to and what they said, with ✕ to cancel. The box is focused and
  its hint reads "Reply to bob".
- **They get notified.** Sending puts the name in front the usual IRC way:
  `bob: sounds good`. Every IRC app alerts the person when a line starts
  with (or contains) their name. If you already typed their name first, or
  typed a /command, nothing is added. Private chats don't need this, so
  they have no Reply.
- **Tab completes names** (Mac or a hardware keyboard): type the first
  letters and press Tab. At the start of the line it becomes `alice: `.
  On any device, typing `@al` shows chips to pick from
  ([chat-screen.md](chat-screen.md)).
- **Mentions are easier to spot.** Messages that mention you have a coral
  bar and tint, with your nick highlighted. Matching is by whole word, so someone named "al"
  is no longer alerted by "also". Rooms home, the sidebar and the
  Mentions tab mark
  conversations with a mention in red.
- Each conversation keeps its own draft and reply, so switching rooms
  doesn't carry a reply over.

## Code

- `lib/core/irc/formatting.dart`: `mentions(text, nick)` (whole-word,
  nickname characters aware) and `completeNick(text, nicks)`.
- `lib/features/chat/application/chat_controller.dart`: `ChatBuffer.replyTo`,
  `startReply`, `cancelReply`, `ChatController.addressTo`; `submit` adds
  `nick: ` in rooms; mention detection uses `mentions()`.
- `lib/features/chat/presentation/chat_screen.dart`: `_LineActions` (swipe
  via `Dismissible`, long-press sheet and Reply semantics action on phones,
  hover reply button on computers), `_LineBody` (nick highlight),
  `showUserActions(onReply:)`.
- `lib/core/ui/composer.dart`: reply bar, Tab and chip completion.

## Tests

- `test/core/irc/formatting_test.dart`: `mentions`, `completeNick`.
- `test/features/chat_flow_test.dart`: "reply to someone so they are
  notified".
- `test/features/chat/chat_redesign_test.dart`: "computers: the reply
  button shows on hover".
