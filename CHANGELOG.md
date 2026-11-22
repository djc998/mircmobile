# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Photos are sent as `📷 Photo from <your nick>: <link>`. The message no
  longer says how long it lasts; opening an expired or already-viewed photo
  says **This photo has expired.**
- Share temporary pictures in private chats (iOS, Android, macOS). Tap the
  picture button next to the message box, choose or take a photo, pick how
  long it lasts (1 hour or 4 hours). Every picture is view-once: it is
  deleted from the server as soon as it has been opened, and nothing is
  kept longer than 4 hours. The photo is shrunk to 2048 px, its location and other metadata
  are removed, and it is encrypted on the device before upload, so the
  server only stores scrambled bytes. The other person sees it in the chat;
  people on other IRC apps get a link that opens in a browser. Pictures
  from people you haven't written to stay hidden until tapped. Each
  picture has **Report picture** and **Block**; reports land on your own
  server for review as text only (no copy of the picture is kept). **Block / Unblock** is also in the people menu.
  The picture server is a small Cloudflare Worker with R2 storage in
  `server/picture-host`. See
  [docs/features/picture-sharing.md](docs/features/picture-sharing.md).
- Change your nickname without commands (iOS, Android, macOS): **Change
  nickname** in the chat menu, or tap your name on a network in the
  conversation list. Optionally change it on all networks; the new name is
  remembered. A taken name shows a clear message and keeps your current one.
  See [docs/features/change-nickname.md](docs/features/change-nickname.md).
- Appearance settings (iOS, Android, macOS): System/Light/Dark mode, four
  themes (Classic, Midnight, Solarized, High contrast) with live previews,
  and text size. Open from the palette button on the start screen or the
  chat menu. See [docs/features/appearance.md](docs/features/appearance.md).
- Reply to someone in a room (iOS, Android, macOS): a Reply button on each
  message (brighter on hover on Mac), swipe right or long-press on phones,
  and **Reply to … here** in the name menu. A "Replying to bob" bar shows
  above the message box, and sending addresses them as `bob: …` so they are
  notified. Tab completes nicknames. Lines that mention you are
  highlighted. See [docs/features/replies-and-mentions.md](docs/features/replies-and-mentions.md).
- Your own rooms without commands (iOS, Android, macOS). **Create a room**
  (chat menu, or the room browser) with Private, Hidden and Password
  switches. **Room settings** changes them, sets or removes the password and
  invites people. The people list adds **Invite to**, and for rooms you run
  **Make operator**, **Remove** and **Ban**. Invitations show a Join/Ignore
  banner. **Keep this room** registers the room with ChanServ (Libera.Chat,
  OFTC, Rizon, DALnet), with a guided nickname registration; Undernet and
  EFnet explain why they can't. Room setting changes show in words. New
  commands: `/mode`, `/invite`, `/kick`, `/ban`, `/op`, `/deop`, `/voice`,
  `/devoice`. See [docs/features/private-rooms.md](docs/features/private-rooms.md).
- Saved chat history (iOS, Android, macOS). Rooms and private chats keep
  their messages after a disconnect or an app restart, marked **Saved
  messages above**. **Continue** rejoins the rooms and reopens the private
  chats that were open. **Save chat history on this device** and **Delete
  saved history** are under **More options** on the start screen, and
  **Clear history** in the chat menu clears one conversation.
  See [docs/features/chat-history.md](docs/features/chat-history.md).
- Several networks at once (iOS, Android, macOS). Adding a network keeps the
  others connected. The conversation list is grouped by network and lists
  each network's favorite rooms for one-tap join. The room browser fetches
  and searches rooms from every connected network, labels each room with
  its network and can filter by network. **Continue** reopens every network
  that was open, and **Connect to all** opens every listed network.
  Disconnect, reconnect and close work per network, and reconnecting keeps
  that network's conversations.
  See [docs/features/multi-network.md](docs/features/multi-network.md).
- Private messages are easy to start (iOS, Android, macOS): tap a name in
  the people list, or a nickname in the chat, for **Send private message**,
  **Who is this? (whois)** and **Copy nickname**. A **New private message**
  button (envelope) in the chat top bar opens a chat with any nickname.
  Whois replies now show in the conversation you asked from instead of the
  server tab. See [docs/features/private-messages.md](docs/features/private-messages.md).

### Fixed
- Dropped connections (iOS, Android, macOS). When the network blips (for
  example after sleep or a Wi-Fi change), the app now notices straight away
  and reconnects, instead of logging "Broken pipe" / "Connection reset by
  peer" errors and waiting up to a minute for the ping timeout. Closing a
  dead connection no longer hangs. See
  [docs/features/irc-core.md](docs/features/irc-core.md).
- The chat menu was missing its **Appearance** item (it was only on the
  start screen).
