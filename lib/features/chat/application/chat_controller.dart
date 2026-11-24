/// App-side chat state built from [IrcClient] events.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/dcc.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/input_commands.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/core/irc/services.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/storage/temp_files.dart';
import 'package:irc_client/features/calls/application/call_controller.dart';
import 'package:irc_client/features/calls/domain/call_link.dart';
import 'package:irc_client/features/chat/data/chat_history_store.dart';
import 'package:irc_client/features/connection/data/certificate_trust.dart';
import 'package:irc_client/features/connection/data/saved_connection.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/dcc_transfer.dart';
import 'package:irc_client/features/pictures/domain/file_link.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:irc_client/features/rooms/domain/room_modes.dart';
import 'package:irc_client/features/safety/application/safety_controller.dart';

/// Name of the server/status buffer.
const String statusBuffer = '*status';

/// How many lines each conversation keeps in memory.
const int maxLinesPerBuffer = 1000;

enum ChatLineKind { message, action, notice, event, error, own }

/// Someone arriving or leaving, so runs of these can be shown as one line
/// ("mara, kai and 3 others joined").
enum PresenceChange { joined, left }

class ChatLine {
  ChatLine({
    required this.text,
    required this.kind,
    this.sender,
    DateTime? time,
    this.presence,
    this.subject,
    this.msgid,
    this.dccId,
  }) : time = time ?? DateTime.now();

  factory ChatLine.fromStored(StoredLine line) => ChatLine(
    text: line.text,
    sender: line.sender,
    time: line.time.toLocal(),
    kind: ChatLineKind.values.asNameMap()[line.kind] ?? ChatLineKind.message,
    msgid: line.msgid,
  );

  final DateTime time;
  final String? sender;
  final String text;
  final ChatLineKind kind;

  /// Set on join, part and quit events (not kicks or your own joins).
  final PresenceChange? presence;

  /// Who [presence] is about.
  final String? subject;

  /// The server's id for the message (IRCv3 `msgid`), when it gave one;
  /// used to skip messages that come again from history.
  final String? msgid;

  /// A direct (DCC) file transfer this line is about; see
  /// [ChatController.transfer]. Not saved: after a restart the line is
  /// plain text.
  final String? dccId;

  /// Whether this kind of line is kept in saved history.
  bool get isSaved => switch (kind) {
    ChatLineKind.message ||
    ChatLineKind.action ||
    ChatLineKind.notice ||
    ChatLineKind.own => true,
    ChatLineKind.event || ChatLineKind.error => false,
  };

  StoredLine toStored() => StoredLine(
    time: time,
    kind: kind.name,
    text: text,
    sender: sender,
    msgid: msgid,
  );

  /// Whether [other] is the same message (from history, say): the same
  /// msgid, or the same sender and text within a few seconds.
  bool sameMessage(ChatLine other) {
    if (msgid != null && other.msgid != null) return msgid == other.msgid;
    return sender == other.sender &&
        text == other.text &&
        time.difference(other.time).abs() < const Duration(seconds: 3);
  }
}

/// One conversation on one network: its status window, a channel or a
/// private chat.
/// What a CHATHISTORY request for a conversation is for.
enum HistoryWant { missed, older }

class ChatBuffer {
  ChatBuffer(this.networkId, this.name);

  /// Id of the [NetworkSession] this conversation belongs to.
  final String networkId;
  final String name;
  final List<ChatLine> lines = [];
  int unread = 0;
  bool mentioned = false;

  /// The first line that arrived while this conversation wasn't open.
  ChatLine? firstUnread;

  /// Where the "New messages" divider goes while the conversation is open:
  /// [firstUnread] at the moment it was opened.
  ChatLine? unreadMarker;

  /// The message the user is replying to, shown above the input. Sending
  /// puts `nick: ` in front so that person is notified.
  ChatLine? replyTo;

  /// True while saved history is being read; new lines wait in
  /// [pendingSave] so they aren't saved twice.
  bool restoring = false;
  final List<StoredLine> pendingSave = [];

  /// Done once saved history has been read (right away when there's none).
  Future<void> restored = Future.value();

  /// A CHATHISTORY request for this conversation is out: older messages
  /// ([HistoryWant.older]) or missed ones ([HistoryWant.missed]).
  HistoryWant? historyWant;

  /// Messages the current history request actually added.
  int historyAdded = 0;

  /// The server has nothing older than what's shown.
  bool historyExhausted = false;

  /// Who's typing here (IRCv3 `+typing`), by case-folded nick, and until
  /// when it counts: 6 seconds after "active", 30 after "paused".
  final Map<String, ({String nick, DateTime until})> typing = {};

  /// Redraws the typing line when the next one runs out.
  Timer? typingTimer;

  /// When we last told others we're typing here; null once done.
  DateTime? typingSentAt;

  /// Read up to here, as the server knows it (draft/read-marker).
  DateTime? readUntil;

  /// Sends the read position after a short pause, not on every message.
  Timer? readTimer;

  /// Who's typing right now, in the order they started.
  List<String> get typingNicks {
    final now = clock.now();
    return [
      for (final t in typing.values)
        if (t.until.isAfter(now)) t.nick,
    ];
  }

  /// The newest chat line (message, action, notice or own), if any.
  ChatLine? get newestMessage {
    for (var i = lines.length - 1; i >= 0; i--) {
      if (lines[i].isSaved) return lines[i];
    }
    return null;
  }

  /// The oldest chat line, if any.
  ChatLine? get oldestMessage {
    for (final l in lines) {
      if (l.isSaved) return l;
    }
    return null;
  }

  /// Unique across networks; see [ChatState.bufferKey].
  String get key => ChatState.bufferKey(networkId, name);

  /// Pictures being uploaded to this conversation right now.
  int uploading = 0;

  bool get isStatus => name == statusBuffer;
  bool get isChannel => name.startsWith('#') || name.startsWith('&');
}

/// One network the user is connected to (or was, and may reconnect to).
///
/// Several sessions can be open at once; each has its own [IrcClient].
class NetworkSession {
  NetworkSession({required this.config, required this.client})
    : id = config.networkKey,
      nick = config.nick;

  /// Lower-cased host the user picked, e.g. `irc.libera.chat`, plus
  /// `/<id>` for one of a soju bouncer's networks. Favorites, recents and
  /// saved history are keyed by it.
  final String id;
  IrcConnectionConfig config;
  IrcClient client;

  // Cancelled by the controller when the network is replaced or closed.
  // ignore: cancel_subscriptions
  StreamSubscription<IrcEvent>? subscription;

  IrcConnectionStatus status = IrcConnectionStatus.disconnected;

  /// Name the network gives itself (ISUPPORT NETWORK), once known.
  String name = '';
  String nick;

  /// When [ChatController] last saved "messages seen until" for this
  /// network; writes are kept to one a minute.
  DateTime? seenSavedAt;

  /// The "seen until" time the last catch-up asked the server from.
  DateTime? historySince;

  /// Rooms from the last LIST on this network.
  List<ChannelListEntry> rooms = const [];
  bool roomsLoading = false;
  DateTime? roomsFetchedAt;
  String? roomsError;

  /// Set when the server's certificate failed verification; the chat screen
  /// asks whether to trust it.
  CertificateInfo? untrustedCertificate;

  /// Set when a secure (TLS) connection couldn't be opened at all, so the
  /// chat screen can offer an unencrypted connection instead.
  bool secureConnectFailed = false;

  /// Conversation that WHOIS replies go to while a WHOIS is running.
  String? whoisBuffer;

  /// Room the user asked to join from the browser; opened when joined.
  String? pendingSelect;

  /// Rooms the user is creating, by lower-cased name, with the settings to
  /// apply once the server confirms we run the room.
  final Map<String, RoomSettings> pendingCreate = {};

  /// Invitations waiting for Join or Ignore.
  final List<RoomInvite> invites = [];

  /// Logged in to a services account (SASL succeeded).
  bool loggedIn = false;

  /// This network's NickServ/ChanServ.
  NetworkServices get services => NetworkServices(servicesFor(id));

