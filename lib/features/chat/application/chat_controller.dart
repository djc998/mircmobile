/// App-side chat state built from [IrcClient] events.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/input_commands.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/connection/data/certificate_trust.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';

/// Name of the server/status buffer.
const String statusBuffer = '*status';

/// How many lines each conversation keeps in memory.
const int maxLinesPerBuffer = 1000;

enum ChatLineKind { message, action, notice, event, error, own }

class ChatLine {
  ChatLine({
    required this.text,
    required this.kind,
    this.sender,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  final DateTime time;
  final String? sender;
  final String text;
  final ChatLineKind kind;
}

/// One conversation: the status window, a channel or a private chat.
class ChatBuffer {
  ChatBuffer(this.name);

  final String name;
  final List<ChatLine> lines = [];
  int unread = 0;
  bool mentioned = false;

  bool get isStatus => name == statusBuffer;
  bool get isChannel => name.startsWith('#') || name.startsWith('&');
}

class ChatState {
  const ChatState({
    this.status = IrcConnectionStatus.disconnected,
    this.network = '',
    this.nick = '',
    this.buffers = const {},
    this.active = statusBuffer,
    this.revision = 0,
    this.rooms = const [],
    this.roomsLoading = false,
    this.roomsFetchedAt,
    this.roomsError,
    this.untrustedCertificate,
    this.secureConnectFailed = false,
  });

  final IrcConnectionStatus status;
  final String network;
  final String nick;

  /// Buffers keyed by lower-cased name, in insertion order.
  final Map<String, ChatBuffer> buffers;
  final String active;

  /// Bumped on every change so listeners rebuild.
  final int revision;

  /// Rooms from the last LIST on this network (the room browser's data).
  final List<ChannelListEntry> rooms;
  final bool roomsLoading;

  /// When [rooms] was fetched, or null if never.
  final DateTime? roomsFetchedAt;

  /// Why the last LIST failed, if it did.
  final String? roomsError;

  /// Set when the server's certificate failed verification; the chat screen
  /// asks whether to trust it.
  final CertificateInfo? untrustedCertificate;

  /// Set when a secure (TLS) connection couldn't be opened at all, so the
  /// chat screen can offer an unencrypted connection instead.
  final bool secureConnectFailed;

  bool get hasConnectionProblem =>
      untrustedCertificate != null || secureConnectFailed;

  ChatBuffer? get activeBuffer => buffers[active.toLowerCase()];

  ChatState copyWith({
    IrcConnectionStatus? status,
    String? network,
    String? nick,
    Map<String, ChatBuffer>? buffers,
    String? active,
    List<ChannelListEntry>? rooms,
    bool? roomsLoading,
    DateTime? roomsFetchedAt,
    String? roomsError,
    bool clearRoomsError = false,
    CertificateInfo? untrustedCertificate,
    bool? secureConnectFailed,
    bool clearConnectionProblem = false,
  }) => ChatState(
    status: status ?? this.status,
    network: network ?? this.network,
    nick: nick ?? this.nick,
    buffers: buffers ?? this.buffers,
    active: active ?? this.active,
    revision: revision + 1,
    rooms: rooms ?? this.rooms,
    roomsLoading: roomsLoading ?? this.roomsLoading,
    roomsFetchedAt: roomsFetchedAt ?? this.roomsFetchedAt,
    roomsError: clearRoomsError ? null : (roomsError ?? this.roomsError),
    untrustedCertificate: clearConnectionProblem
        ? null
        : (untrustedCertificate ?? this.untrustedCertificate),
    secureConnectFailed:
        !clearConnectionProblem &&
        (secureConnectFailed ?? this.secureConnectFailed),
  );
}

/// Lets tests swap the network layer.
final transportFactoryProvider = Provider<IrcTransportFactory>(
  (ref) => defaultTransportFactory,
);

final chatControllerProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

/// Owns the single active [IrcClient] and turns its events into buffers.
class ChatController extends Notifier<ChatState> {
  IrcClient? _client;
  IrcConnectionConfig? _config;
  StreamSubscription<IrcEvent>? _sub;

  IrcClient? get client => _client;

  /// Host of the current network; favorites and recents are keyed by it.
  String? get host => _client?.config.host;

  @override
  ChatState build() {
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      unawaited(_client?.dispose());
    });
    return ChatState(buffers: {statusBuffer: ChatBuffer(statusBuffer)});
  }

