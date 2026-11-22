# Your own rooms: create, make private, keep

Available on iOS, Android and macOS (shared Flutter code). No commands are
needed. The commands still work for people who like them.

## What the user sees

### Create a room
**Create a room** is in the chat menu and on the room browser (the
**Create room** button). Type a name, then choose:

- **Private:** only people you invite can join (mode `+i`). On by default.
- **Hidden:** the room isn't shown in the room list (`+s`). On by default.
- **Password:** people need the password to join (`+k`).

With several networks open, pick the network too. The app joins the room.
When the server confirms you run it (you are its operator, `@`), the app
applies those settings and locks the topic to operators (`+t`). If the room
already exists and someone else runs it, the app says so and changes
nothing.

### Room settings
**Room settings** (chat menu, in a room) shows and changes:

- the room's **Description** (its topic), shown at the top of the room and
  in the room list. Operators can always change it; others only when the
  topic isn't locked;
- the **Private**, **Hidden** and **Lock the topic** switches;
- **Moderated** (`+m`): only operators and people with a voice can talk;
- **No messages from outside** (`+n`): people who aren't in the room can't
  send it messages;
- **Room size** (`+l`): the most people allowed in, or **No limit**;
- the room **Password** (set, change or remove);
- **Invite someone** by nickname;
- **Banned** (operators only): the room's ban list (loaded with
  `MODE #room +b` when the settings open, kept up to date as bans change),
  with **Unban** next to each one.

People who don't run the room see the settings but can't change them. Every
change shows in the room in words, for example "alice changed the room:
invite only on, password set". Passwords are never shown.

### People list
Tapping a name now also offers **Invite to #room** for your other rooms on
that network. In a room you run, it offers **Make operator** (or **Remove
operator** for someone who already is one), **Give voice** / **Take
voice** (`+v`, so they can talk in a moderated room), **Remove from #room**
(kick) and **Ban from #room** (ban by nickname, then remove).

### Invitations
When someone invites you, a banner shows "alice invited you to #club" with
**Join** and **Ignore**.

### Keep this room
An empty IRC room disappears, and the next person who joins it runs it.
**Keep this room** (in Room settings) registers the room with the network's
ChanServ, so it stays and you always get to run it. This needs a registered
nickname:

- **Register my nickname** asks for a password and an email and sends them
  to NickServ. Most networks email a code or link to confirm. The app keeps
  the password in the device keychain and uses it to log in automatically
  next time. **I already registered this nickname** logs in instead.
- ChanServ's and NickServ's answers open in their own chats.

Per network:

| Network | Keep rooms from the app |
| --- | --- |
| Libera.Chat, OFTC, Rizon | Yes (`REGISTER #room`) |
| DALnet | Yes; services are `ChanServ@services.dal.net`, and the app asks for a separate room registration password |
| Undernet | No: rooms are registered on the X website (cservice.undernet.org); the app explains this |
| EFnet | No: there are no services; the app explains that rooms last only while someone is in them |

## Commands

`/mode [#room] +modes [args]`, `/invite nick [#room]`, `/kick nick
[reason]`, `/ban nick`, `/op`, `/deop`, `/voice`, `/devoice`.

## Code

- `lib/core/irc/irc_client.dart`: `IrcChannel.modes`, `key`, `limit`
  (from `MODE` and `324`), `isOperator()`, `requestModes()` (sent after
  joining), `setModes()`, `invite()`, `kick()`, `ban()`. Events:
  `ChannelModeEvent`, `InviteEvent` (`irc_events.dart`).
- `lib/core/irc/services.dart`: `NetworkServices` builds NickServ/ChanServ
  messages; `IrcNetwork.services` / `servicesFor()` in `networks.dart`.
- `lib/features/rooms/domain/room_modes.dart`: `RoomSettings`,
  `modeChange()` (settings to one MODE line), `describeModeChange()`.
- `lib/features/rooms/presentation/room_dialogs.dart`: create dialog, room
  settings sheet, nickname registration dialog.
- `ChatController`: `createRoom`, `updateRoom`, `inviteUser`, `kickUser`,
  `banUser`, `makeOperator`, `acceptInvite`, `dismissInvite`,
  `registerNick`, `identifyNick`, `registerRoom`.

## Tests

- `test/core/irc/irc_client_test.dart`: mode tracking, operator ranks,
  invites, the new commands.
- `test/features/rooms/room_modes_test.dart`: mode changes, descriptions,
  services per network.
- `test/features/chat_flow_test.dart`: "create a private room, change its
  settings and keep it".
