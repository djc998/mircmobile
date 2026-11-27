/// Typed events emitted by `IrcClient`.
library;

import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/irc_message.dart';
import 'package:irc_client/core/irc/irc_transport.dart';

/// Lifecycle of a connection.
enum IrcConnectionStatus {
  disconnected,
  connecting,
  registering,
  connected,
  reconnecting,
}

/// Base class for everything the client reports to the UI.
sealed class IrcEvent {
  IrcEvent({DateTime? time}) : time = time ?? DateTime.now();

  final DateTime time;
}

/// Every raw line, in or out. Useful for a debug/status window.
class RawLineEvent extends IrcEvent {
  RawLineEvent(this.line, {required this.outgoing});

  final String line;
  final bool outgoing;
}

class StatusChangedEvent extends IrcEvent {
  StatusChangedEvent(this.status, {this.reason});

  final IrcConnectionStatus status;
  final String? reason;
}

/// The server answered `IrcClient.checkConnection`: the connection is
/// alive and nothing needs reconnecting.
class ConnectionCheckedEvent extends IrcEvent {
  ConnectionCheckedEvent();
}

/// Registration finished (RPL_WELCOME).
class RegisteredEvent extends IrcEvent {
  RegisteredEvent({required this.nick, required this.network});

  final String nick;

  /// The network name from ISUPPORT NETWORK=, or the server name.
  final String network;
}

/// The server sent RPL_ISUPPORT (005); [network] is the network's name.
class ServerInfoEvent extends IrcEvent {
  ServerInfoEvent({required this.network});

  final String network;
}

/// The server's TLS certificate failed verification and isn't trusted yet.
/// The connection was not made; the UI should ask the user what to do.
class CertificateRejectedEvent extends IrcEvent {
  CertificateRejectedEvent({required this.host, required this.certificate});

  final String host;
  final CertificateInfo certificate;
}

class SaslEvent extends IrcEvent {
  SaslEvent(this.outcome);

  final SaslOutcome outcome;
}

/// A PRIVMSG or NOTICE, including CTCP ACTION (/me).
class MessageEvent extends IrcEvent {
  MessageEvent({
    required this.target,
    required this.sender,
    required this.text,
    required this.isOwn,
    this.isAction = false,
    this.isNotice = false,
    this.tags = const {},
    this.history = false,
    super.time,
  });

  /// The channel, or for a private message the other party's nick.
  final String target;
  final String sender;
  final String text;
  final bool isOwn;
  final bool isAction;
  final bool isNotice;
  final Map<String, String> tags;

  /// Sent again from the server's history (CHATHISTORY), not live.
  final bool history;

  /// The server's id for the message (IRCv3 `msgid`), if it gave one.
  String? get msgid => tags['msgid'];
}

class JoinEvent extends IrcEvent {
  JoinEvent({
    required this.channel,
    required this.nick,
    required this.isSelf,
    this.isRejoin = false,
    super.time,
  });

  final String channel;
  final String nick;
  final bool isSelf;

  /// The client rejoining a room on its own after a reconnect, not the
  /// user joining it.
  final bool isRejoin;
}

class PartEvent extends IrcEvent {
  PartEvent({
    required this.channel,
    required this.nick,
    required this.isSelf,
    this.reason,
    this.kickedBy,
    super.time,
  });

  final String channel;
  final String nick;
  final bool isSelf;
  final String? reason;

  /// Set when the user was kicked rather than leaving.
  final String? kickedBy;
}

class QuitEvent extends IrcEvent {
  QuitEvent({
    required this.nick,
    required this.channels,
    this.reason,
    super.time,
  });

  final String nick;

  /// Channels the user shared with us.
  final List<String> channels;
  final String? reason;
}

class NickChangeEvent extends IrcEvent {
  NickChangeEvent({
    required this.oldNick,
    required this.newNick,
    required this.isSelf,
    required this.channels,
    super.time,
  });

  final String oldNick;
  final String newNick;
  final bool isSelf;
  final List<String> channels;
}

class TopicEvent extends IrcEvent {
  TopicEvent({required this.channel, required this.topic, this.setBy});