  /// Connects to a network, replacing any previous connection.
  Future<void> connect(IrcConnectionConfig requested) async {
    await _sub?.cancel();
    // Close the old connection in the background; don't wait for it.
    final old = _client;
    _client = null;
    if (old != null) unawaited(old.dispose());
    // Add certificates the user trusted earlier for this server.
    final config = requested.copyWith(
      trustedFingerprints: {
        ...requested.trustedFingerprints,
        ...ref
            .read(certificateTrustStoreProvider)
            .fingerprintsFor(requested.host),
      },
    );
    _config = config;
    final client = IrcClient(
      config,
      transportFactory: ref.read(transportFactoryProvider),
    );
    _client = client;
    state = ChatState(
      network: config.host,
      nick: config.nick,
      buffers: {statusBuffer: ChatBuffer(statusBuffer)},
    );
    _addLine(
      statusBuffer,
      ChatLine(
        text:
            'Connecting to ${config.host}:${config.port}'
            '${config.useTls ? ' (secure)' : ' (NOT encrypted)'}…',
        kind: ChatLineKind.event,
      ),
    );
    _sub = client.events.listen(_onEvent);
    await client.connect();
  }

  Future<void> disconnect() async {
    await _client?.disconnect();
  }

  /// Trusts the certificate that was just rejected and reconnects.
  Future<void> trustCertificateAndReconnect() async {
    final cert = state.untrustedCertificate;
    final config = _config;
    if (cert == null || config == null) return;
    await ref
        .read(certificateTrustStoreProvider)
        .trust(config.host, cert.sha256);
    await connect(config);
  }

  /// Reconnects without TLS on port 6667, after the user agreed.
  Future<void> connectWithoutEncryption() async {
    final config = _config;
    if (config == null) return;
    await connect(config.copyWith(useTls: false, port: 6667));
  }

  /// Hides the connection-problem banner.
  void dismissConnectionProblem() {
    state = state.copyWith(clearConnectionProblem: true);
  }

  /// Asks the server for its room list. Results land in [ChatState.rooms].
  ///
  /// Returns false when not connected yet.
  bool fetchRooms() {
    final client = _client;
    if (client == null || state.status != IrcConnectionStatus.connected) {
      return false;
    }
    if (state.roomsLoading) return true;
    state = state.copyWith(roomsLoading: true, clearRoomsError: true);
    client.list();
    return true;
  }

  /// Joins a room from the browser and makes it the open conversation.
  void joinRoom(String name) {
    final client = _client;
    if (client == null) return;
    if (client.channel(name) != null) {
      selectBuffer(name);
      return;
    }
    client.join(name);
  }

  void selectBuffer(String name) {
    final buffer = state.buffers[name.toLowerCase()];
    if (buffer == null) return;
    buffer
      ..unread = 0
      ..mentioned = false;
    state = state.copyWith(active: buffer.name);
  }

  /// Closes a conversation, leaving the channel if needed.
  void closeBuffer(String name) {
    if (name == statusBuffer) return;
    final client = _client;
    if (client != null && client.isChannel(name)) client.part(name);
    final buffers = Map.of(state.buffers)..remove(name.toLowerCase());
    state = state.copyWith(
      buffers: buffers,
      active: state.active.toLowerCase() == name.toLowerCase()
          ? statusBuffer
          : state.active,
    );
  }

  /// Runs what the user typed in the active conversation.
  void submit(String text) {
    final client = _client;
    final active = state.active;
    if (client == null) {
      _addLine(
        active,
        ChatLine(text: 'Not connected.', kind: ChatLineKind.error),
      );
      return;
    }
    final result = runInput(
      client,
      text,
      target: active == statusBuffer ? null : active,
    );
    switch (result) {
      case InputSent():
        break;
      case InputOpenQuery(:final nick):
        _ensureBuffer(nick);
        selectBuffer(nick);
      case InputError(:final message):
        _addLine(active, ChatLine(text: message, kind: ChatLineKind.error));
    }
  }

  ChatBuffer _ensureBuffer(String name) {
    final key = name.toLowerCase();
    final existing = state.buffers[key];
    if (existing != null) return existing;
    final buffer = ChatBuffer(name);
    state = state.copyWith(buffers: {...state.buffers, key: buffer});
    return buffer;
  }

  void _addLine(String bufferName, ChatLine line, {bool countUnread = true}) {
    final buffer = _ensureBuffer(bufferName);
    buffer.lines.add(line);
    if (buffer.lines.length > maxLinesPerBuffer) {
      buffer.lines.removeRange(0, buffer.lines.length - maxLinesPerBuffer);
    }
    final isActive = state.active.toLowerCase() == bufferName.toLowerCase();
    if (!isActive && countUnread) {
      buffer.unread++;
      if (state.nick.isNotEmpty &&
          line.kind == ChatLineKind.message &&
          line.text.toLowerCase().contains(state.nick.toLowerCase())) {
        buffer.mentioned = true;
      }
    }
    state = state.copyWith();
  }

