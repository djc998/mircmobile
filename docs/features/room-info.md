# Room info, people and profile cards

Available on iOS, Android and macOS (shared Flutter code). Phase 5 of the
[IRCage UI redesign](../design/ui-redesign.md).

## Room info

Tap a room's name in its header. Phones get a full page; tablets and the
Mac get a panel that slides in from the right. One page holds everything
that used to be in stacked sheets:

- The room's avatar, name, "9 people · Libera.Chat" and its topic.
- **Add to / Remove from favorites.**
- **Mute**: the room's unread count turns grey and no longer adds to the
  Mentions badge; messages that mention you are still coral.
- **People (n)** on phones and tablets (it's pinned on wide screens).
- **Room settings** inline: description, Private, Hidden, Lock the topic,
  Moderated, No messages from outside, room size, password, invite someone,
  the ban list and **Keep this room** (operators change them; others see
  them).
- **Clear history** and **Leave room**.

Private chats and the server tab still open the short Chat info sheet.

## Mute anywhere

Long-press a chat in Rooms home, or right-click it in the sidebar, for
**Mute** / **Unmute**, **Add to favorites** and **Leave** (screen readers
get the same as actions). Muted chats show a bell-off icon and a grey
badge, and are listed in Settings → Muted chats to unmute.

## People

The member list (pinned on wide screens, sliding over on phones) is grouped
into **Operators**, **Voiced**, **Members** and **Away**, each with a count.
Away people are dimmed and their avatar is faded.

Away status comes from the IRCv3 `away-notify` extension: after joining a
room of up to 200 people the app sends one `WHO` to learn who's away
already, and later `AWAY` messages move people in and out of Away. On
servers without `away-notify` there's no Away group.

## Profile cards

Tap a name (in a message, the people list or a mention) for a profile card:

- Their avatar with their role ring, nick, and what's known: "Operator of
  #flutter", "Has a voice in #flutter", "Away", the network.
- Quick buttons: **Message** (private chat), **Call** (opens the private
  chat and starts a voice call), **Mention** (in rooms: starts your message
  with `devon: ` so they're notified).
- Then: Reply to them here, Send private message, Who is this? (whois), Copy
  nickname, **Ignore** (hides their messages, pictures and invitations on
  every network; Settings lists who you ignore), **Report**, Invite to a
  room, and for the room's operators: make or remove operator, give or take
  voice, remove from the room, ban.
- **Report**: IRC has no app-wide report button, so the dialog explains who
  can act and lists the room's operators with **Message** buttons, plus an
  **Ignore** button.

## Code

- `lib/features/rooms/presentation/room_info.dart`: `showRoomInfo`,
  `RoomInfoScreen`.
- `lib/features/rooms/presentation/room_dialogs.dart`:
  `RoomSettingsSheet(embedded:)`.
- `lib/features/favorites/application/room_prefs_controller.dart`:
  `RoomPrefs.muted`, `isMuted`, `toggleMute`.
- `lib/features/chat/presentation/chat_shell.dart`:
  `showConversationMenu`.
- `lib/features/chat/presentation/chat_screen.dart`: `showUserActions`
  (profile card), `_ProfileHeader`, `_QuickAction`, `_showReport`,
  `_NickList` (groups).
- `lib/core/irc/irc_client.dart`: `IrcMember.away`, `AWAY`, `352` and the
  `WHO` after joining (`whoAwayMaxMembers`).
- `ChatController.blockUser` / `unblockUser` / `blockedNicks` (Ignore).

## Tests

- `test/features/polish/polish_test.dart`: People groups and away, profile
  card (role, Mention, Report, Ignore), Mute (badge, Mentions, Settings),
  Room info.
- `test/features/chat/pinned_panels_test.dart`: Room info on a phone and a
  wide screen.
