# Chat screen

Available on iOS, Android and macOS (shared Flutter code). Phase 2 of the
[IRCage UI redesign](../design/ui-redesign.md); see
[design-system.md](design-system.md) for colours and components.

## What the user sees

### Header

- The room or person's avatar (in Comfortable), their name, and below it
  **"142 people · Libera.Chat"** in a room, the network in a private chat,
  or the connection on the server tab ("Connected as dennis"). While a
  network is reconnecting or disconnected, the line says so.
- Tap the name for **Chat info**, which now also holds the room's topic.
- Buttons: Voice and Video call in private chats, **Search this chat**
  (Find in Chat), and People in rooms. Everything that isn't about this
  chat moved to Rooms home, You and the sidebar
  ([navigation.md](navigation.md)); there's no ⋮ menu. On phones the top
  left is a back arrow; on wide screens it hides and shows the sidebar.

### Rooms (Comfortable)

- **Grouped messages.** Messages from one person within 5 minutes sit under
  one avatar, coloured name, gold **OP** tag for operators, and the time.
  Tap the avatar or name for that person's actions.
- **Mentions** get a coral bar on the left and a soft coral tint, and your
  nick is highlighted in the text. A mention always starts its own group.
- **Your own messages** get an accent bar on the left.
- **Joins and leaves collapse** into one centred line, such as
  "mara, kai and 3 others joined · sam left". Tap it to see each one. A
  single join or quit keeps its full text and reason. Kicks, nick changes,
  topic and mode changes stay on their own centred lines; errors are red.

### Private chats (Comfortable)

- **Bubbles**: theirs on the left on a grey bubble, yours on the right in
  the accent colour, at most 76% of the width. In a run of messages the
  corner nearest the sender is tucked in, and the time shows once under
  the run.
- Pictures still show under the message, with the same view-once rules
  ([picture-sharing.md](picture-sharing.md)).

### Everywhere

- **Day dividers**: "Today", "Yesterday", then the date ("Wed, Nov 18";
  older years in full).
- **"New messages" divider** (coral) above the first message that arrived
  while you were elsewhere. It stays while you're in the conversation and
  is gone the next time you open it.
- **"3 new" pill.** Scrolled up while messages arrive, a pill in the corner
  counts them; it turns coral (`@ 2 new`) when one mentions you. Tap it to
  jump to the latest. The jump doesn't animate with Reduce Motion on.
- **Compact** density and the server tab keep the classic
  `HH:MM <nick> text` lines, with the day and new-messages dividers.

### Composer

- A rounded field with **+** on the left and an accent **Send** button.
  The hint names the chat: "Message #flutter", "Message alice".
- **+** opens a menu: **Send a picture** (private chats) and common
  commands (`/me`, `/topic`, `/join`, `/msg`, `/nick`, `/whois`), which it
  writes into the field.
- **Completion chips** appear above the field while typing:
  - `@al` → people in the room; picking one writes `alice: ` at the start
    of a line (so they're notified) or `alice ` elsewhere.
  - `/to` at the start of a line → commands (`/topic`).
  - `#li` → rooms you're in on this network.
- **Format text** (the A button) adds bold, italics, underline,
  strikethrough and colours ([mirc-formatting.md](mirc-formatting.md)).
- Tab still completes names on a keyboard. On a computer Enter sends and
  Shift+Enter starts a new line.

### Replying

- Phones: **swipe a message right**, or **long-press** it for **Reply** and
  **Copy message**. Screen readers get a "Reply to bob" action on the
  message.
- Mac: a reply button appears at the end of the line on **hover** (or when
  it has keyboard focus).
- See [replies-and-mentions.md](replies-and-mentions.md).

### Motion

New messages fade in and slide up 8 pt (200 ms, ease-out). Messages that
were already there when you opened the chat don't animate, and nothing
moves with Reduce Motion on.

### Accessibility

- Each message reads as "alice, 10:42, message" (plus "mentions you"),
  then the text.
- Dividers are headings; collapsed events are buttons that say whether
  they're expanded.
- Buttons are at least 48 pt; colours meet 4.5:1 for text and 3:1 for bars
  in every theme and mode (tested).

### Not in this phase

- **Typing indicator** and **"Seen"**: these need the IRCv3 `typing` and
  read-marker extensions, which the app doesn't support yet.
- **Call history card** in private chats: with the call restyle in Phase 5.
- **Emoji button**: the phone keyboards and the Mac's emoji picker
  (Ctrl+Cmd+Space) cover it for now.

## Code

- `lib/features/chat/application/chat_layout.dart`: `layoutChat()` turns a
  conversation's lines into `DayItem`, `UnreadItem`, `GroupItem`,
  `PresenceItem`, `SystemItem` and `LineItem`; `presenceSummary()`,
  `nameList()`, `lineMentions()`, `messageGroupGap` (5 minutes).
- `lib/features/chat/application/chat_controller.dart`: `ChatLine.presence`
  and `subject` (set on joins, parts and quits), `ChatBuffer.firstUnread`
  and `unreadMarker` (set in `selectBuffer`).
- `lib/core/irc/completions.dart`: `completionsFor()`, `applyCompletion()`,
  `inputCommandNames`.
- `lib/core/ui/message_group.dart`: `MessageGroup`, `OpBadge`,
  `MessageBubble`.
- `lib/core/ui/chat_dividers.dart`: `DayDivider`, `UnreadDivider`,
  `SystemEventLine`, `JumpPill`.
- `lib/core/ui/composer.dart`: `Composer`, `composerCommands`.
- `lib/features/chat/presentation/chat_screen.dart`: `_MessageList` (picks
  lines, groups or bubbles; the jump pill), `_LineBody`, `_LineActions`
  (swipe, long-press, hover reply), `_MessageTile` (Compact lines), the
  header (`_subtitle`).

## Tests

- `test/features/chat/chat_layout_test.dart`: grouping, dividers,
  collapsed events.
- `test/core/irc/completions_test.dart`: chips and what they insert.
- `test/core/ui/chat_components_test.dart`: dividers, pill, group and
  bubble colours and shapes, composer buttons and menu, contrast in every
  theme.
- `test/features/chat/chat_redesign_test.dart`: the real chat screen:
  groups and OP tag, collapsed joins, the new-messages divider, bubbles,
  Compact, chips, the jump pill, Mac hover reply.
- `test/goldens/components_golden_test.dart`: light and dark goldens of
  the new components (macOS only).
