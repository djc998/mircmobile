# Direct file transfers (DCC)

Available on iOS, Android and macOS (shared Flutter code), in private
chats. For files with people on classic IRC apps (mIRC, HexChat, irssi…),
or on the same Wi-Fi. For everything else, sending through the server
([file-sharing.md](file-sharing.md)) is more dependable.

## What the user sees

- **Receiving:** an offer shows as `📁 Direct file: album.zip (68 KB)` with
  a card: **Accept** or **Decline**, and "Accepting connects to bob, who
  will see your IP address. Only accept files from people you trust."
  Accepting shows progress, then **Received** and **Save** (the share
  sheet on iPhone and Android, a save dialog on the Mac). Nothing is ever
  downloaded without Accept.
- **Sending:** **+** → **Send a file** asks how:
  - **Through the server:** encrypted, works on any network, 25 MB at
    most (the default when the server is set up).
  - **Directly (DCC):** "Works with mIRC and HexChat. Shows them your IP
    address, and usually only works on the same Wi-Fi." No size limit.
  A direct send shows "Waiting for bob to accept (2 minutes)…", then
  progress, then **Sent**, or why it didn't work.
- Offers from ignored people are dropped. Declining sends nothing back
  (DCC has no standard "no").
- If a direct transfer can't connect, the card says so: they're usually
  only possible on the same network, or with an open port.

## How it works

- An offer is a CTCP message: `DCC SEND <name> <ip> <port> <size>`, with
  names that have spaces in quotes, IPv4 written as one number, or an IPv6
  address. The receiver connects and reads the bytes, acknowledging with
  the 4-byte count received so far.
- **Passive** offers (port 0 and a token, from senders that can't accept
  connections) are supported: the app listens and replies with its own
  address, port and the token.
- Sending listens on a free port on the device's local address (a private
  IPv4 if there is one) and offers that; one connection is accepted within
  2 minutes.
- Received files stream to a temporary file (2 GB at most), so large files
  don't sit in memory. A transfer that stops early, stalls for a minute or
  can't connect fails with a clear message.
- Transfers live while the app runs; after a restart the offer is plain
  text.
- iOS asks once for **Local Network** access (`NSLocalNetworkUsageDescription`);
  the Mac already had the network server entitlement.

## Code

- `lib/core/irc/dcc.dart`: `DccOffer.parse`, `dccSendArgs`,
  `localAddress`, `DccListener`, `sendDcc`, `receiveDcc`,
  `receivePassiveDcc`, `DccException`.
- `lib/core/irc/irc_client.dart`: CTCP `DCC` becomes a `DccOfferEvent`
  (never from history); `sendCtcp`.
- `lib/features/pictures/domain/dcc_transfer.dart`: `DccTransfer`.
- `ChatController`: `transfer`, `acceptDcc`, `declineDcc`, `sendDccFile`;
  `ChatLine.dccId`.
- `lib/features/pictures/presentation/file_widgets.dart`: `DccCard`, the
  send sheet's choice. `lib/core/storage/temp_files.dart`: `tempFolder`.

## Tests

`test/core/irc/dcc_test.dart` (parsing, writing, and real transfers over
sockets: plain, passive, cut short, nobody there) and
`test/features/pictures/dcc_flow_test.dart` (accept and save, decline,
ignored people, send directly). Checked live: an offer sent through Ergo's
test server reached another connection, which received 2 MB directly and
exactly.