  void _onEvent(IrcEvent e) {
    switch (e) {
      case RawLineEvent():
        return;
      case StatusChangedEvent(:final status, :final reason):
        state = state.copyWith(
          status: status,
          roomsLoading: status == IrcConnectionStatus.connected ? null : false,
        );
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
        _addLine(
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
        state = state.copyWith(untrustedCertificate: certificate);
        _addLine(
          statusBuffer,
          ChatLine(
            text:
                "$host's security certificate can't be verified because "
                '$why.',
            kind: ChatLineKind.error,
          ),
        );
      case RegisteredEvent(:final nick, :final network):
        state = state.copyWith(
          nick: nick,
          network: network,
          clearConnectionProblem: true,
        );
        _addLine(
          statusBuffer,
          ChatLine(
            text:
                'Welcome, $nick! Tap "Browse rooms" (the compass) to find '
                'a room, or type /join #room.',
            kind: ChatLineKind.event,
          ),
          countUnread: false,
        );
      case ServerInfoEvent(:final network):
        if (network != state.network) {
          state = state.copyWith(network: network);
        }
      case SaslEvent(:final outcome):
        _addLine(
          statusBuffer,
          ChatLine(
            text: 'Account login: ${outcome.name}',
            kind: ChatLineKind.event,
          ),
        );
      case MessageEvent():
        _addLine(
          e.target,
          ChatLine(
            sender: e.sender,
            text: stripFormatting(e.text),
            time: e.time,
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
        _addLine(
          channel,
          ChatLine(
            text: isSelf ? 'You joined $channel' : '$nick joined',
            kind: ChatLineKind.event,
            time: e.time,
          ),
          countUnread: false,
        );
        if (isSelf) {
          selectBuffer(channel);
          final host = this.host;
          if (host != null) {
            ref.read(roomPrefsProvider.notifier).addRecent(host, channel);
          }
        }
      case PartEvent(:final channel, :final nick, :final isSelf):
        final what = e.kickedBy != null
            ? '$nick was kicked by ${e.kickedBy}'
            : '$nick left';
        final reason = e.reason == null || e.reason!.isEmpty
            ? ''
            : ' (${e.reason})';
        _addLine(
          channel,
          ChatLine(
            text: '${isSelf && e.kickedBy == null ? 'You left' : what}$reason',
            kind: ChatLineKind.event,
            time: e.time,
          ),
          countUnread: false,
        );
      case QuitEvent(:final nick, :final channels, :final reason):
        for (final c in channels) {
          _addLine(
            c,
            ChatLine(
              text: '$nick quit${reason == null ? '' : ' ($reason)'}',
              kind: ChatLineKind.event,
              time: e.time,
            ),
            countUnread: false,
          );
        }
      case NickChangeEvent(:final oldNick, :final newNick, :final isSelf):
        if (isSelf) state = state.copyWith(nick: newNick);
        for (final c in e.channels) {
          _addLine(
            c,
            ChatLine(
              text: '$oldNick is now known as $newNick',
              kind: ChatLineKind.event,
            ),
            countUnread: false,
          );
        }
      case TopicEvent(:final channel, :final topic, :final setBy):
        _addLine(
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
        state = state.copyWith();
      case ChannelListEvent(:final entries):
        state = state.copyWith(
          rooms: entries,
          roomsLoading: false,
          roomsFetchedAt: DateTime.now(),
        );
        _addLine(
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
        if (code == 'CONNECT' && (_config?.useTls ?? false)) {
          state = state.copyWith(secureConnectFailed: true);
        }
        // 416: list too large / not allowed; LIST errors end the request.
        if (state.roomsLoading && (code == '416' || target == 'LIST')) {
          state = state.copyWith(roomsLoading: false, roomsError: text);
        }
        final buffer =
            target != null && state.buffers.containsKey(target.toLowerCase())
            ? target
            : state.active;
        _addLine(
          buffer,
          ChatLine(
            text: code == 'CONNECT' || code == 'ERROR' ? text : '$text ($code)',
            kind: ChatLineKind.error,
          ),
        );
      case ServerNoticeEvent(:final message, :final text):
        // 263 RPL_TRYAGAIN: the server refused LIST for now.
        if (state.roomsLoading && message.command == '263') {
          state = state.copyWith(roomsLoading: false, roomsError: text);
        }
        _addLine(
          statusBuffer,
          ChatLine(text: stripFormatting(text), kind: ChatLineKind.notice),
          countUnread: false,
        );
    }
  }
}
