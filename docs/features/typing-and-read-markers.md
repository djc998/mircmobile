# Typing indicators and read markers

Available on iOS, Android and macOS (shared Flutter code), on servers that
support the IRCv3 extensions. Elsewhere nothing shows and nothing is sent.

## Typing

- **Who's typing** shows above the message box: "bob is typing…",
  "bob and ann are typing…", or "Several people are typing…". It's a live
  region, so screen readers announce it.
- It goes away when they send their message, say they stopped, or after
  6 seconds without an update (30 after "paused"), like other clients.
- **Your typing** is sent while you write in a room or private chat: at
  most once every 3 seconds, and "done" when you clear the box. Commands
  (`/…`) aren't typing. Sending a message ends it.
- **Turn it off** in Settings → Safety → **Show when I'm typing**. You
  still see other people's typing.
- Ignored people's typing isn't shown.

Protocol: the `+typing` client tag (`active`, `paused`, `done`) on a
`TAGMSG`, which needs the `message-tags` capability.

## Read position (read markers)

On servers with `draft/read-marker` (soju, Ergo), the server remembers
where you've read up to in each conversation, for all your devices:

- Opening a conversation, or reading new messages in it, tells the server
  (`MARKREAD <target> timestamp=…`), shortly after and only when it moved
  forward. Nothing is sent while the app is in the background.
- When the server says a conversation was read on another device, its
  unread count, "New messages" start and mention badge here follow: only
  what came after still counts.
- Missed messages from history that were already read elsewhere don't
  count as unread.

Read markers are only for your own devices: IRC has no read receipts, so
nobody else sees what you've read.

## Code

- `lib/core/irc/irc_client.dart`: `supportsTyping`, `sendTyping`,
  `supportsReadMarkers`, `markRead`, TAGMSG and MARKREAD handling, and
  `_timestamp` (milliseconds, as IRCv3 requires).
- `lib/core/irc/irc_events.dart`: `TypingEvent`, `ReadMarkerEvent`.
- `lib/features/chat/application/chat_controller.dart`: `noteTyping`,
  `ChatBuffer.typing` / `typingNicks`, `_syncRead`, `_onReadMarker`.
- `lib/features/chat/presentation/chat_screen.dart`: `TypingLine`.
- `lib/core/ui/composer.dart`: `onChanged`.
- `lib/features/safety/application/safety_controller.dart`: `sendTyping`.

## Tests

`test/core/irc/typing_read_test.dart` (TAGMSG and MARKREAD, millisecond
timestamps) and `test/features/chat/typing_read_flow_test.dart` (the typing
line, the 3-second limit and "done", the Settings switch, read on another
device). Checked live: typing between two connections on Ergo's test
server, and a read marker from one soju connection reaching another.
