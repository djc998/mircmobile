# IRC core

Status: done (v0.1, unreleased). Platforms: iOS, Android, macOS.

## What it does

- Connects over TLS (port 6697) by default. Plain-text connections are
  possible for custom servers and are labelled "NOT encrypted".
- Certificates are always verified. When a server's certificate fails
  (self-signed, wrong name or expired, common on EFnet), the connection
  stops and the app asks the user. Trusting stores that certificate's
  SHA-256 fingerprint for the server host
  (`features/connection/data/certificate_trust.dart`); only that exact
  certificate is accepted afterwards. If TLS can't be opened at all, the
  user can choose an unencrypted connection on port 6667.
- Sends username `mobile` and real name `Mobile IRC user` unless the user
  sets their own ("More options"). The nickname is never reused for these,
  because DALnet bans logins where all three match as bots.
- Negotiates IRCv3 capabilities: `server-time`, `message-tags`,
  `multi-prefix`, `away-notify`, `account-notify`, `extended-join`,
  `echo-message`, `cap-notify`, `userhost-in-names`, `batch`, plus `sasl`
  when the user logs in with an account.
- Logs in with SASL PLAIN. If the server rejects the login or doesn't offer
  PLAIN, registration still continues and the user sees the outcome.
- Picks `nick_`, `nick__`, ... when the nickname is taken while connecting.
- Sends a keepalive PING after 90 s of silence and reconnects if nothing
  comes back within 60 s. Reconnects back off 2 s, 4 s, 8 s ... up to 5 min
  and rejoin every channel that was open.
- Limits outgoing lines to a burst of 5, then one every 1.5 s, so networks
  don't disconnect the user for flooding.

## Commands

| Command | What it does |
|---|---|
| `/join #room [key]` (`/j`) | Join a room; `#` is added if missing |
| `/part [#room] [reason]` | Leave the current or named room |
| `/msg nick text` | Private message |
| `/query nick [text]` (`/q`) | Open a private chat |
| `/me action` | Action, shown as `* nick action` |
| `/notice target text` | Send a notice |
| `/nick name` | Change nickname |
| `/topic [#room] [text]` | Show or set the topic |
| `/whois nick` (`/wi`) | Look up a user |
| `/list [min users]` | List rooms on the network |
| `/quote raw line` (`/raw`) | Send a raw IRC line |
| `/quit [reason]` | Disconnect |
| `//text` | Send text that starts with `/` |

## Tests

`test/core/irc/` covers the parser, line decoder, CAP/SASL negotiation,
ISUPPORT, the client state machine (with a fake transport) and the input
commands. `test/features/chat_flow_test.dart` drives the screens end to end
against a fake server.
