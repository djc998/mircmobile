# Private messages

Status: done (unreleased). Platforms: iOS, Android, macOS.

## Starting one
- **People list:** open a room's people list (people icon), tap a name and
  choose **Send private message**.
- **In the chat:** tap a nickname in a message (`<alice>`, `* alice`,
  `-alice-`) for the same menu.
- **Envelope button** in the chat top bar: **New private message** (on phones:
  ☰ → **Message**), type a nickname, **Open chat**.
- **Commands:** `/query nick` opens the chat, `/msg nick text` sends one
  message without switching.

Private chats appear in the conversation list with a person avatar (or
icon in Compact). When someone messages you first, their chat opens
automatically. In Comfortable, messages show as bubbles: theirs on the
left, yours on the right in the accent colour
([chat-screen.md](chat-screen.md)).

## The name menu
- **Send private message** (hidden for your own nick)
- **Who is this? (whois):** the server's answer (user@host, real name,
  channels, idle time, account) appears in the conversation you asked from.
- **Copy nickname**

## Code
- `ChatController.openPrivateChat()`, `ChatController.whoisUser()` and the
  WHOIS reply routing (numerics 301, 307, 311–320, 330, 338, 378, 379, 671).
- `showUserActions()`, `MessageGroup` (tappable avatar and name) and
  `_MessageTile` (tappable nicknames in Compact) in
  `lib/features/chat/presentation/chat_screen.dart`.

## Tests
`test/features/chat_flow_test.dart`: "start a private message from the
people list or button" and "whois replies appear in the open conversation".
