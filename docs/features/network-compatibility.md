# Network compatibility notes

Checked 2026-11-21 from a home connection (port 6697, TLS).

| Network | TLS certificate | Notes |
|---|---|---|
| Libera.Chat | Valid (Let's Encrypt) | Works |
| OFTC | Valid (Let's Encrypt) | Works |
| DALnet | Valid (Let's Encrypt, *.dal.net) | Bans logins where nick, username and real name are identical (`[exp/dm]`). Fixed by sending distinct defaults. Also bans IPs on its drone/proxy lists. |
| Rizon | Valid (Let's Encrypt) | Works |
| EFnet | Self-signed, mismatched or expired on every server tested | Needs **Trust and connect** once per server certificate. `irc.efnet.org` rotates between servers, so you may be asked again for a different server. |
| Undernet | Not reachable on 6697 during the check | Use **Connect without encryption** if the secure connection fails. |
