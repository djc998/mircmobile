# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
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
- Unit and widget tests (75 in total), GitHub Actions CI (format, analyze,
  test).
