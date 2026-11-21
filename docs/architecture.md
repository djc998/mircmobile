# Architecture

The app is one Flutter codebase for iOS, Android and macOS. Every feature
ships on all three platforms; nothing in `lib/` is platform specific.

## Layers

```
lib/
  app/                       App widget and go_router routes
  core/irc/                  Pure Dart IRC engine (no Flutter imports)
    irc_message.dart         Parse/serialize one protocol line
    irc_transport.dart       Socket transport + byte-to-line decoder
    cap_negotiator.dart      CAP LS 302 and SASL PLAIN state machine
    isupport.dart            RPL_ISUPPORT (005) features
    flood_control.dart       Outgoing rate limit
    irc_client.dart          Connection state machine and channel tracking
    irc_events.dart          Typed events the UI listens to
    input_commands.dart      /commands typed by the user
    formatting.dart          mIRC colour code stripping, nick validation
    networks.dart            Built-in network list
  core/storage/              KeyValueStore / SecretStore interfaces
  core/theme/                Material 3 theme, nick colours
  features/connection/       Network picker screen
  features/chat/             ChatController (Riverpod) and chat screen
  features/connection/data/  SavedConnection (nick, network, account)
  features/discovery/        Room browser: filterRooms() and its screen
  features/favorites/        Favorite and recent rooms per network
```

## Data flow

1. The network picker builds an `IrcConnectionConfig` and calls
   `ChatController.connect`.
2. `IrcClient` opens an `IrcTransport` (TLS socket by default), sends
   `CAP LS 302`, `NICK` and `USER`, and lets `CapNegotiator` finish CAP and
   SASL before `CAP END`.
3. Each incoming line is parsed into an `IrcMessage`, applied to the client's
   state (channels, members, nick) and re-emitted as an `IrcEvent`.
4. `ChatController` (a Riverpod `Notifier`) keeps one `NetworkSession`
   (with its own `IrcClient`) per open network and turns each client's
   events into conversation buffers (`*status`, channels, private chats)
   with unread counts. Buffers are keyed by network and name. See
   [features/multi-network.md](features/multi-network.md). Chat lines are
   also saved through `ChatHistoryStore` and loaded into new conversations
   (see [features/chat-history.md](features/chat-history.md)).
5. The room browser calls `ChatController.fetchRooms`, which sends `LIST`
   to every connected network. Each client collects the replies into one
   `ChannelListEvent`, the controller stores them on that network's
   session, and the screen merges them (`ChatState.allRooms`), then filters
   and sorts them locally with `filterRooms`.
6. The chat screen watches the controller. Typed text goes through
   `runInput`, which maps `/commands` to client calls.

## Why the transport is an interface

iOS suspends sockets in the background. v1 reconnects when the app returns;
v2 adds bouncer support (soju/ZNC) and push. Because `IrcClient` only uses
`IrcTransport`, a bouncer or WebSocket transport can be dropped in without
touching the protocol code. Tests use an in-memory transport the same way.

## Storage

`main.dart` overrides `keyValueStoreProvider` with shared_preferences and
`secretStoreProvider` with flutter_secure_storage (Keychain on iOS/macOS,
encrypted storage on Android). Features only see the interfaces, and tests
use the in-memory defaults. Passwords never go into shared_preferences.

## Decisions

- Bouncer support: deferred to v2 (decided 2026-11-21).
- Models in `core/irc` are plain immutable Dart classes so the engine stays
  dependency-free; freezed is used for app-level models where it helps.
