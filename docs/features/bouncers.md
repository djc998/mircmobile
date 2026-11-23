# Bouncers (soju)

Available on iOS, Android and macOS (shared Flutter code). A bouncer stays
connected to IRC for you, so you keep your nick and rooms while the app is
closed, and it keeps what was said for when you come back.

## soju

[soju](https://soju.im) holds several networks for one account. The app
supports its bouncer-networks extension, the same way soju's own clients
(goguma, gamja) do.

### Setting it up

1. **Advanced options → Username:** your soju username.
2. **Add your own network:** the bouncer's address and port, TLS as your
   bouncer is set up, and your soju password as the **Server password**.
3. **Connect.**

The bouncer appears as **`<address>` (bouncer)**, and every network on it
opens as its own entry (Libera.Chat, OFTC…), already connected and with its
rooms, because soju keeps them joined. Networks added on the bouncer later
(for example `/msg BouncerServ network create …`) open on their own too.

**Continue** remembers the bouncer, not each network: reconnecting it
brings its networks back.

Missed messages and older history come through IRCv3 chathistory, which
soju supports ([chathistory.md](chathistory.md)). Errors from soju (IRCv3
`FAIL` replies) show in the bouncer's or network's **Server messages**.

### How it works

- `IrcClient` asks for `soju.im/bouncer-networks` and
  `soju.im/bouncer-networks-notify`.
- The bouncer's own connection (no network bound) sends
  `BOUNCER LISTNETWORKS` after logging in and keeps
  `IrcClient.bouncerNetworks` up to date from `BOUNCER NETWORK <id>
  <attrs>` lines: the listing batch, then changes (only the attributes that
  changed; an empty value removes one; `*` means deleted). Each update is a
  `BouncerNetworksEvent`.
- `ChatController` opens a session per network:
  `IrcConnectionConfig.bouncerNetwork` is the network id, and the session
  is keyed `<host>/<id>` (`IrcConnectionConfig.networkKey`), so favorites,
  recents and saved history stay apart per network.
- A network's connection sends `BOUNCER BIND <id>` just before `CAP END`.
  soju only allows that once logged in, and a server password is only
  checked after registration, so these connections log in with SASL PLAIN
  using the username and server password.

## ZNC and others

ZNC works as an ordinary server: add it with your ZNC password as the
server password (ZNC's `user/network:password` form picks the network).
History playback depends on ZNC's own modules.

## Code

- `lib/core/irc/irc_client.dart`: `IrcConnectionConfig.bouncerNetwork` and
  `networkKey`, `isBouncer`, `bouncerNetworks`, the SASL login for bound
  connections, `FAIL` replies.
- `lib/core/irc/irc_events.dart`: `BouncerNetwork`, `BouncerNetworksEvent`.
- `lib/core/irc/cap_negotiator.dart`: `beforeEnd` (for BIND).
- `lib/features/chat/application/chat_controller.dart`: sessions keyed by
  `networkKey`, opening the bouncer's networks, `NetworkSession.isBouncer`
  and its label.

## Tests

`test/core/irc/bouncer_test.dart` (BIND order, SASL for bound networks,
listing and changes, FAIL, keys) and
`test/features/chat/bouncer_flow_test.dart` (a bouncer opens each network
once, with the same login, and later ones too). Checked against soju
0.10.1 running locally with a network on Ergo's test server.
