# Network compatibility notes

Checked 2026-11-21 from a home connection (port 6697, TLS).

| Network | TLS certificate | Notes |
|---|---|---|
| Libera.Chat | Valid (Let's Encrypt) | Works |
| OFTC | Valid (Let's Encrypt) | Works |
| DALnet | Valid (Let's Encrypt, *.dal.net) | Bans logins where nick, username and real name are identical (`[exp/dm]`). Fixed by sending distinct defaults. Also bans IPs on its drone/proxy lists. |
| Rizon | Valid (Let's Encrypt) | Works |
| EFnet | Self-signed, mismatched or expired on every server tested | Needs **Trust and connect** once per server certificate. `irc.efnet.org` rotates between servers, so you may be asked again for a different server. |
| Undernet | None: no server offers TLS | Rechecked 2026-11-24 on all seven servers behind `irc.undernet.org`: 6697 is closed or refuses, and 6667/7000 are plain text only. The preset connects to 6667 without encryption and says so. |
