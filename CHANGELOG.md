# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed
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
- Unit and widget tests (90 in total), GitHub Actions CI (format, analyze,
  test).
