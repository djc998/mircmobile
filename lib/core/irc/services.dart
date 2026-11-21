/// Building messages to a network's NickServ and ChanServ, so users can
/// register their nickname and keep their rooms without typing commands.
library;

import 'package:irc_client/core/irc/networks.dart';

/// Website where Undernet rooms are registered.
const String undernetChannelServiceUrl = 'https://cservice.undernet.org/live/';

/// A message to send to a service: `PRIVMSG target :text`.
typedef ServiceMessage = ({String target, String text});

class NetworkServices {
  const NetworkServices(this.kind);

  final ServicesKind kind;

  /// Whether nicknames can be registered from the app.
  bool get canRegisterNick =>
      kind == ServicesKind.standard || kind == ServicesKind.dalnet;

  /// Whether rooms can be registered from the app.
  bool get canRegisterRoom => canRegisterNick;

  /// DALnet asks for a separate room password when registering.
  bool get roomNeedsPassword => kind == ServicesKind.dalnet;

  String get nickServ =>
      kind == ServicesKind.dalnet ? 'NickServ@services.dal.net' : 'NickServ';

  String get chanServ =>
      kind == ServicesKind.dalnet ? 'ChanServ@services.dal.net' : 'ChanServ';

  /// Registers the current nickname. Most networks email a code to confirm.
  ServiceMessage registerNick(String password, String email) =>
      (target: nickServ, text: 'REGISTER $password $email');

  /// Logs in to the current nickname's account.
  ServiceMessage identify(String password) =>
      (target: nickServ, text: 'IDENTIFY $password');

  /// Registers [channel] to the logged-in account, so it is kept even when
  /// empty and the owner always gets operator status back.
  ServiceMessage registerRoom(
    String channel, {
    String? password,
    String description = 'Created with the app',
  }) => kind == ServicesKind.dalnet
      ? (
          target: chanServ,
          text: 'REGISTER $channel ${password ?? ''} $description',
        )
      : (target: chanServ, text: 'REGISTER $channel');

  /// Why rooms can't be kept from the app on this network, or null.
  String? get roomLimitation => switch (kind) {
    ServicesKind.standard || ServicesKind.dalnet => null,
    ServicesKind.undernet =>
      'Undernet keeps rooms through its channel service X, which needs a '
          'sign-up on its website ($undernetChannelServiceUrl). Until then '
          'the room stays while someone is in it.',
    ServicesKind.none =>
      "This network has no channel service, so rooms can't be kept: a room "
          'lasts only while someone is in it, and the next person to join an '
          'empty room becomes its operator.',
  };
}
