/// One direct (DCC) file transfer, in or out, and where it's at.
library;

import 'dart:io';

import 'package:irc_client/core/irc/dcc.dart';

enum DccDirection { incoming, outgoing }

enum DccState {
  /// Incoming: waiting for you to accept or decline.
  offered,

  /// Outgoing: offered, waiting for them to connect.
  waiting,

  /// Connecting or sending bytes.
  transferring,
  done,
  failed,
  declined,
}

class DccTransfer {
  DccTransfer({
    required this.id,
    required this.networkId,
    required this.nick,
    required this.name,
    required this.size,
    required this.direction,
    required this.state,
    this.offer,
  });

  final String id;
  final String networkId;

  /// The other person.
  final String nick;

  /// The file's name, made safe to save.
  final String name;

  /// Size in bytes; 0 when the sender didn't say.
  final int size;
  final DccDirection direction;

  /// For incoming transfers: what was offered.
  final DccOffer? offer;

  DccState state;

  /// Bytes received or sent so far.
  int done = 0;

  /// Incoming, once done: the received file (in temporary storage).
  File? file;

  /// Why it failed, to show.
  String? error;

  bool get incoming => direction == DccDirection.incoming;

  /// 0 to 1, or null when the size isn't known.
  double? get progress => size > 0 ? (done / size).clamp(0, 1) : null;
}