  final String channel;
  final String topic;
  final String? setBy;
}

/// The member list of a channel changed (after NAMES, JOIN, PART, ...).
class MembersChangedEvent extends IrcEvent {
  MembersChangedEvent(this.channel);

  final String channel;
}

/// One entry from a LIST reply.
class ChannelListEntry {
  const ChannelListEntry({
    required this.name,
    required this.userCount,
    required this.topic,
  });

  final String name;
  final int userCount;
  final String topic;
}

/// Results of a LIST request, delivered once RPL_LISTEND arrives.
class ChannelListEvent extends IrcEvent {
  ChannelListEvent(this.entries);

  final List<ChannelListEntry> entries;
}

/// A server error numeric or ERROR line worth showing to the user.
class ServerErrorEvent extends IrcEvent {
  ServerErrorEvent({required this.code, required this.text, this.target});

  final String code;
  final String text;
  final String? target;
}

/// Any other server message, e.g. MOTD lines and WHOIS replies.
class ServerNoticeEvent extends IrcEvent {
  ServerNoticeEvent(this.message, {required this.text});

  final IrcMessage message;
  final String text;
}

/// A channel's modes changed (MODE), or the server told us its modes (324).
class ChannelModeEvent extends IrcEvent {
  ChannelModeEvent({
    required this.channel,
    required this.change,
    this.setBy,
    super.time,
  });

  final String channel;

  /// The mode string with its arguments, e.g. `+ik secret`.
  final String change;

  /// Who changed it; null for the server's reply to a MODE query (324).
  final String? setBy;
}

/// Someone invited us to a channel.
class InviteEvent extends IrcEvent {
  InviteEvent({required this.from, required this.channel, super.time});

  final String from;
  final String channel;
}

/// A CHATHISTORY reply for [target] finished; [count] messages came in it.
/// [failed] when the server refused the request (FAIL CHATHISTORY), in which
/// case [target] may be null.
class HistoryBatchEvent extends IrcEvent {
  HistoryBatchEvent({
    required this.target,
    required this.count,
    this.failed = false,
  });

  final String? target;
  final int count;
  final bool failed;
}

/// Conversations with messages in a time range (CHATHISTORY TARGETS): rooms
/// and people, each with the time of its latest message.
class HistoryTargetsEvent extends IrcEvent {
  HistoryTargetsEvent(this.targets);

  final List<({String name, DateTime latest})> targets;
}

/// A soju bouncer's networks, listed or changed (keyed by network id).
class BouncerNetworksEvent extends IrcEvent {
  BouncerNetworksEvent(this.networks);

  final Map<String, BouncerNetwork> networks;
}

/// A network on a soju bouncer (`BOUNCER NETWORK` attributes).
class BouncerNetwork {
  const BouncerNetwork({required this.id, required this.attributes});

  final String id;

  /// Attributes such as `name`, `host`, `state` (connected, connecting,
  /// disconnected) and `nickname`.
  final Map<String, String> attributes;

  String get name => attributes['name'] ?? attributes['host'] ?? id;
  String? get host => attributes['host'];
  String get state => attributes['state'] ?? 'disconnected';
}

/// Someone's typing state in a conversation (IRCv3 `+typing`): `active`,
/// `paused` or `done`.
class TypingEvent extends IrcEvent {
  TypingEvent({required this.target, required this.nick, required this.state});

  /// The channel, or for a private chat the other person's nick.
  final String target;
  final String nick;
  final String state;
}

/// Where you've read up to in [target], from the server (IRCv3
/// `draft/read-marker`), e.g. after reading it on another device. Null
/// [readUntil] means the server doesn't know yet.
class ReadMarkerEvent extends IrcEvent {
  ReadMarkerEvent({required this.target, required this.readUntil});

  final String target;
  final DateTime? readUntil;
}

/// Someone sent a DCC request (`DCC SEND …` for a file). [args] is the part
/// after `DCC `; parse it with `DccOffer.parse`.
class DccOfferEvent extends IrcEvent {
  DccOfferEvent({required this.from, required this.args});

  final String from;
  final String args;
}
