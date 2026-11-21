/// Built-in IRC networks so users don't need to know server addresses.
library;

class IrcNetwork {
  const IrcNetwork({
    required this.name,
    required this.host,
    required this.description,
    this.port = 6697,
    this.useTls = true,
  });

  final String name;
  final String host;
  final int port;
  final bool useTls;
  final String description;
}

const List<IrcNetwork> builtInNetworks = [
  IrcNetwork(
    name: 'Libera.Chat',
    host: 'irc.libera.chat',
    description: 'Free and open source projects, tech and communities.',
  ),
  IrcNetwork(
    name: 'OFTC',
    host: 'irc.oftc.net',
    description: 'Open source projects such as Debian and Tor.',
  ),
  IrcNetwork(
    name: 'EFnet',
    host: 'irc.efnet.org',
    description: 'One of the original IRC networks, since 1990.',
  ),
  IrcNetwork(
    name: 'Undernet',
    host: 'irc.undernet.org',
    description: 'Classic general chat network with many social rooms.',
  ),
  IrcNetwork(
    name: 'DALnet',
    host: 'irc.dal.net',
    description: 'Friendly social chat, a favourite of the mIRC era.',
  ),
  IrcNetwork(
    name: 'Rizon',
    host: 'irc.rizon.net',
    description: 'Large general-purpose network: gaming, anime and more.',
  ),
];