  /// Display name: the network's own name, or its host until known. A
  /// bouncer's own connection shows the address it was added with.
  String get label {
    if (isBouncer) return '${config.host} (bouncer)';
    return name.isEmpty ? config.host : name;
  }

  /// The soju bouncer's own connection, which lists its networks (each
  /// network has its own session).
  bool get isBouncer => client.isBouncer && config.bouncerNetwork == null;

  bool get isConnected => status == IrcConnectionStatus.connected;

  bool get hasConnectionProblem =>
      untrustedCertificate != null || secureConnectFailed;

  void clearConnectionProblem() {
    untrustedCertificate = null;
    secureConnectFailed = false;
  }
}

/// Someone invited the user to a room.
class RoomInvite {
  const RoomInvite({required this.from, required this.channel});

  final String from;
  final String channel;
}

/// A room from a LIST reply, tagged with the network it is on.
class NetworkRoom {
  const NetworkRoom(this.network, this.entry);

  final NetworkSession network;
  final ChannelListEntry entry;
}

class ChatState {
  const ChatState({
    this.networks = const {},
    this.buffers = const {},
    this.activeKey,
    this.revision = 0,
  });

  /// Open networks keyed by [NetworkSession.id], in the order added.
  final Map<String, NetworkSession> networks;

  /// Buffers keyed by [bufferKey], in insertion order.
  final Map<String, ChatBuffer> buffers;

  /// Key of the open conversation.
  final String? activeKey;

  /// Bumped on every change so listeners rebuild.
  final int revision;

  static String bufferKey(String networkId, String name) =>
      '$networkId/${name.toLowerCase()}';

  ChatBuffer? get activeBuffer => activeKey == null ? null : buffers[activeKey];

  /// Network of the open conversation (or the first network).
  NetworkSession? get activeNetwork {
    final buffer = activeBuffer;
    if (buffer != null) return networks[buffer.networkId];
    return networks.values.firstOrNull;
  }

  List<ChatBuffer> buffersFor(String networkId) => [
    for (final b in buffers.values)
      if (b.networkId == networkId) b,
  ];

  List<NetworkSession> get connectedNetworks => [
    for (final n in networks.values)
      if (n.isConnected) n,
  ];

  /// Rooms from every network, for the room browser.
  List<NetworkRoom> get allRooms => [
    for (final n in networks.values)
      for (final r in n.rooms) NetworkRoom(n, r),
  ];

  bool get roomsLoading => networks.values.any((n) => n.roomsLoading);

  ChatState copyWith({
    Map<String, NetworkSession>? networks,
    Map<String, ChatBuffer>? buffers,
    String? activeKey,
  }) => ChatState(
    networks: networks ?? this.networks,
    buffers: buffers ?? this.buffers,
    activeKey: activeKey ?? this.activeKey,
    revision: revision + 1,
  );
}

/// Lets tests swap the network layer.
final transportFactoryProvider = Provider<IrcTransportFactory>(
  (ref) => defaultTransportFactory,
);

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

/// Owns one [IrcClient] per open network and turns their events into
/// conversations.
class ChatController extends Notifier<ChatState> {
  /// Every open session, so they can be closed when the app goes away
  /// (state can't be read while the provider is disposed).
  final _sessions = <NetworkSession>{};

  @override
  ChatState build() {
    ref.onDispose(() {
      for (final n in _sessions) {
        unawaited(n.subscription?.cancel());
        unawaited(n.client.dispose());
      }
      for (final b in _timedBuffers) {
        b.typingTimer?.cancel();
        b.readTimer?.cancel();
      }
    });
    return const ChatState();
  }

  /// Conversations with a typing or read timer running, to cancel them.
  final Set<ChatBuffer> _timedBuffers = {};

  static const _saveHistoryKey = 'saveHistory';
  static const _blockedKey = 'blockedNicks';
  static const _openConversationsKey = 'openConversations';