- Join/part (green), notice (dark red) and action (purple) lines were hard
  to read on dark backgrounds. Chat colours now come from the theme, with
  light and dark versions that all meet a 4.5:1 contrast ratio (tested).
- Mentions now match whole words, so a short nickname like "al" is no
  longer alerted by words such as "also".
- Logging in again without retyping the password no longer deletes the
  saved password.
- The Join and New private message dialogs no longer use their text field
  after it was disposed while the dialog closes.
- EFnet (and other servers with self-signed, mismatched or expired TLS
  certificates) failed with `CERTIFICATE_VERIFY_FAILED`. The app now shows
  the certificate details and lets you **Trust and connect**. It remembers
  that exact certificate (SHA-256 fingerprint) per server, so a different
  certificate later is still refused. Verification is never turned off.
- DALnet disconnected new users as a "compromised host" (`[exp/dm]`). The
  app sent the nickname as the username and real name too, which DALnet's
  drone detector flags. It now sends `mobile` / `Mobile IRC user` by
  default, and both can be set under **More options** on the start screen.

### Added
- When a secure connection can't be opened at all (for example a server
  without TLS), the chat screen offers **Connect without encryption**
  (port 6667) with a clear warning.
- Favorites and recent rooms (iOS, Android, macOS). Star a room from the chat
  screen or the room browser; favorites are kept per network and rejoined
  automatically on connect ("Rejoin my favorite rooms"). The last 10 rooms
  you joined on each network appear as quick-join chips in the room browser,
  and a **Favorites** filter shows only starred rooms. Favorite rooms show a
  star in the conversation list.
  See [docs/features/favorites.md](docs/features/favorites.md).
- Saved connection settings: the nickname, last network and account name are
  remembered, and a **Continue on <network>** card reconnects in one tap.
  Account passwords are stored only in the iOS/macOS Keychain or Android
  encrypted storage (flutter_secure_storage), with a "Remember password"
  switch.
- Storage layer (`lib/core/storage/app_storage.dart`) wrapping
  shared_preferences and flutter_secure_storage behind interfaces, with
  in-memory versions for tests.
- Room browser (iOS, Android, macOS): tap the compass in the chat screen to
  see every room on the network. Search by name or topic, filter by size
  (any, 10+, 50+, 200+ people), sort by most people or A–Z, and join with
  one tap. The list is fetched once per connection and can be refreshed.
  See [docs/features/room-browser.md](docs/features/room-browser.md).
- A welcome line after connecting that points new users to the browser.
- `ServerInfoEvent`, so the app shows the network's real name (from
  ISUPPORT `NETWORK=`) instead of the server's host name.
- Flutter project for iOS, Android and macOS (`com.djc998.irc_client`),
  working display name "mIRC Mobile".
- IRC core in pure Dart (`lib/core/irc/`), identical on every platform:
  - Line parser and serializer for RFC 1459/2812 with IRCv3 message tags,
    tag escaping and `server-time`.
  - Byte-to-line decoder with UTF-8 and a Latin-1 fallback.
  - TLS socket transport (port 6697 by default) behind an `IrcTransport`
    interface, so a bouncer transport can be added later.
  - CAP LS 302 negotiation (multi-line LS, REQ/ACK/NAK, NEW/DEL) and SASL
    PLAIN with 400-byte chunking.
  - Registration with automatic nick-collision handling, PING/PONG,
    idle keepalive and ping timeout, reconnect with exponential backoff,
    and rejoining channels after a reconnect.
  - Channel and member tracking: JOIN, PART, KICK, QUIT, NICK, MODE
    (prefix modes), NAMES with `multi-prefix` and `userhost-in-names`,
    topics, and RPL_ISUPPORT (PREFIX, CHANTYPES, NETWORK, CASEMAPPING, ELIST).
  - Messages and notices, CTCP ACTION, VERSION/PING/TIME replies,
    STATUSMSG, `echo-message` support, and splitting long messages so every
    line fits in 512 bytes without breaking a character.
  - LIST with the ELIST `>n` user filter, or a local filter when the server
    lacks it.
  - Outgoing flood control (token bucket).
  - Slash commands: /join, /part, /msg, /query, /me, /notice, /nick, /topic,
    /whois, /list, /quote, /quit, and `//` to send a literal slash.
- Built-in network list: Libera.Chat, OFTC, EFnet, Undernet, DALnet, Rizon.
- First screens: network picker (nickname, rooms to join, optional account
  login) and a chat screen with a conversation list, coloured nicks, a
  nick list and a message box. Wide layouts (iPad, Mac) show the
  conversation list beside the chat.
- Android INTERNET permission and the macOS network-client entitlement.
- Unit and widget tests (92 in total), GitHub Actions CI (format, analyze,
  test).
