# Your own networks

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

Under the built-in networks on the welcome screen (and **Add a network**),
**Add your own network** opens a form:

- **Server address**, such as `irc.example.net`. Typing
  `irc.example.net:7000`, `irc.example.net:+7000` or an
  `ircs://irc.example.net:6697/#room` link fills in the port (and TLS for
  `+port` and `ircs://`).
- **Port**: 6697 to start with.
- **Secure connection (TLS)**: on by default. Turning it off moves the port
  to 6667 unless another port was typed, and warns that messages and
  passwords are sent unencrypted.
- **Name (optional)**: shown in the list; the address is used without one.
- **Server password (optional)**: sent as `PASS` before registering, for
  bouncers such as soju or ZNC and private servers. Kept in the device
  keychain, never in the settings file.

**Connect** saves the network and connects with the nickname and Advanced
options above. Added networks appear under the built-in ones with a server
icon, their address and port, and an **Edit** button that reopens the
form with **Save**, **Save and connect** and **Remove**. Servers already in
the built-in list can't be added again.

Added networks work like built-in ones: **Connect to all** includes them,
**Continue** reconnects them next launch, and self-signed certificates get
the same trust-once prompt. Rooms on them assume standard NickServ and
ChanServ.

## Code

- `lib/features/connection/data/custom_networks.dart`: `CustomNetwork`,
  `parseServer`, `defaultPort`, `customNetworksProvider`
  (`CustomNetworksController`: `save`, `remove`, `password`), stored under
  `customNetworks`; passwords under `pass:<host>` in the `SecretStore`.
- `lib/features/connection/presentation/custom_network_sheet.dart`:
  `showCustomNetworkSheet`, `CustomNetworkAction`.
- `lib/features/connection/presentation/network_picker_screen.dart`: lists
  them, the Edit button on `_NetworkCard`, and `serverPassword` when
  connecting.

## Tests

`test/features/connection/custom_networks_test.dart`: address parsing,
saving/editing/removing with the password, adding and connecting (port,
TLS off, `PASS`), editing and removing from the list, and refusing a
built-in network.