  /// Per network: when messages were last seen live, so a reconnect can
  /// ask the server which private chats had messages since.
  static const _historySeenKey = 'historySeen';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);
  ChatHistoryStore get _history => ref.read(chatHistoryStoreProvider);

  Set<String>? _blocked;

  /// Lower-cased nicknames whose messages, pictures and invitations are
  /// hidden, on every network.
  Set<String> get blockedNicks => _blocked ??= _loadBlocked();

  Set<String> _loadBlocked() {
    final raw = _store.getString(_blockedKey);
    if (raw == null) return {};
    try {
      return {...(jsonDecode(raw) as List<Object?>).whereType<String>()};
    } on Object {
      return {};
    }
  }

  bool isBlocked(String? nick) =>
      nick != null && blockedNicks.contains(nick.toLowerCase());

  /// Hides everything [nick] sends from now on (all networks).
  void blockUser(String nick) => _setBlocked(nick, blocked: true);

  void unblockUser(String nick) => _setBlocked(nick, blocked: false);

  void _setBlocked(String nick, {required bool blocked}) {
    final set = {...blockedNicks};
    if (blocked) {
      set.add(nick.toLowerCase());
    } else {
      set.remove(nick.toLowerCase());
    }
    _blocked = set;
    _touch();
    unawaited(_store.setString(_blockedKey, jsonEncode(set.toList()..sort())));
  }

  /// Encrypts and uploads [picture], then sends its link in the open
  /// conversation. Returns a message to show when it fails.
  Future<String?> sendPicture(
    Uint8List picture, {
    PictureExpiry expiry = PictureExpiry.fourHours,
    bool viewOnce = true,
  }) async {
    final session = state.activeNetwork;
    final buffer = state.activeBuffer;
    if (session == null || buffer == null || buffer.isStatus) {
      return 'Open a conversation first.';
    }
    if (session.status != IrcConnectionStatus.connected) {
      return 'Not connected to ${session.label}.';
    }
    final service = ref.read(pictureServiceProvider);
    if (!service.isConfigured) return "Photo sharing isn't set up yet.";
    buffer.uploading++;
    _touch();
    try {
      final link = await service.upload(
        picture,
        expiry: expiry,
        viewOnce: viewOnce,
      );
      if (session.status != IrcConnectionStatus.connected) {
        return 'Not connected to ${session.label}.';
      }
      runInput(session.client, link.message(session.nick), target: buffer.name);
      return null;
    } on PictureException catch (e) {
      return e.message;
    } finally {
      buffer.uploading--;
      _touch();
    }
  }

  // ---------------------------------------------------------------------
  // Direct file transfers (DCC SEND)
  // ---------------------------------------------------------------------

  final Map<String, DccTransfer> _transfers = {};
  var _transferCount = 0;

  /// The direct transfer with [id], if it's still known.
  DccTransfer? transfer(String id) => _transfers[id];

  DccTransfer _newTransfer({
    required NetworkSession session,
    required String nick,
    required String name,
    required int size,
    required DccDirection direction,
    required DccState state,
    DccOffer? offer,
  }) {
    final t = DccTransfer(
      id: 'dcc-${++_transferCount}',
      networkId: session.id,
      nick: nick,
      name: safeFileName(name),
      size: size,
      direction: direction,
      state: state,
      offer: offer,
    );
    _transfers[t.id] = t;
    return t;
  }

  void _onDccOffer(NetworkSession session, DccOfferEvent e) {
    if (isBlocked(e.from)) return;
    final offer = DccOffer.parse(e.args);
    if (offer == null) return;
    final t = _newTransfer(
      session: session,
      nick: e.from,
      name: offer.name,
      size: offer.size,
      direction: DccDirection.incoming,
      state: DccState.offered,
      offer: offer,
    );
    _addLine(
      session,
      e.from,
      ChatLine(
        sender: e.from,
        text:
            '📁 Direct file: ${t.name}'
            '${t.size > 0 ? ' (${formatFileSize(t.size)})' : ''}',
        kind: ChatLineKind.message,
        time: e.time,
        dccId: t.id,
      ),
    );
  }

  /// Accepts an incoming direct transfer: connects (or, for a passive
  /// offer, listens) and receives the file into temporary storage.
  Future<void> acceptDcc(String id) async {
    final t = _transfers[id];
    final offer = t?.offer;
    final session = t == null ? null : state.networks[t.networkId];
    if (t == null || offer == null || t.state != DccState.offered) return;
    t.state = DccState.transferring;
    _touch();
    var lastDraw = DateTime.now();
    void progress(int n) {
      t.done = n;
      final now = DateTime.now();
      if (now.difference(lastDraw) > const Duration(milliseconds: 200)) {
        lastDraw = now;
        _touch();
      }
    }

    try {
      final dir = await tempFolder('dcc');
      final into = File('${dir.path}/${t.id}-${t.name}');
      if (offer.passive) {
        await receivePassiveDcc(
          offer,
          into,
          reply: (args) => session?.client.sendCtcp(t.nick, 'DCC $args'),
          onProgress: progress,
        );
      } else {
        await receiveDcc(offer, into, onProgress: progress);
      }
      t
        ..file = into
        ..done = t.size > 0 ? t.size : await into.length()
        ..state = DccState.done;
    } on DccException catch (e) {
      t
        ..state = DccState.failed
        ..error = e.message;
    } on Object {
      t
        ..state = DccState.failed
        ..error = "Couldn't receive the file.";
    }
    if (ref.mounted) _touch();
  }

  /// Declines an incoming direct transfer (nothing is sent: DCC has no
  /// standard "no").
  void declineDcc(String id) {
    final t = _transfers[id];
    if (t == null || t.state != DccState.offered) return;
    t.state = DccState.declined;
    _touch();
  }

  /// Offers [file] directly to the open private chat and sends it when they
  /// connect (within 2 minutes). Returns an error to show, or null.
  Future<String?> sendDccFile(File file, {required String name}) async {
    final session = state.activeNetwork;
    final buffer = state.activeBuffer;
    if (session == null || buffer == null || buffer.isStatus) {
      return 'Open a conversation first.';
    }
    if (!session.isConnected) return 'Not connected to ${session.label}.';
    final DccListener listener;
    try {
      listener = await DccListener.open();
    } on DccException catch (e) {
      return e.message;
    } on Object {
      return "Couldn't start a direct transfer here.";
    }
    final size = await file.length();
    final t = _newTransfer(
      session: session,
      nick: buffer.name,
      name: name,
      size: size,
      direction: DccDirection.outgoing,
      state: DccState.waiting,
    );
    session.client.sendCtcp(
      buffer.name,
      'DCC ${dccSendArgs(t.name, listener.address, listener.port, size)}',
    );
    _addLine(
      session,
      buffer.name,
      ChatLine(
        sender: session.nick,
        text: '📁 Direct file: ${t.name} (${formatFileSize(size)})',
        kind: ChatLineKind.own,
        dccId: t.id,
      ),
    );
    unawaited(_runSend(t, listener, file));
    return null;
  }

  Future<void> _runSend(DccTransfer t, DccListener listener, File file) async {
    var lastDraw = DateTime.now();
    try {
      await sendDcc(
        listener,
        file,
        onProgress: (n) {
          t
            ..state = DccState.transferring
            ..done = n;
          final now = DateTime.now();
          if (now.difference(lastDraw) > const Duration(milliseconds: 200)) {
            lastDraw = now;
            if (ref.mounted) _touch();
          }
        },
      );
      t.state = DccState.done;
    } on DccException catch (e) {
      t
        ..state = DccState.failed
        ..error = e.message;
    } on Object {
      t
        ..state = DccState.failed
        ..error = "Couldn't send the file.";
    }
    if (ref.mounted) _touch();
  }

  /// Encrypts, uploads and sends a file to the open private chat. Returns
  /// an error to show, or null.
  Future<String?> sendFile(
    Uint8List bytes, {
    required String name,
    PictureExpiry expiry = PictureExpiry.fourHours,
  }) async {
    final session = state.activeNetwork;
    final buffer = state.activeBuffer;
    if (session == null || buffer == null || buffer.isStatus) {
      return 'Open a conversation first.';
    }
    if (session.status != IrcConnectionStatus.connected) {
      return 'Not connected to ${session.label}.';
    }
    final service = ref.read(pictureServiceProvider);
    if (!service.isConfigured) return "File sharing isn't set up yet.";
    buffer.uploading++;
    _touch();
    try {
      final link = await service.uploadFile(bytes, name: name, expiry: expiry);
      if (session.status != IrcConnectionStatus.connected) {
        return 'Not connected to ${session.label}.';
      }
      runInput(session.client, link.message(session.nick), target: buffer.name);
      return null;
    } on PictureException catch (e) {
      return e.message;
    } finally {
      buffer.uploading--;
      _touch();
    }
  }

  /// Sends [text] to [target] on [networkId]. Returns false when that
  /// network isn't connected.
  bool sendPrivateText(String networkId, String target, String text) {
    final session = state.networks[networkId];
    if (session == null || session.status != IrcConnectionStatus.connected) {
      return false;
    }
    runInput(session.client, text, target: target);
    return true;
  }

  /// Reports a picture to the server that holds it and blocks its sender.
  Future<String?> reportPicture(
    PictureLink link, {
    required String sender,
    required String networkId,
    required String reason,
  }) async {
    blockUser(sender);
    try {
      await ref
          .read(pictureServiceProvider)
          .report(link, sender: sender, network: networkId, reason: reason);
      return null;
    } on PictureException catch (e) {
      return e.message;
    }
  }

  /// Reports [line] (someone else's message, in [room] or a private chat)
  /// to the app's makers and ignores its sender. Returns an error message,
  /// or null.
  Future<String?> reportMessage(
    ChatLine line, {
    required String networkId,
    required String reason,
    String? room,
  }) async {
    final sender = line.sender;
    if (sender == null) return "That message can't be reported.";
    blockUser(sender);
    try {
      await ref
          .read(pictureServiceProvider)
          .reportMessage(
            text: stripFormatting(line.text),
            sender: sender,
            network: networkId,
            room: room,
            reason: reason,
          );
      return null;
    } on PictureException catch (e) {
      return e.message;
    }
  }

  /// Whether conversations are saved on this device (on by default).
  bool get saveHistory => _store.getString(_saveHistoryKey) != 'false';

  Future<void> setSaveHistory({required bool enabled}) =>
      _store.setString(_saveHistoryKey, '$enabled');

  /// Deletes a conversation's saved history and clears it on screen.
  Future<void> clearHistory(String key) async {
    final buffer = state.buffers[key];
    if (buffer == null) return;
    buffer.lines.clear();
    _touch();
    await _history.clear(buffer.networkId, buffer.name);
  }

  /// Deletes all saved history on this device.
  Future<void> clearAllHistory() async {
    for (final b in state.buffers.values) {
      b.lines.removeWhere((l) => l.isSaved);
    }
    _touch();
    await _history.clearAll();
  }

  Map<String, List<String>> _loadOpenConversations() {
    final raw = _store.getString(_openConversationsKey);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, Object?>).entries)
          e.key: [for (final n in e.value! as List) '$n'],
      };
    } on Object {
      return {};
    }
  }

  /// Remembers which rooms and private chats are open on [networkId], so
  /// the next launch can reopen them.
  void _saveOpenConversations(String networkId) {
    final all = _loadOpenConversations();
    final names = [
      for (final b in state.buffersFor(networkId))
        if (!b.isStatus) b.name,
    ];
    if (names.isEmpty) {
      all.remove(networkId);
    } else {
      all[networkId] = names;
    }
    unawaited(_store.setString(_openConversationsKey, jsonEncode(all)));
  }

  /// Loads saved lines into a new conversation, above anything already
  /// received.
  void _restoreHistory(ChatBuffer buffer) {
    if (!saveHistory) return;
    buffer.restoring = true;
    buffer.restored = _history.load(buffer.networkId, buffer.name).then((
      saved,
    ) {
      buffer.restoring = false;
      for (final line in buffer.pendingSave) {
        _history.append(buffer.networkId, buffer.name, line);
      }
      buffer.pendingSave.clear();
      if (saved.isEmpty || state.buffers[buffer.key] != buffer) return;
      final restored = [
        for (final l in saved) ChatLine.fromStored(l),
        ChatLine(
          text: 'Saved messages above',
          kind: ChatLineKind.event,
          time: saved.last.time.toLocal(),
        ),
      ];
      buffer.lines.insertAll(0, restored);
      if (buffer.lines.length > maxLinesPerBuffer) {
        buffer.lines.removeRange(0, buffer.lines.length - maxLinesPerBuffer);
      }
      _touch();
    });
  }

  void _saveLine(ChatBuffer buffer, ChatLine line) {
    if (buffer.isStatus || !line.isSaved || !saveHistory) return;
    if (buffer.restoring) {
      buffer.pendingSave.add(line.toStored());
    } else {
      _history.append(buffer.networkId, buffer.name, line.toStored());
    }
  }

  /// Client of the open conversation's network.
  IrcClient? get client => state.activeNetwork?.client;

  /// Host of the open conversation's network; favorites and recents are
  /// keyed by it.
  String? get host => state.activeNetwork?.id;

  /// Connects to a network. Other networks stay connected. Connecting to a
  /// network that is already open replaces its connection but keeps its
  /// conversations.
  Future<void> connect(IrcConnectionConfig requested) async {
    final id = requested.networkKey;
    // Rooms and private chats that were open last time on this network.
    final reopen = state.networks.containsKey(id)
        ? const <String>[]
        : _loadOpenConversations()[id] ?? const <String>[];
    // Add certificates the user trusted earlier for this server, and rejoin
    // rooms that were open.
    final config = requested.copyWith(
      autoJoin: [
        ...requested.autoJoin,
        for (final name in reopen)
          if (_looksLikeChannel(name) &&
              !requested.autoJoin.any(
                (r) => r.toLowerCase() == name.toLowerCase(),
              ))
            name,
      ],
      trustedFingerprints: {
        ...requested.trustedFingerprints,
        ...ref
            .read(certificateTrustStoreProvider)
            .fingerprintsFor(requested.host),
      },
    );
    final client = IrcClient(
      config,
      transportFactory: ref.read(transportFactoryProvider),
    );
    var session = state.networks[id];
    final isNew = session == null;
    if (session != null) {
      await session.subscription?.cancel();
      // Close the old connection in the background; don't wait for it.
      unawaited(session.client.dispose());
      session
        ..config = config
        ..client = client
        ..nick = config.nick
        ..status = IrcConnectionStatus.disconnected
        ..roomsLoading = false
        ..whoisBuffer = null
        ..clearConnectionProblem();
    } else {
      session = NetworkSession(config: config, client: client);
      _sessions.add(session);
      state = state.copyWith(networks: {...state.networks, id: session});
    }
    final status = _ensureBuffer(session, statusBuffer);
    for (final name in reopen) {
      _ensureBuffer(session, name);
    }
    // A new network opens on its server tab; reconnecting stays put.
    if (isNew || state.activeKey == null) {
      state = state.copyWith(activeKey: status.key);
    }
    _addLine(
      session,
      statusBuffer,
      ChatLine(
        text:
            'Connecting to ${config.host}:${config.port}'
            '${config.useTls ? ' (secure)' : ' (NOT encrypted)'}…',
        kind: ChatLineKind.event,
      ),
    );
    final current = session;
    session.subscription = client.events.listen((e) => _onEvent(current, e));
    await client.connect();
  }

  static bool _looksLikeChannel(String name) =>
      name.startsWith('#') || name.startsWith('&');

  NetworkSession? _network(String? id) =>
      id == null ? state.activeNetwork : state.networks[id];

  /// Disconnects a network (the open one by default) but keeps its
  /// conversations so it can be reconnected.
  Future<void> disconnect([String? networkId]) async {
    await _network(networkId)?.client.disconnect();
  }

  /// Reconnects a network that was disconnected.
  Future<void> reconnect([String? networkId]) async {
    final session = _network(networkId);
    if (session == null) return;
    await connect(session.config);
  }

  /// Disconnects a network and closes all of its conversations.
  Future<void> removeNetwork(String networkId) async {
    final session = state.networks[networkId];
    if (session == null) return;
    _sessions.remove(session);
    await session.subscription?.cancel();
    unawaited(session.client.dispose());
    // A bouncer's network comes back with the bouncer; only forget the
    // bouncer (or an ordinary server) itself.
    if (session.config.bouncerNetwork == null) {
      unawaited(
        ref
            .read(savedConnectionRepositoryProvider)
            .removeNetwork(session.config.host),
      );
    }
    final open = _loadOpenConversations()..remove(networkId);
    unawaited(_store.setString(_openConversationsKey, jsonEncode(open)));
    final networks = Map.of(state.networks)..remove(networkId);
    final buffers = Map.of(state.buffers)
      ..removeWhere((_, b) => b.networkId == networkId);
    final activeGone = !buffers.containsKey(state.activeKey);
    state = ChatState(
      networks: networks,
      buffers: buffers,
      activeKey: activeGone
          ? networks.values
                .map((n) => ChatState.bufferKey(n.id, statusBuffer))
                .firstOrNull
          : state.activeKey,
      revision: state.revision + 1,
    );
  }

  /// Trusts the certificate that was just rejected and reconnects.
  Future<void> trustCertificateAndReconnect([String? networkId]) async {
    final session = _network(networkId);
    final cert = session?.untrustedCertificate;
    if (session == null || cert == null) return;
    await ref
        .read(certificateTrustStoreProvider)
        .trust(session.config.host, cert.sha256);
    await connect(session.config);
  }

  /// Reconnects without TLS on port 6667, after the user agreed.
  Future<void> connectWithoutEncryption([String? networkId]) async {
    final session = _network(networkId);
    if (session == null) return;
    await connect(session.config.copyWith(useTls: false, port: 6667));
  }

  /// Hides the connection-problem banner.
  void dismissConnectionProblem([String? networkId]) {
    _network(networkId)?.clearConnectionProblem();
    _touch();
  }

  /// Asks one network (or every connected network) for its room list.
  /// Results land in [NetworkSession.rooms].
  ///
  /// Returns false when nothing is connected yet.
  bool fetchRooms([String? networkId]) {
    final targets = networkId == null
        ? state.connectedNetworks
        : [
            if (state.networks[networkId]?.isConnected ?? false)
              state.networks[networkId]!,
          ];
    if (targets.isEmpty) return false;
    for (final n in targets) {
      if (n.roomsLoading) continue;
      n
        ..roomsLoading = true
        ..roomsError = null;
      n.client.list();
    }
    _touch();
    return true;
  }

  /// Fetches rooms from connected networks that haven't been asked yet.
  void fetchMissingRooms() {
    for (final n in state.connectedNetworks) {
      if (n.roomsFetchedAt == null && !n.roomsLoading && n.roomsError == null) {
        fetchRooms(n.id);
      }
    }
  }

  /// Opens (or switches to) a private conversation with [nick] on the open
  /// conversation's network.
  void openPrivateChat(String nick) {
    final session = state.activeNetwork;
    final name = nick.trim();
    if (session == null || name.isEmpty || name.contains(' ')) return;
    selectBuffer(_ensureBuffer(session, name).key);
  }

  /// Asks the server about [nick]; replies are shown in the open
  /// conversation instead of the server tab.
  void whoisUser(String nick) {
    final session = state.activeNetwork;
    if (session == null) return;
    session.whoisBuffer = state.activeBuffer?.name ?? statusBuffer;
    session.client.whois(nick);
  }

  /// WHOIS reply numerics (RFC 2812 and common extensions).
  static const _whoisReplies = {
    '301',
    '276',
    '307',
    '311',
    '312',
    '313',
    '317',
    '318',
    '319',
    '320',
    '330',
    '338',
    '378',
    '379',
    '671',
  };

  /// Joins a room (from the browser or a favorite) on a network and makes
  /// it the open conversation.
  void joinRoom(String name, {String? networkId}) {
    final session = _network(networkId);
    if (session == null) return;
    if (session.client.channel(name) != null) {
      selectBuffer(ChatState.bufferKey(session.id, name));
      return;
    }
    session.pendingSelect = name.toLowerCase();
    session.client.join(name);
  }

  /// Creates a room (or joins it if it already exists) and, once the
  /// server confirms the user runs it, applies [settings].
  void createRoom(String name, RoomSettings settings, {String? networkId}) {
    final session = _network(networkId);
    var room = name.trim();
    if (session == null || room.isEmpty) return;
    if (!session.client.isChannel(room)) room = '#$room';
    final key = room.toLowerCase();
    session
      ..pendingCreate[key] = settings
      ..pendingSelect = key;
    final password = settings.password?.trim() ?? '';
    session.client.join(room, key: password.isEmpty ? null : password);
  }

  /// Changes a room's settings. Only works for the room's operators.
  void updateRoom(String channel, RoomSettings settings, {String? networkId}) {
    final session = _network(networkId);
    final chan = session?.client.channel(channel);
    if (session == null || chan == null) return;
    final change = modeChange(
      current: chan.modes,
      currentKey: chan.key,
      currentLimit: chan.limit,
      wanted: settings,
    );
    if (change != null) {
      session.client.setModes(chan.name, change.modes, change.args);
    }
  }

  void inviteUser(String nick, String channel, {String? networkId}) {
    final session = _network(networkId);
    if (session == null) return;
    session.client.invite(nick, channel);
    _addLine(
      session,
      channel,
      ChatLine(text: 'Invited $nick to $channel.', kind: ChatLineKind.event),
      countUnread: false,
    );
  }

  void kickUser(String channel, String nick, {String? networkId}) =>
      _network(networkId)?.client.kick(channel, nick);

  /// Bans [nick] and removes them from the room.
  void banUser(String channel, String nick, {String? networkId}) {
    final client = _network(networkId)?.client;
    if (client == null) return;
    client
      ..ban(channel, nick)
      ..kick(channel, nick, reason: 'Banned');
  }

  void makeOperator(String channel, String nick, {String? networkId}) =>
      _network(networkId)?.client.setModes(channel, '+o', [nick]);

  /// Takes operator status away from [nick].
  void removeOperator(String channel, String nick, {String? networkId}) =>
      _network(networkId)?.client.setModes(channel, '-o', [nick]);

  /// Gives or takes [nick]'s voice (+v): in a moderated room only people
  /// with a voice (and operators) can talk.
  void setVoice(
    String channel,
    String nick, {
    required bool voice,
    String? networkId,
  }) =>
      _network(networkId)?.client
          .setModes(channel, voice ? '+v' : '-v', [nick]);

  /// Changes the room's description (its topic).
  void setRoomDescription(String channel, String text, {String? networkId}) =>
      _network(networkId)?.client.setTopic(channel, text.trim());

  /// Loads the room's ban list; the room settings show it when it arrives.
  void requestBans(String channel, {String? networkId}) =>
      _network(networkId)?.client.requestBans(channel);

  /// Lifts a ban.
  void unban(String channel, String mask, {String? networkId}) =>
      _network(networkId)?.client.setModes(channel, '-b', [mask]);

  /// Joins the room from an invitation and forgets the invitation.
  void acceptInvite(String networkId, RoomInvite invite) {
    dismissInvite(networkId, invite);
    joinRoom(invite.channel, networkId: networkId);
  }

  void dismissInvite(String networkId, RoomInvite invite) {
    state.networks[networkId]?.invites.remove(invite);
    _touch();
  }

  /// Registers the current nickname with NickServ and remembers the
  /// password for automatic login (SASL) next time. The reply opens in a
  /// NickServ chat.
  Future<void> registerNick(
    String password,
    String email, {
    String? networkId,
  }) async {
    final session = _network(networkId);
    if (session == null || !session.services.canRegisterNick) return;
    final msg = session.services.registerNick(password, email);
    session.client.sendRaw('PRIVMSG ${msg.target} :${msg.text}');
    await ref
        .read(savedConnectionRepositoryProvider)
        .rememberAccount(session.config.host, session.nick, password);
    _openServiceChat(
      session,
      'NickServ',
      'Asked NickServ to register ${session.nick}. Check $email for a '
          'confirmation message if the network sends one.',
    );
  }

  /// Logs in to the current nickname's account now (without reconnecting).
  void identifyNick(String password, {String? networkId}) {
    final session = _network(networkId);
    if (session == null || !session.services.canRegisterNick) return;
    final msg = session.services.identify(password);
    session.client.sendRaw('PRIVMSG ${msg.target} :${msg.text}');
    _openServiceChat(session, 'NickServ', 'Logging in to ${session.nick}…');
  }

  /// Asks ChanServ to register [channel] so it is kept permanently. The
  /// reply opens in a ChanServ chat.
  void registerRoom(String channel, {String? password, String? networkId}) {
    final session = _network(networkId);
    if (session == null || !session.services.canRegisterRoom) return;
    final msg = session.services.registerRoom(channel, password: password);
    session.client.sendRaw('PRIVMSG ${msg.target} :${msg.text}');
    _addLine(
      session,
      channel,
      ChatLine(
        text:
            'Asked ChanServ to keep $channel. Its answer is in the '
            'ChanServ chat.',
        kind: ChatLineKind.event,
      ),
      countUnread: false,
    );
    _openServiceChat(session, 'ChanServ', 'Registering $channel…');
  }

  void _openServiceChat(NetworkSession session, String name, String note) {
    final buffer = _ensureBuffer(session, name);
    _addLine(
      session,
      name,
      ChatLine(text: note, kind: ChatLineKind.event),
      countUnread: false,
    );
    selectBuffer(buffer.key);
  }

  /// Opens the conversation with [key] (see [ChatBuffer.key]).
  void selectBuffer(String key) {
    final buffer = state.buffers[key];
    if (buffer == null) return;
    // The divider only marks what was new on this visit.
    final previous = state.activeBuffer;
    if (previous != null && previous != buffer) previous.unreadMarker = null;
    buffer
      ..unreadMarker = buffer.firstUnread ?? buffer.unreadMarker
      ..firstUnread = null
      ..unread = 0
      ..mentioned = false;
    state = state.copyWith(activeKey: key);
    _syncRead(buffer);
  }

  /// Closes a conversation, leaving the channel if needed.
  void closeBuffer(String key) {
    final buffer = state.buffers[key];
    if (buffer == null || buffer.isStatus) return;
    final session = state.networks[buffer.networkId];
    if (session != null &&
        session.isConnected &&
        session.client.isChannel(buffer.name)) {
      session.client.part(buffer.name);
    }
    final buffers = Map.of(state.buffers)..remove(key);
    state = ChatState(
      networks: state.networks,
      buffers: buffers,
      activeKey: state.activeKey == key
          ? ChatState.bufferKey(buffer.networkId, statusBuffer)
          : state.activeKey,
      revision: state.revision + 1,
    );
    _saveOpenConversations(buffer.networkId);
  }

  /// Changes the user's nickname on one network (the open one by default)
  /// or on every open network, and remembers it for next time. Networks
  /// that aren't connected use it when they reconnect.
  ///
  /// Returns an error message, or null when the change was sent.
  String? changeNick(
    String nick, {
    String? networkId,
    bool everywhere = false,
  }) {
    final name = nick.trim();
    if (!isValidNick(name)) {
      return 'Use letters, numbers and _-[]{}|^ only, starting with a letter.';
    }
    final targets = everywhere
        ? state.networks.values.toList()
        : [?_network(networkId)];
    if (targets.isEmpty) return 'Connect to a network first.';
    for (final session in targets) {
      session.config = session.config.copyWith(nick: name);
      if (session.status == IrcConnectionStatus.connected) {
        session.client.changeNick(name);
      } else {
        session.nick = name;
      }
    }
    _touch();
    unawaited(ref.read(savedConnectionRepositoryProvider).rememberNick(name));
    return null;
  }

  /// Starts a reply to [line] in the open conversation.
  void startReply(ChatLine line) {
    final buffer = state.activeBuffer;
    if (buffer == null || buffer.isStatus || line.sender == null) return;
    buffer.replyTo = line;
    _touch();
  }

  void cancelReply() {
    state.activeBuffer?.replyTo = null;
    _touch();
  }

  /// [text] addressed to [nick] the usual IRC way (`nick: text`), unless it
  /// already starts with their name or is a command.
  static String addressTo(String nick, String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('/') && !trimmed.startsWith('//')) return text;
    if (trimmed.toLowerCase().startsWith(nick.toLowerCase())) return text;
    return '$nick: $trimmed';
  }

  /// Runs what the user typed in the open conversation.
  void submit(String input) {
    final reply = state.activeBuffer?.replyTo;
    final text = reply != null && (state.activeBuffer?.isChannel ?? false)
        ? addressTo(reply.sender!, input)
        : input;
    state.activeBuffer?.replyTo = null;
    final session = state.activeNetwork;
    final buffer = state.activeBuffer;
    if (session == null || buffer == null) return;
    // Sending a message ends "typing" for everyone else.
    buffer.typingSentAt = null;
    if (session.status == IrcConnectionStatus.disconnected) {
      _addLine(
        session,
        buffer.name,
        ChatLine(
          text: 'Not connected to ${session.label}.',
          kind: ChatLineKind.error,
        ),
      );
      return;
    }
    final result = runInput(
      session.client,
      text,
      target: buffer.isStatus ? null : buffer.name,
    );
    switch (result) {
      case InputSent():
        break;
      case InputOpenQuery(:final nick):
        selectBuffer(_ensureBuffer(session, nick).key);
      case InputError(:final message):
        _addLine(
          session,
          buffer.name,
          ChatLine(text: message, kind: ChatLineKind.error),
        );
    }
  }

  void _touch() => state = state.copyWith();

  /// Rings for a call link someone sent us in a private chat. Old messages
  /// (history replayed by the server) don't ring.
  void _maybeRing(NetworkSession session, MessageEvent e) {
    if (e.isOwn || e.isNotice || e.isAction) return;
    if (session.client.isChannel(e.target)) return;
    final link = CallLink.find(e.text);
    if (link == null) return;
    if (DateTime.now().difference(e.time) > const Duration(minutes: 2)) return;
    ref
        .read(callControllerProvider.notifier)
        .ring(link, from: e.sender, networkId: session.id);
  }

  ChatBuffer _ensureBuffer(NetworkSession session, String name) {
    final key = ChatState.bufferKey(session.id, name);
    final existing = state.buffers[key];
    if (existing != null) return existing;
    final buffer = ChatBuffer(session.id, name);
    state = state.copyWith(buffers: {...state.buffers, key: buffer});
    if (!buffer.isStatus) {
      _restoreHistory(buffer);
      _saveOpenConversations(session.id);
    }
    return buffer;
  }

  void _addLine(
    NetworkSession session,
    String bufferName,
    ChatLine line, {
    bool countUnread = true,
  }) {
    final buffer = _ensureBuffer(session, bufferName);
    buffer.lines.add(line);
    _saveLine(buffer, line);
    if (buffer.lines.length > maxLinesPerBuffer) {
      buffer.lines.removeRange(0, buffer.lines.length - maxLinesPerBuffer);
    }
    if (countUnread) _countUnread(session, buffer, line);
    if (line.isSaved && !buffer.isStatus) _markSeen(session);
    if (line.isSaved && state.activeKey == buffer.key) _syncRead(buffer);
    _touch();
  }

  // ---------------------------------------------------------------------
  // Typing notifications and read markers (IRCv3)
  // ---------------------------------------------------------------------

  /// What's in the open conversation's message box changed: tell others
  /// we're typing (at most every 3 seconds), or that we stopped.
  void noteTyping(String text) {
    final buffer = state.activeBuffer;
    final session = state.activeNetwork;
    if (buffer == null || session == null || buffer.isStatus) return;
    if (!ref.read(safetyProvider).sendTyping || !session.isConnected) return;
    final now = clock.now();
    final typing = text.trim().isNotEmpty && !text.startsWith('/');
    if (!typing) {
      if (buffer.typingSentAt != null) {
        buffer.typingSentAt = null;
        session.client.sendTyping(buffer.name, 'done');
      }
      return;
    }
    final last = buffer.typingSentAt;
    if (last == null || now.difference(last) >= const Duration(seconds: 3)) {
      buffer.typingSentAt = now;
      session.client.sendTyping(buffer.name, 'active');
    }
  }

  void _onTyping(NetworkSession session, TypingEvent e) {
    if (isBlocked(e.nick)) return;
    final buffer = _bufferNamed(session, e.target);
    if (buffer == null) return;
    final key = session.client.isupport.fold(e.nick);
    final wait = switch (e.state) {
      'active' => const Duration(seconds: 6),
      'paused' => const Duration(seconds: 30),
      _ => null,
    };
    if (wait == null) {
      buffer.typing.remove(key);
    } else {
      buffer.typing[key] = (nick: e.nick, until: clock.now().add(wait));
    }
    _scheduleTypingRefresh(buffer);
    _touch();
  }

  void _scheduleTypingRefresh(ChatBuffer buffer) {
    buffer.typingTimer?.cancel();
    final now = clock.now();
    buffer.typing.removeWhere((_, t) => !t.until.isAfter(now));
    if (buffer.typing.isEmpty) return;
    final next = buffer.typing.values
        .map((t) => t.until)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    _timedBuffers.add(buffer);
    buffer.typingTimer = Timer(next.difference(now), () {
      if (!ref.mounted) return;
      _scheduleTypingRefresh(buffer);
      _touch();
    });
  }

  /// Tells the server the open conversation is read up to its newest
  /// message, shortly after, if that's newer than what it knows.
  void _syncRead(ChatBuffer buffer) {
    if (buffer.isStatus || !_appVisible) return;
    buffer.readTimer?.cancel();
    _timedBuffers.add(buffer);
    buffer.readTimer = Timer(const Duration(milliseconds: 800), () {
      if (!ref.mounted) return;
      final session = state.networks[buffer.networkId];
      final newest = buffer.newestMessage?.time;
      if (session == null || !session.isConnected || newest == null) return;
      final known = buffer.readUntil;
      if (known != null && !newest.isAfter(known)) return;
      buffer.readUntil = newest;
      session.client.markRead(buffer.name, newest);
    });
  }

  /// Whether the user can see the app (not in the background).
  static bool get _appVisible {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  /// The server says [buffer] was read up to [until] (maybe on another
  /// device): only what came after still counts as unread.
  void _onReadMarker(ChatBuffer buffer, DateTime until) {
    final known = buffer.readUntil;
    if (known != null && !until.isAfter(known)) return;
    buffer.readUntil = until;
    if (state.activeKey == buffer.key) return;
    final session = state.networks[buffer.networkId];
    final unread = [
      for (final l in buffer.lines)
        if (l.isSaved && l.kind != ChatLineKind.own && l.time.isAfter(until)) l,
    ];
    buffer
      ..unread = unread.length
      ..firstUnread = unread.isEmpty ? null : unread.first
      ..mentioned = unread.any(
        (l) =>
            l.kind == ChatLineKind.message &&
            session != null &&
            session.nick.isNotEmpty &&
            mentions(l.text, session.nick),
      );
    _touch();
  }

  void _countUnread(NetworkSession session, ChatBuffer buffer, ChatLine line) {
    if (state.activeKey == buffer.key) return;
    if (buffer.unread == 0) buffer.firstUnread = line;
    buffer.unread++;
    if (session.nick.isNotEmpty &&
        line.kind == ChatLineKind.message &&
        mentions(line.text, session.nick)) {
      buffer.mentioned = true;
    }
  }

  // ---------------------------------------------------------------------
  // History from the server (IRCv3 CHATHISTORY: Ergo, soju and others)
  // ---------------------------------------------------------------------

  DateTime? _seenAt(String networkId) {
    try {
      final all = jsonDecode(
        _store.getString(_historySeenKey) ?? '{}',
      ) as Map<String, Object?>;
      final ms = all[networkId];
      return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } on Object {
      return null;
    }
  }

  /// Notes that this network's messages were seen up to now (at most one
  /// write a minute).
  void _markSeen(NetworkSession session, {bool force = false}) {
    final now = DateTime.now();
    final last = session.seenSavedAt;
    if (!force && last != null && now.difference(last).inSeconds < 60) {
      return;
    }
    session.seenSavedAt = now;
    Map<String, Object?> all;
    try {
      all = jsonDecode(
        _store.getString(_historySeenKey) ?? '{}',
      ) as Map<String, Object?>;
    } on Object {
      all = {};
    }
    all[session.id] = now.millisecondsSinceEpoch;
    unawaited(_store.setString(_historySeenKey, jsonEncode(all)));
  }

  /// After logging in: asks which private chats had messages since the app
  /// last saw this network, and what open private chats missed.
  void _catchUp(NetworkSession session) {
    final client = session.client;
    if (!client.supportsHistory) return;
    final since =
        _seenAt(session.id) ?? DateTime.now().subtract(const Duration(days: 1));
    session.historySince = since;
    _markSeen(session, force: true);
    client.requestHistoryTargets(
      since,
      DateTime.now().add(const Duration(minutes: 1)),
    );
    for (final b in state.buffers.values.toList()) {
      if (b.networkId == session.id && !b.isStatus && !b.isChannel) {
        unawaited(_fetchMissed(session, b));
      }
    }
  }

  /// Asks for what [buffer] missed: messages after its newest one, or the
  /// latest ones when it has none.
  Future<void> _fetchMissed(NetworkSession session, ChatBuffer buffer) async {
    await buffer.restored;
    if (buffer.historyWant != null || !session.client.supportsHistory) return;
    buffer
      ..historyWant = HistoryWant.missed
      ..historyAdded = 0;
    final newest = buffer.newestMessage;
    session.client.requestHistory(
      buffer.name,
      after: newest?.time,
      limit: newest == null ? 50 : null,
    );
  }

  /// Whether older messages can be fetched for [buffer] from the server.
  bool canLoadOlder(ChatBuffer buffer) =>
      !buffer.isStatus &&
      !buffer.historyExhausted &&
      (state.networks[buffer.networkId]?.client.supportsHistory ?? false) &&
      state.networks[buffer.networkId]?.status == IrcConnectionStatus.connected;

  /// Fetches up to 50 messages from before the oldest one shown.
  void loadOlder(String key) {
    final buffer = state.buffers[key];
    if (buffer == null || buffer.historyWant != null || !canLoadOlder(buffer)) {
      return;
    }
    buffer
      ..historyWant = HistoryWant.older
      ..historyAdded = 0;
    state.networks[buffer.networkId]!.client.requestHistoryBefore(
      buffer.name,
      buffer.oldestMessage?.time ?? DateTime.now(),
      limit: 50,
    );
    _touch();
  }

  /// A message from history: skipped if it's already shown, otherwise put
  /// in time order. Ones newer than everything shown were missed, so they
  /// are saved and count as unread.
  void _addHistoryLine(NetworkSession session, String name, ChatLine line) {
    final buffer = _ensureBuffer(session, name);
    if (buffer.lines.any(line.sameMessage)) return;
    final newest = buffer.newestMessage;
    var i = buffer.lines.length;
    while (i > 0 && buffer.lines[i - 1].time.isAfter(line.time)) {
      i--;
    }
    buffer.lines.insert(i, line);
    buffer.historyAdded++;
    if (newest == null || line.time.isAfter(newest.time)) {
      _saveLine(buffer, line);
      final read = buffer.readUntil;
      // Already read on another device: not unread here either.
      if (read == null || line.time.isAfter(read)) {
        _countUnread(session, buffer, line);
      }
      if (state.activeKey == buffer.key) _syncRead(buffer);
    }
    _touch();
  }

  ChatBuffer? _bufferNamed(NetworkSession session, String? name) {
    if (name == null) return null;
    final fold = session.client.isupport.fold(name);
    for (final b in state.buffers.values) {
      if (b.networkId == session.id &&
          session.client.isupport.fold(b.name) == fold) {
        return b;
      }
    }
    return null;
  }

  void _onEvent(NetworkSession session, IrcEvent e) {
    // Ignore late events from a connection that was replaced.
    if (state.networks[session.id] != session) return;
    void add(String buffer, ChatLine line, {bool countUnread = true}) =>
        _addLine(session, buffer, line, countUnread: countUnread);

    switch (e) {
      case RawLineEvent():
        return;
      case StatusChangedEvent(:final status, :final reason):
        session.status = status;
        if (status != IrcConnectionStatus.connected) {
          session.roomsLoading = false;
        }
        final label = switch (status) {
          IrcConnectionStatus.connecting => 'Connecting…',
          IrcConnectionStatus.registering => 'Logging in…',
          IrcConnectionStatus.connected => 'Connected.',
          IrcConnectionStatus.reconnecting =>
            'Connection lost${reason == null ? '' : ' ($reason)'}. '
                'Reconnecting…',
          IrcConnectionStatus.disconnected =>
            'Disconnected${reason == null ? '' : ' ($reason)'}.',
        };
        add(
          statusBuffer,
          ChatLine(text: label, kind: ChatLineKind.event),
          countUnread: false,
        );
      case CertificateRejectedEvent(:final host, :final certificate):
        final why = certificate.isExpired
            ? 'it has expired'
            : certificate.isSelfSigned
            ? "it's self-signed"
            : "it isn't issued for $host by a trusted authority";
        session.untrustedCertificate = certificate;
        add(
          statusBuffer,
          ChatLine(
            text:
                "$host's security certificate can't be verified because "
                '$why.',
            kind: ChatLineKind.error,
          ),
        );
      case RegisteredEvent(:final nick, :final network):
        session
          ..nick = nick
          ..name = network
          ..clearConnectionProblem();
        add(
          statusBuffer,
          ChatLine(
            text:
                'Welcome, $nick! Tap "Browse rooms" (the compass) to find '
                'a room, or type /join #room.',
            kind: ChatLineKind.event,
          ),
          countUnread: false,
        );
        _catchUp(session);
      case ServerInfoEvent(:final network):
        if (network != session.name) {
          session.name = network;
          _touch();
        }
      case SaslEvent(:final outcome):
        session.loggedIn = outcome == SaslOutcome.success;
        add(
          statusBuffer,
          ChatLine(
            text: 'Account login: ${outcome.name}',
            kind: ChatLineKind.event,
          ),
        );
      case MessageEvent(:final sender, :final isOwn)
          when !isOwn && isBlocked(sender):
        return;
      case MessageEvent(:final history) when history:
        _addHistoryLine(
          session,
          e.target,
          ChatLine(
            sender: e.sender,
            text: e.text,
            time: e.time,
            msgid: e.msgid,
            kind: e.isOwn
                ? ChatLineKind.own
                : e.isAction
                ? ChatLineKind.action
                : e.isNotice
                ? ChatLineKind.notice
                : ChatLineKind.message,
          ),
        );
      case HistoryBatchEvent(:final target, :final failed):
        final buffers = failed
            ? [
                for (final b in state.buffers.values)
                  if (b.networkId == session.id && b.historyWant != null) b,
              ]
            : [?_bufferNamed(session, target)];
        for (final b in buffers) {
          if (b.historyWant == HistoryWant.older && b.historyAdded == 0) {
            b.historyExhausted = true;
          }
          b.historyWant = null;
        }
        _touch();
      case TypingEvent():
        _onTyping(session, e);
      case DccOfferEvent():
        _onDccOffer(session, e);
      case ReadMarkerEvent(:final target, :final readUntil):
        final buffer = _bufferNamed(session, target);
        if (buffer != null && readUntil != null) {
          _onReadMarker(buffer, readUntil);
        }
      case BouncerNetworksEvent(:final networks):
        // Open every network on the bouncer that isn't open yet, each on
        // its own connection bound to it.
        if (!session.isBouncer) return;
        for (final net in networks.values) {
          final config = session.config.copyWith(
            bouncerNetwork: net.id,
            autoJoin: const [],
          );
          if (!state.networks.containsKey(config.networkKey)) {
            unawaited(connect(config));
          }
        }
        _touch();
      case HistoryTargetsEvent(:final targets):
        final since = session.historySince;
        for (final t in targets) {
          if (session.client.isChannel(t.name) ||
              t.name == '*' ||
              session.client.isMe(t.name) ||
              isBlocked(t.name) ||
              (since != null && !t.latest.isAfter(since))) {
            continue;
          }
          unawaited(_fetchMissed(session, _ensureBuffer(session, t.name)));
        }
      case MessageEvent():
        _maybeRing(session, e);
        final room = _bufferNamed(session, e.target);
        if (room != null &&
            room.typing.remove(session.client.isupport.fold(e.sender)) !=
                null) {
          _scheduleTypingRefresh(room);
        }
        add(
          e.target,
          ChatLine(
            sender: e.sender,
            // Raw, with mIRC codes; the chat view draws them.
            text: e.text,
            time: e.time,
            msgid: e.msgid,
            kind: e.isOwn
                ? ChatLineKind.own
                : e.isAction
                ? ChatLineKind.action
                : e.isNotice
                ? ChatLineKind.notice
                : ChatLineKind.message,
          ),
        );
      case JoinEvent(:final channel, :final nick, :final isSelf):
        add(
          channel,
          ChatLine(
            text: isSelf ? 'You joined $channel' : '$nick joined',
            kind: ChatLineKind.event,
            time: e.time,
            presence: isSelf ? null : PresenceChange.joined,
            subject: nick,
          ),
          countUnread: false,
        );
        if (isSelf) {
          // Open the room if the user asked for it, or if they're looking
          // at this network. Don't jump away from another network's chat.
          final asked = session.pendingSelect == channel.toLowerCase();
          if (asked) session.pendingSelect = null;
          if (asked || state.activeBuffer?.networkId == session.id) {
            selectBuffer(ChatState.bufferKey(session.id, channel));
          }
          ref.read(roomPrefsProvider.notifier).addRecent(session.id, channel);
          // What the room said while we were away, if the server keeps it.
          final room = _bufferNamed(session, channel);
          if (room != null) unawaited(_fetchMissed(session, room));
        }
      case PartEvent(:final channel, :final nick, :final isSelf):
        final what = e.kickedBy != null
            ? '$nick was kicked by ${e.kickedBy}'
            : '$nick left';
        final reason = e.reason == null || e.reason!.isEmpty
            ? ''
            : ' (${e.reason})';
        add(
          channel,
          ChatLine(
            text: '${isSelf && e.kickedBy == null ? 'You left' : what}$reason',
            kind: ChatLineKind.event,
            time: e.time,
            presence: isSelf || e.kickedBy != null ? null : PresenceChange.left,
            subject: nick,
          ),
          countUnread: false,
        );
      case QuitEvent(:final nick, :final channels, :final reason):
        for (final c in channels) {
          add(
            c,
            ChatLine(
              text: '$nick quit${reason == null ? '' : ' ($reason)'}',
              kind: ChatLineKind.event,
              time: e.time,
              presence: PresenceChange.left,
              subject: nick,
            ),
            countUnread: false,
          );
        }
      case NickChangeEvent(:final oldNick, :final newNick, :final isSelf):
        if (isSelf) {
          session.nick = newNick;
          _touch();
        }
        for (final c in e.channels) {
          add(
            c,
            ChatLine(
              text: '$oldNick is now known as $newNick',
              kind: ChatLineKind.event,
            ),
            countUnread: false,
          );
        }
      case TopicEvent(:final channel, :final topic, :final setBy):
        add(
          channel,
          ChatLine(
            text: setBy == null
                ? 'Topic: ${stripFormatting(topic)}'
                : '$setBy set the topic: ${stripFormatting(topic)}',
            kind: ChatLineKind.event,
          ),
          countUnread: false,
        );
      case MembersChangedEvent():
        _touch();
      case ChannelModeEvent(:final channel, :final change, :final setBy):
        _onChannelModes(session, channel, change, setBy);
      case InviteEvent(:final from) when isBlocked(from):
        return;
      case InviteEvent(:final from, :final channel):
        session.invites
          ..removeWhere((i) => i.channel.toLowerCase() == channel.toLowerCase())
          ..add(RoomInvite(from: from, channel: channel));
        add(
          statusBuffer,
          ChatLine(
            text: '$from invited you to $channel.',
            kind: ChatLineKind.event,
          ),
          countUnread: false,
        );
      case ChannelListEvent(:final entries):
        session
          ..rooms = entries
          ..roomsLoading = false
          ..roomsFetchedAt = DateTime.now();
        add(
          statusBuffer,
          ChatLine(
            text:
                '${entries.length} rooms found. Open "Browse rooms" to '
                'search them.',
            kind: ChatLineKind.event,
          ),
          countUnread: false,
        );
      case ServerErrorEvent(:final text, :final target, :final code):
        if (code == 'CONNECT' && session.config.useTls) {
          session.secureConnectFailed = true;
        }
        // 416: list too large / not allowed; LIST errors end the request.
        if (session.roomsLoading && (code == '416' || target == 'LIST')) {
          session
            ..roomsLoading = false
            ..roomsError = text;
        }
        final active = state.activeBuffer;
        final buffer =
            target != null &&
                state.buffers.containsKey(
                  ChatState.bufferKey(session.id, target),
                )
            ? target
            : active != null && active.networkId == session.id
            ? active.name
            : statusBuffer;
        add(
          buffer,
          ChatLine(
            text: switch (code) {
              'CONNECT' || 'ERROR' => text,
              // Nickname in use / not allowed / temporarily unavailable.
              '432' || '433' || '436' || '437' =>
                "Couldn't change your nickname: $text. You're still "
                    '${session.nick}. Choose another with Change nickname in '
                    'the menu.',
              _ => '$text ($code)',
            },
            kind: ChatLineKind.error,
          ),
        );
      case ServerNoticeEvent(:final message, :final text):
        // 263 RPL_TRYAGAIN: the server refused LIST for now.
        if (session.roomsLoading && message.command == '263') {
          session
            ..roomsLoading = false
            ..roomsError = text;
        }
        final whoisTarget = session.whoisBuffer;
        if (whoisTarget != null && _whoisReplies.contains(message.command)) {
          if (message.command == '318') {
            session.whoisBuffer = null; // End of WHOIS.
          } else {
            add(
              whoisTarget,
              ChatLine(text: text, kind: ChatLineKind.notice),
              countUnread: false,
            );
          }
          return;
        }
        add(
          statusBuffer,
          ChatLine(text: text, kind: ChatLineKind.notice),
          countUnread: false,
        );
    }
  }

  void _onChannelModes(
    NetworkSession session,
    String channel,
    String change,
    String? setBy,
  ) {
    final words = describeModeChange(change);
    if (change.trim().isNotEmpty && change.trim() != '+') {
      _addLine(
        session,
        channel,
        ChatLine(
          text: setBy == null
              ? 'Room settings: $words'
              : '$setBy changed the room: $words',
          kind: ChatLineKind.event,
        ),
        countUnread: false,
      );
    }
    // The reply to our MODE query after joining tells us whether we got
    // to create (and run) a room the user asked for.
    final settings = session.pendingCreate.remove(channel.toLowerCase());
    if (settings == null || setBy != null) return;
    final chan = session.client.channel(channel);
    if (chan == null) return;
    if (!session.client.isOperator(channel)) {
      _addLine(
        session,
        channel,
        ChatLine(
          text:
              '$channel already exists and someone else runs it, so its '
              "settings weren't changed.",
          kind: ChatLineKind.error,
        ),
      );
      return;
    }
    final apply = modeChange(
      current: chan.modes,
      currentKey: chan.key,
      wanted: RoomSettings(
        inviteOnly: settings.inviteOnly,
        secret: settings.secret,
        topicLocked: settings.topicLocked ?? true,
        password: settings.password,
      ),
    );
    if (apply != null) {
      session.client.setModes(chan.name, apply.modes, apply.args);
    }
    _addLine(
      session,
      channel,
      ChatLine(
        text:
            'You created $channel and run it. Open Room settings in the menu '
            'to change who can join or to keep the room permanently.',
        kind: ChatLineKind.event,
      ),
      countUnread: false,
    );
  }
}
