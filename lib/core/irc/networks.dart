/// Built-in IRC networks so users don't need to know server addresses.
library;

class IrcNetwork {
  const IrcNetwork({
    required this.name,
    required this.host,
    required this.description,
    this.port = 6697,
    this.useTls = true,
    this.services = ServicesKind.standard,
  });

  final String name;
  final String host;
  final int port;
  final bool useTls;
  final String description;

  /// Which nickname/room registration service the network runs.
  final ServicesKind services;
}

/// The kind of registration services (NickServ/ChanServ) a network has.
enum ServicesKind {
  /// NickServ and ChanServ that accept `REGISTER` by message (Atheme,
  /// Anope, OFTC services): Libera.Chat, OFTC, Rizon and most networks.
  standard,

  /// DALnet: services are addressed as `NickServ@services.dal.net` and a
  /// room needs its own password to register.
  dalnet,

  /// Undernet: rooms are registered on the X website, not by message.
  undernet,

  /// No services at all (EFnet): rooms can't be kept.
  none,
}

/// Services for [host]; networks not in the list are assumed standard.
ServicesKind servicesFor(String host) {
  for (final n in builtInNetworks) {
    if (n.host.toLowerCase() == host.toLowerCase()) return n.services;
  }
  return ServicesKind.standard;
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
    services: ServicesKind.none,
  ),
  IrcNetwork(
    name: 'Undernet',
    host: 'irc.undernet.org',
    description: 'Classic general chat network with many social rooms.',
    services: ServicesKind.undernet,
  ),
  IrcNetwork(
    name: 'DALnet',
    host: 'irc.dal.net',
    description: 'Friendly social chat, a favourite of the mIRC era.',
    services: ServicesKind.dalnet,
  ),
  IrcNetwork(
    name: 'Rizon',
    host: 'irc.rizon.net',
    description: 'Large general-purpose network: gaming, anime and more.',
  ),
];
