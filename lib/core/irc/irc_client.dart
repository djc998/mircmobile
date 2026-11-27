/// The IRC connection state machine: registration, channels and messaging.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/flood_control.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_message.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/irc/isupport.dart';

/// Everything needed to connect to one network.
class IrcConnectionConfig {
  const IrcConnectionConfig({
    required this.host,
    required this.nick,
    this.port = 6697,
    this.useTls = true,
    this.username,
    this.realname,
    this.serverPassword,
    this.sasl,
    this.autoJoin = const [],
    this.autoReconnect = true,
    this.trustedFingerprints = const {},
    this.bouncerNetwork,
  });

  final String host;
  final int port;
  final bool useTls;
  final String nick;
  final String? username;
  final String? realname;
  final String? serverPassword;
  final SaslCredentials? sasl;
  final List<String> autoJoin;
  final bool autoReconnect;

  /// Certificates the user chose to trust for this server (SHA-256).
  final Set<String> trustedFingerprints;

  /// On a soju bouncer: the id of the network this connection is for
  /// (sent as `BOUNCER BIND`). Null for an ordinary server, or for the
  /// bouncer's own connection that lists its networks.
  final String? bouncerNetwork;

  /// What the app keys this network by: the host, plus `/id` for one of a
  /// bouncer's networks.
  String get networkKey {
    final h = host.toLowerCase();
    return bouncerNetwork == null ? h : '$h/$bouncerNetwork';
  }

  IrcConnectionConfig copyWith({
    String? nick,
    int? port,
    bool? useTls,
    Set<String>? trustedFingerprints,
    List<String>? autoJoin,
    String? bouncerNetwork,
  }) => IrcConnectionConfig(
    host: host,
    nick: nick ?? this.nick,
    port: port ?? this.port,
    useTls: useTls ?? this.useTls,
    username: username,
    realname: realname,
    serverPassword: serverPassword,
    sasl: sasl,
    autoJoin: autoJoin ?? this.autoJoin,
    autoReconnect: autoReconnect,
    trustedFingerprints: trustedFingerprints ?? this.trustedFingerprints,
    bouncerNetwork: bouncerNetwork ?? this.bouncerNetwork,
  );
}

/// A user in a channel together with their status prefixes (e.g. `@+`).
class IrcMember {
  IrcMember(this.nick, [this.prefixes = '']);

  String nick;

  /// Status symbols in rank order, highest first.
  String prefixes;

  /// The highest-ranked prefix symbol, or an empty string.
  String get topPrefix => prefixes.isEmpty ? '' : prefixes[0];

  /// Marked away (IRCv3 `away-notify`, or the H/G flag in a WHO reply).
  bool away = false;
}

/// Local state for a joined channel.
class IrcChannel {
  IrcChannel(this.name);

  final String name;
  String topic = '';
  String? topicSetBy;

  /// Members keyed by case-folded nick.
  final Map<String, IrcMember> members = {};

  /// Flag modes without arguments, e.g. `{'n', 't', 'i', 's'}`.
  final Set<String> modes = {};

  /// Join password (+k), if any.
  String? key;

  /// User limit (+l), if any.
  int? limit;

  /// Ban masks (+b), once asked for with [IrcClient.requestBans] or seen
  /// being set.
  final List<String> bans = [];

  /// Whether [bans] has been loaded from the server.
  bool bansLoaded = false;

  /// Whether [modes] reflect the server yet (after 324 or a MODE).
  bool modesKnown = false;

  bool get isInviteOnly => modes.contains('i');
  bool get isSecret => modes.contains('s');
  bool get isTopicLocked => modes.contains('t');
  bool get isModerated => modes.contains('m');
  bool get hasKey => key != null;
}

/// A single IRC connection.
///
/// It owns the transport, negotiates capabilities, answers PINGs, tracks
/// channels and members, and reports everything as [IrcEvent]s.
class IrcClient {
  IrcClient(
    this.config, {
    this._transportFactory = defaultTransportFactory,
    int floodBurst = 5,
    Duration floodInterval = const Duration(milliseconds: 1500),
    this.pingInterval = const Duration(seconds: 90),
    this.pingTimeout = const Duration(seconds: 60),
    this.maxReconnectDelay = const Duration(minutes: 5),
  }) {
    _flood = FloodControl(
      write: _write,
      burst: floodBurst,
      interval: floodInterval,
    );
    _nick = config.nick;
  }

  final IrcConnectionConfig config;
  final IrcTransportFactory _transportFactory;
  final Duration pingInterval;
  final Duration pingTimeout;
  final Duration maxReconnectDelay;

  late final FloodControl _flood;
  final StreamController<IrcEvent> _events =
      StreamController<IrcEvent>.broadcast();

  IrcTransport? _transport;
  // Cancelled in _teardown().
  // ignore: cancel_subscriptions
  StreamSubscription<String>? _subscription;
  CapNegotiator? _cap;
  Timer? _idleTimer;
  Timer? _reconnectTimer;
  Timer? _checkTimer;
  // The PING token [checkConnection] is waiting for, or null.
  String? _checkToken;
  int _checkCount = 0;
  bool _awaitingPong = false;
  bool _userQuit = false;
  int _reconnectAttempt = 0;
  int _nickAttempt = 0;
  final Set<String> _rejoin = {};
  // Rooms rejoined after a reconnect, case-folded, until their JOIN echo.
  final Set<String> _rejoining = {};
  final List<ChannelListEntry> _listBuffer = [];
  // Ban masks arriving (367) per case-folded channel, until 368.
  final _banBuffer = <String, List<String>>{};
  final Set<String> _namesInProgress = {};
  // Open IRCv3 batches by reference.
  final _batches = <String, _Batch>{};

  IrcConnectionStatus _status = IrcConnectionStatus.disconnected;
  late String _nick;
  ISupport _isupport = ISupport();
  String? _serverName;

  /// All client events. Broadcast, so several widgets can listen.
  Stream<IrcEvent> get events => _events.stream;

  IrcConnectionStatus get status => _status;

  /// Our current nickname.
  String get nick => _nick;

  ISupport get isupport => _isupport;

  /// Enabled IRCv3 capabilities.
  Set<String> get capabilities => _cap?.enabled ?? const {};

  /// Whether this is a soju bouncer that can list and bind networks.
  bool get isBouncer => capabilities.contains('soju.im/bouncer-networks');

  /// The bouncer's networks by id, once listed (empty otherwise).
  final Map<String, BouncerNetwork> bouncerNetworks = {};

  /// Whether the server passes on typing notifications (message tags).
  bool get supportsTyping => capabilities.contains('message-tags');

  /// Whether the server keeps your read position (draft/read-marker).
  bool get supportsReadMarkers => capabilities.contains('draft/read-marker');

  /// Sends a CTCP request, e.g. `DCC SEND …`.
  void sendCtcp(String target, String body) =>
      sendRaw('PRIVMSG $target :\x01$body\x01');

  /// Tells [target] you're typing: [state] is `active`, `paused` or `done`.
  void sendTyping(String target, String state) {
    if (!supportsTyping) return;
    sendRaw('@+typing=$state TAGMSG $target');
  }

  /// Tells the server you've read [target] up to [time].
  void markRead(String target, DateTime time) {
    if (!supportsReadMarkers) return;
    sendRaw('MARKREAD $target ${_timestamp(time)}');
  }

  /// Whether the server keeps history we can ask for (CHATHISTORY).
  bool get supportsHistory =>
      capabilities.contains('draft/chathistory') ||
      capabilities.contains('chathistory');

  /// How many messages to ask for at once: the server's limit, at most 100.
  int get historyLimit {
    final max = _isupport.chathistoryLimit;
    return max == null || max <= 0 || max > 100 ? 100 : max;
  }

  /// `timestamp=YYYY-MM-DDThh:mm:ss.sssZ`: IRCv3 wants exactly
  /// milliseconds, and servers (soju) refuse Dart's microseconds.
  static String _timestamp(DateTime t) {
    final ms = DateTime.fromMillisecondsSinceEpoch(
      t.millisecondsSinceEpoch,
      isUtc: true,
    );
    return 'timestamp=${ms.toIso8601String()}';
  }

  /// Asks for the latest messages in [target]: those after [after], or the
  /// newest [limit] when [after] is null. Replies come as [MessageEvent]s
  /// with `history` set, then a [HistoryBatchEvent].
  void requestHistory(String target, {DateTime? after, int? limit}) {
    if (!supportsHistory) return;
    final since = after == null ? '*' : _timestamp(after);
    sendRaw('CHATHISTORY LATEST $target $since ${limit ?? historyLimit}');
  }

  /// Asks for up to [limit] messages in [target] from before [before].
  void requestHistoryBefore(String target, DateTime before, {int? limit}) {
    if (!supportsHistory) return;
    sendRaw(
      'CHATHISTORY BEFORE $target ${_timestamp(before)} '
      '${limit ?? historyLimit}',
    );
  }

  /// Asks which conversations had messages between [from] and [to]; the
  /// answer is a [HistoryTargetsEvent].
  void requestHistoryTargets(DateTime from, DateTime to, {int? limit}) {
    if (!supportsHistory) return;
    sendRaw(
      'CHATHISTORY TARGETS ${_timestamp(from)} ${_timestamp(to)} '
      '${limit ?? historyLimit}',
    );
  }

  /// Joined channels keyed by case-folded name.
  final Map<String, IrcChannel> channels = {};

  /// Display name of the network.
  String get networkName => _isupport.networkName ?? _serverName ?? config.host;

  bool isChannel(String target) => _isupport.isChannel(target);

  IrcChannel? channel(String name) => channels[_isupport.fold(name)];

  bool isMe(String nick) => _isupport.fold(nick) == _isupport.fold(_nick);

  // ---------------------------------------------------------------------
  // Connection lifecycle
  // ---------------------------------------------------------------------

  /// Opens the connection and starts registration.
  Future<void> connect() async {
    if (_status != IrcConnectionStatus.disconnected &&
        _status != IrcConnectionStatus.reconnecting) {
      return;
    }
    _userQuit = false;
    _reconnectTimer?.cancel();
    _setStatus(IrcConnectionStatus.connecting);

    final transport = _transportFactory(
      config.host,
      config.port,
      useTls: config.useTls,
      trustedFingerprints: config.trustedFingerprints,
    );
    _transport = transport;
    try {
      await transport.connect();
    } on UntrustedCertificateException catch (e) {
      // Retrying can't help until the user decides, so don't reconnect.
      _transport = null;
      _emit(CertificateRejectedEvent(host: e.host, certificate: e.certificate));
      _setStatus(
        IrcConnectionStatus.disconnected,
        reason: 'Untrusted certificate',
      );
      return;
    } on Object catch (e) {
      _transport = null;
      _emit(ServerErrorEvent(code: 'CONNECT', text: 'Could not connect: $e'));
      _handleClosed(reason: '$e');
      return;
    }
    if (!identical(_transport, transport)) return; // Disconnected meanwhile.

    _subscription = transport.lines.listen(
      _onLine,
      onError: (Object e) => _handleClosed(reason: '$e'),
      onDone: () => _handleClosed(reason: 'Connection closed'),
    );
    _register();
  }

  /// Checks right away that the connection still works, e.g. when the app
  /// comes back from the background, where the system may have dropped the
  /// socket without telling us.
  ///
  /// A live connection answers the PING within [timeout] and a
  /// [ConnectionCheckedEvent] follows; a dead one is closed and reconnected
  /// at once (no backoff), and rejoins its channels. A connection that is
  /// already waiting to reconnect tries again now. Does nothing while
  /// disconnected or still connecting.
  void checkConnection({Duration timeout = const Duration(seconds: 6)}) {
    switch (_status) {
      case IrcConnectionStatus.reconnecting:
        _reconnectTimer?.cancel();
        _reconnectAttempt = 0;
        unawaited(connect());
      case IrcConnectionStatus.connected || IrcConnectionStatus.registering:
        if (_checkToken != null) return; // Already checking.
        final token = 'check-${++_checkCount}';
        _checkToken = token;
        _flood.sendNow('PING :$token');
        // Writing can fail at once on a dead socket, which reconnects.
        if (_checkToken != token) return;
        _checkTimer = Timer(timeout, () {
          if (_checkToken == token) {
            _handleClosed(reason: 'No answer from the server');
          }
        });
      case IrcConnectionStatus.connecting || IrcConnectionStatus.disconnected:
        return;
    }
  }

  void _endCheck() {
    _checkTimer?.cancel();
    _checkTimer = null;
    _checkToken = null;
  }

  /// Sends QUIT and closes. Does not reconnect.
  Future<void> disconnect([String reason = 'Leaving']) async {
    _userQuit = true;
    _reconnectTimer?.cancel();
    if (_transport != null) {
      _flood.sendNow('QUIT :$reason');
    }
    await _teardown();
    _rejoin.clear();
    _rejoining.clear();
    _setStatus(IrcConnectionStatus.disconnected, reason: reason);
  }

  /// Releases resources. The client can't be reused afterwards.
  Future<void> dispose() async {
    await disconnect();
    await _events.close();
  }

  /// SASL credentials: the account login, or for one of a soju bouncer's
  /// networks the username and server password. soju only allows
  /// `BOUNCER BIND` once logged in, and a server password (PASS) is only
  /// checked after registration, too late; SASL comes first.
  SaslCredentials? get _login {
    if (config.sasl != null) return config.sasl;
    final password = config.serverPassword ?? '';
    final user = (config.username ?? '').trim();
    if (config.bouncerNetwork == null || password.isEmpty || user.isEmpty) {
      return null;
    }
    return SaslCredentials(account: user, password: password);
  }

  void _register() {
    _setStatus(IrcConnectionStatus.registering);
    _nick = config.nick;
    _nickAttempt = 0;
    _isupport = ISupport();
    _cap = CapNegotiator(
      send: _flood.sendNow,
      sasl: _login,
      onFinished: (outcome) {
        if (config.sasl != null) _emit(SaslEvent(outcome));
      },
      beforeEnd: () {
        final net = config.bouncerNetwork;
        if (net != null && isBouncer) _flood.sendNow('BOUNCER BIND $net');
      },
    )..start();
    if (config.serverPassword != null && config.serverPassword!.isNotEmpty) {
      _flood.sendNow('PASS ${config.serverPassword}');
    }
    _flood
      ..sendNow('NICK $_nick')
      ..sendNow(
        'USER ${_username(config.username)} 0 * '
        ':${_realname(config.realname)}',
      );
    _resetIdleTimer();
  }

  Future<void> _teardown() async {
    _endCheck();
    _idleTimer?.cancel();
    _idleTimer = null;
    _flood.reset();
    final sub = _subscription;
    final transport = _transport;
    _subscription = null;
    _transport = null;
    await sub?.cancel();
    await transport?.close();
  }

  void _handleClosed({required String reason}) {
    if (_status == IrcConnectionStatus.disconnected) return;
    _rejoin.addAll(channels.values.map((c) => c.name));
    channels.clear();
    _batches.clear();
    // Found dead by checkConnection: the user is waiting, so no backoff.
    final checking = _checkToken != null;
    unawaited(_teardown());
    if (_userQuit || !config.autoReconnect) {
      _setStatus(IrcConnectionStatus.disconnected, reason: reason);
      return;
    }
    final delay = checking
        ? Duration.zero
        : reconnectDelay(_reconnectAttempt++, maxReconnectDelay);
    _setStatus(IrcConnectionStatus.reconnecting, reason: reason);
    _reconnectTimer = Timer(delay, () => unawaited(connect()));
  }

  /// Exponential backoff: 2s, 4s, 8s ... capped at [max].
  static Duration reconnectDelay(int attempt, Duration max) {
    final seconds = 2 * math.pow(2, math.min(attempt, 16));
    final d = Duration(seconds: seconds.toInt());
    return d > max ? max : d;
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _awaitingPong = false;
    _idleTimer = Timer(pingInterval, () {
      _awaitingPong = true;
      _flood.sendNow('PING :keepalive');
      _idleTimer = Timer(pingTimeout, () {
        if (_awaitingPong) _handleClosed(reason: 'Ping timeout');
      });
    });
  }

  void _setStatus(IrcConnectionStatus status, {String? reason}) {
    if (_status == status) return;
    _status = status;
    _emit(StatusChangedEvent(status, reason: reason));
  }

  void _emit(IrcEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _write(String line) {
    final transport = _transport;
    if (transport == null) return;
    try {
      transport.writeLine(line);
    } on Object catch (e) {
      // A dead connection: reconnect now instead of waiting for the
      // ping timeout.
      _handleClosed(reason: 'Connection lost: $e');
      return;
    }
    _emit(RawLineEvent(line, outgoing: true));
  }

  // ---------------------------------------------------------------------
  // Commands
  // ---------------------------------------------------------------------

  /// Sends a raw protocol line (rate limited once registered).
  void sendRaw(String line) {
    if (_status == IrcConnectionStatus.connected) {
      _flood.send(line);
    } else {
      _flood.sendNow(line);
    }
  }

  void join(String channel, {String? key}) =>
      sendRaw(key == null ? 'JOIN $channel' : 'JOIN $channel $key');

  void part(String channel, {String? reason}) =>
      sendRaw(reason == null ? 'PART $channel' : 'PART $channel :$reason');

  void changeNick(String nick) => sendRaw('NICK $nick');

  void setTopic(String channel, String topic) =>
      sendRaw('TOPIC $channel :$topic');

  void whois(String nick) => sendRaw('WHOIS $nick');

  /// Asks for a channel's modes (reply: 324).
  void requestModes(String channel) => sendRaw('MODE $channel');

  /// Changes channel modes, e.g. `setModes('#room', '+ik', ['secret'])`.
  void setModes(String channel, String modes, [List<String> args = const []]) =>
      sendRaw(['MODE', channel, modes, ...args].join(' '));

  void invite(String nick, String channel) => sendRaw('INVITE $nick $channel');

  void kick(String channel, String nick, {String? reason}) => sendRaw(
    reason == null || reason.isEmpty
        ? 'KICK $channel $nick'
        : 'KICK $channel $nick :$reason',
  );

  /// Asks the server for [channel]'s ban list (367/368 replies).
  void requestBans(String channel) => sendRaw('MODE $channel +b');

  /// Bans [nick] from [channel] by nickname mask (`nick!*@*`).
  void ban(String channel, String nick) =>
      setModes(channel, '+b', ['$nick!*@*']);

  /// Requests the channel list. Uses the ELIST `>n` filter when supported,
  /// otherwise filters [minUsers] locally when the results arrive.
  void list({int? minUsers, String? mask}) {
    _listBuffer.clear();
    _listMinUsers = minUsers;
    final args = <String>[];
    if (mask != null && mask.isNotEmpty) args.add(mask);
    if (minUsers != null && minUsers > 0 && _isupport.supportsElist('U')) {
      args.add('>${minUsers - 1}');
    }
    sendRaw(args.isEmpty ? 'LIST' : 'LIST ${args.join(',')}');
  }

  int? _listMinUsers;

  /// Sends a message, splitting long text so each line fits in 512 bytes.
  void sendMessage(String target, String text) =>
      _sendText('PRIVMSG', target, text);

  void sendNotice(String target, String text) =>
      _sendText('NOTICE', target, text);

  /// Sends a CTCP ACTION (/me).
  void sendAction(String target, String text) {
    for (final part in splitUtf8(text, _textBudget('PRIVMSG', target) - 9)) {
      sendRaw('PRIVMSG $target :\x01ACTION $part\x01');
      _localEcho(target, part, isAction: true);
    }
  }

  void _sendText(String command, String target, String text) {
    for (final line in const LineSplitter().convert(text)) {
      if (line.isEmpty) continue;
      for (final part in splitUtf8(line, _textBudget(command, target))) {
        sendRaw('$command $target :$part');
        _localEcho(target, part, isNotice: command == 'NOTICE');
      }
    }
  }

  void _localEcho(
    String target,
    String text, {
    bool isAction = false,
    bool isNotice = false,
  }) {
    // With echo-message the server sends our own lines back to us.
    if (capabilities.contains('echo-message')) return;
    _emit(
      MessageEvent(
        target: target,
        sender: _nick,
        text: text,
        isOwn: true,
        isAction: isAction,
        isNotice: isNotice,
      ),
    );
  }

  /// Bytes available for text, leaving room for the prefix the server adds
  /// when relaying (`:nick!user@host `) and the CRLF.
  int _textBudget(String command, String target) {
    final overhead =
        utf8.encode('$command $target :').length +
        utf8.encode(':$_nick!').length +
        10 + // user
        64 + // host
        2 + // '@' and ' '
        2; // CRLF
    return math.max(64, 512 - overhead);
  }

  /// Splits [text] into chunks of at most [maxBytes] UTF-8 bytes, never
  /// cutting a character and preferring to break at a space.
  static List<String> splitUtf8(String text, int maxBytes) {
    final out = <String>[];
    var rest = text;
    while (utf8.encode(rest).length > maxBytes) {
      var bytes = 0;
      var cut = 0;
      for (final rune in rest.runes) {
        final len = utf8.encode(String.fromCharCode(rune)).length;
        if (bytes + len > maxBytes) break;
        bytes += len;
        cut += rune > 0xFFFF ? 2 : 1;
      }
      final space = rest.lastIndexOf(' ', cut);
      if (space > cut ~/ 2) cut = space;
      out.add(rest.substring(0, cut));
      rest = rest.substring(cut).trimLeft();
    }
    if (rest.isNotEmpty || out.isEmpty) out.add(rest);
    return out;
  }

  // ---------------------------------------------------------------------
  // Incoming
  // ---------------------------------------------------------------------

  void _onLine(String line) {
    _resetIdleTimer();
    _emit(RawLineEvent(line, outgoing: false));
    final IrcMessage m;
    try {
      m = IrcMessage.parse(line);
    } on IrcParseException {
      return;
    }
    handleMessage(m);
  }

  /// Processes one parsed message. Public for tests.
  void handleMessage(IrcMessage m) {
    if (_cap?.handle(m) ?? false) return;
    final time = m.serverTime;
    final from = m.prefix?.nick ?? '';

    switch (m.command) {
      case 'PING':
        _flood.sendNow(m.params.isEmpty ? 'PONG' : 'PONG :${m.params.last}');
      case 'PONG':
        _awaitingPong = false;
        final token = _checkToken;
        if (token != null && m.params.contains(token)) {
          _endCheck();
          _emit(ConnectionCheckedEvent());
        }
      case '001':
        _nick = m.param(0) ?? _nick;
        _serverName = m.prefix?.raw;
        _reconnectAttempt = 0;
        _setStatus(IrcConnectionStatus.connected);
        _emit(RegisteredEvent(nick: _nick, network: networkName));
        _emit(ServerNoticeEvent(m, text: m.trailing ?? ''));
        _joinAfterRegistration();
        // The bouncer's own connection: ask which networks it has.
        if (isBouncer && config.bouncerNetwork == null) {
          sendRaw('BOUNCER LISTNETWORKS');
        }
      case '005':
        if (m.params.length > 2) {
          _isupport.apply(m.params.sublist(1, m.params.length - 1));
          _emit(ServerInfoEvent(network: networkName));
        }
      case '432' || '433' || '436'
          when _status == IrcConnectionStatus.registering:
        _nick = _nextNick();
        _flood.sendNow('NICK $_nick');
      case 'NICK':
        _onNick(from, m.param(0) ?? '', time);
      case 'JOIN':
        _onJoin(from, m.param(0) ?? '', time);
      case 'PART':
        _onPart(m.param(0) ?? '', from, m.param(1), null, time);
      case 'KICK':
        _onPart(m.param(0) ?? '', m.param(1) ?? '', m.param(2), from, time);
      case 'QUIT':
        _onQuit(from, m.param(0), time);
      case '315':
        // RPL_ENDOFWHO: the WHO after joining is only for away flags.
        break;
      case 'AWAY':
        // away-notify: a message means away, none means back.
        _setAway(from, away: (m.param(0) ?? '').isNotEmpty);
      case '352':
        // RPL_WHOREPLY: me #chan user host server nick H|G[*@+] :hops name
        final flags = m.param(6) ?? '';
        if (flags.isNotEmpty) {
          _setAway(m.param(5) ?? '', away: flags.startsWith('G'));
        }
      case 'MODE':
        _onMode(m);
      case '324':
        // RPL_CHANNELMODEIS: me #chan +modes args
        final chan = channel(m.param(1) ?? '');
        if (chan != null) {
          chan
            ..modes.clear()
            ..key = null
            ..limit = null;
          _applyChannelModes(chan, m.params.sublist(2));
          _emit(
            ChannelModeEvent(
              channel: chan.name,
              change: m.params.sublist(2).join(' '),
              time: time,
            ),
          );
        }
      case 'INVITE':
        _emit(InviteEvent(from: from, channel: m.param(1) ?? '', time: time));
      case 'TOPIC':
        _setChannelTopic(m.param(0) ?? '', m.param(1) ?? '', from);
      case '332':
        _setChannelTopic(m.param(1) ?? '', m.param(2) ?? '', null);
      case '367':
        // RPL_BANLIST: me #chan mask [setter time]
        final key = _isupport.fold(m.param(1) ?? '');
        final mask = m.param(2);
        if (mask != null) (_banBuffer[key] ??= []).add(mask);
      case '368':
        // RPL_ENDOFBANLIST
        final chan = channel(m.param(1) ?? '');
        final found = _banBuffer.remove(_isupport.fold(m.param(1) ?? ''));
        if (chan != null) {
          chan
            ..bans.clear()
            ..bans.addAll(found ?? const [])
            ..bansLoaded = true;
          // Not a membership change, but it refreshes the room's views.
          _emit(MembersChangedEvent(chan.name));
        }
      case '353':
        _onNames(m.param(2) ?? '', m.param(3) ?? '');
      case '366':
        final name = m.param(1) ?? '';
        _namesInProgress.remove(_isupport.fold(name));
        _emit(MembersChangedEvent(name));
        // With away-notify, one WHO tells us who's away already; later
        // changes arrive as AWAY. Skipped for big rooms to spare the server.
        final joined = channel(name);
        if (capabilities.contains('away-notify') &&
            joined != null &&
            joined.members.length <= whoAwayMaxMembers) {
          _flood.send('WHO $name');
        }
      case '321':
        _listBuffer.clear();
      case '322':
        _listBuffer.add(
          ChannelListEntry(
            name: m.param(1) ?? '',
            userCount: int.tryParse(m.param(2) ?? '') ?? 0,
            topic: _stripListModes(m.param(3) ?? ''),
          ),
        );
      case '323':
        final min = _listMinUsers ?? 0;
        _emit(
          ChannelListEvent(
            List.unmodifiable(_listBuffer.where((e) => e.userCount >= min)),
          ),
        );
        _listBuffer.clear();
      case 'PRIVMSG' || 'NOTICE':
        _onMessage(m, from, time);
      case 'BATCH':
        _onBatch(m);
      case 'TAGMSG':
        final typing = m.tags['+typing'];
        final target = m.param(0) ?? '';
        if (typing != null &&
            !isMe(from) &&
            !_batches.containsKey(m.tags['batch'])) {
          _emit(
            TypingEvent(
              target: _isupport.isChannel(target) ? target : from,
              nick: from,
              state: typing,
            ),
          );
        }
      case 'MARKREAD':
        final at = m.param(1) ?? '*';
        _emit(
          ReadMarkerEvent(
            target: m.param(0) ?? '',
            readUntil: at == '*'
                ? null
                : DateTime.tryParse(at.replaceFirst('timestamp=', '')),
          ),
        );
      case 'CHATHISTORY' when m.param(0) == 'TARGETS':
        final batch = _batches[m.tags['batch']];
        final at = DateTime.tryParse(
          (m.param(2) ?? '').replaceFirst('timestamp=', ''),
        );
        if (batch != null && at != null) {
          batch.targets.add((m.param(1) ?? '', at));
        }
      case 'BOUNCER' when m.param(0) == 'NETWORK':
        _onBouncerNetwork(m.param(1) ?? '', m.param(2) ?? '*');
        // Outside the LISTNETWORKS batch it's a change (-notify).
        if (!_batches.containsKey(m.tags['batch'])) {
          _emit(BouncerNetworksEvent(Map.of(bouncerNetworks)));
        }
      case 'FAIL' when m.param(0) == 'CHATHISTORY':
        _emit(HistoryBatchEvent(target: null, count: 0, failed: true));
      case 'FAIL':
        // IRCv3 standard replies, e.g. soju's FAIL BOUNCER …: show them.
        _emit(
          ServerErrorEvent(
            code: '${m.param(0)} ${m.param(1)}',
            text: m.trailing ?? '',
          ),
        );
      case 'ERROR':
        _emit(ServerErrorEvent(code: 'ERROR', text: m.trailing ?? ''));
      default:
        final numeric = m.numeric;
        if (numeric != null && numeric >= 400 && numeric < 600) {
          _emit(
            ServerErrorEvent(
              code: m.command,
              text: m.trailing ?? '',
              target: m.params.length > 2 ? m.params[1] : null,
            ),
          );
        } else if (numeric != null) {
          _emit(ServerNoticeEvent(m, text: m.params.skip(1).join(' ')));
        }
    }
  }

  void _joinAfterRegistration() {
    final targets = <String>{...config.autoJoin, ..._rejoin}.toList();
    _rejoining
      ..clear()
      ..addAll(_rejoin.map(_isupport.fold));
    _rejoin.clear();
    // JOIN accepts comma-separated channels; keep lines short.
    for (var i = 0; i < targets.length; i += 10) {
      sendRaw('JOIN ${targets.skip(i).take(10).join(',')}');
    }
  }

  String _nextNick() {
    _nickAttempt++;
    final base = config.nick;
    if (_nickAttempt <= 3) return '$base${'_' * _nickAttempt}';
    return '$base${math.Random().nextInt(9000) + 1000}';
  }

  IrcChannel _ensureChannel(String name) =>
      channels.putIfAbsent(_isupport.fold(name), () => IrcChannel(name));

  void _onJoin(String nick, String name, DateTime? time) {
    if (name.isEmpty) return;
    final self = isMe(nick);
    final chan = self ? _ensureChannel(name) : channel(name);
    chan?.members[_isupport.fold(nick)] = IrcMember(nick);
    _emit(
      JoinEvent(
        channel: name,
        nick: nick,
        isSelf: self,
        isRejoin: self && _rejoining.remove(_isupport.fold(name)),
        time: time,
      ),
    );
    _emit(MembersChangedEvent(name));
    // Learn the room's settings (invite only, password, ...).
    if (self) requestModes(name);
  }

  void _onPart(
    String name,
    String nick,
    String? reason,
    String? kickedBy,
    DateTime? time,
  ) {
    final self = isMe(nick);
    if (self) {
      channels.remove(_isupport.fold(name));
    } else {
      channel(name)?.members.remove(_isupport.fold(nick));
    }
    _emit(
      PartEvent(
        channel: name,
        nick: nick,
        isSelf: self,
        reason: reason,
        kickedBy: kickedBy,
        time: time,
      ),
    );
    _emit(MembersChangedEvent(name));
  }

  /// Rooms up to this size get a WHO after joining to learn who's away.
  static const int whoAwayMaxMembers = 200;

  /// Marks [nick] away or back in every room you share.
  void _setAway(String nick, {required bool away}) {
    if (nick.isEmpty) return;
    final key = _isupport.fold(nick);
    for (final c in channels.values) {
      final member = c.members[key];
      if (member != null && member.away != away) {
        member.away = away;
        _emit(MembersChangedEvent(c.name));
      }
    }
  }

  void _onQuit(String nick, String? reason, DateTime? time) {
    final key = _isupport.fold(nick);
    final shared = <String>[];
    for (final c in channels.values) {
      if (c.members.remove(key) != null) shared.add(c.name);
    }
    _emit(QuitEvent(nick: nick, channels: shared, reason: reason, time: time));
    for (final c in shared) {
      _emit(MembersChangedEvent(c));
    }
  }

  void _onNick(String oldNick, String newNick, DateTime? time) {
    if (newNick.isEmpty) return;
    final self = isMe(oldNick);
    if (self) _nick = newNick;
    final oldKey = _isupport.fold(oldNick);
    final shared = <String>[];
    for (final c in channels.values) {
      final member = c.members.remove(oldKey);
      if (member != null) {
        member.nick = newNick;
        c.members[_isupport.fold(newNick)] = member;
        shared.add(c.name);
      }
    }
    _emit(
      NickChangeEvent(
        oldNick: oldNick,
        newNick: newNick,
        isSelf: self,
        channels: shared,
        time: time,
      ),
    );
  }

  void _onNames(String name, String names) {
    final key = _isupport.fold(name);
    final chan = channel(name);
    if (chan == null) return;
    if (_namesInProgress.add(key)) chan.members.clear();
    final symbols = _isupport.prefixSymbols;
    for (final raw in names.split(' ')) {
      if (raw.isEmpty) continue;
      var i = 0;
      while (i < raw.length && symbols.contains(raw[i])) {
        i++;
      }
      var nick = raw.substring(i);
      final bang = nick.indexOf('!');
      if (bang != -1) nick = nick.substring(0, bang); // userhost-in-names
      chan.members[_isupport.fold(nick)] = IrcMember(
        nick,
        _sortPrefixes(raw.substring(0, i)),
      );
    }
  }

  void _onMode(IrcMessage m) {
    final target = m.param(0) ?? '';
    final chan = channel(target);
    if (chan == null || m.params.length < 2) return;
    final membersChanged = _applyChannelModes(chan, m.params.sublist(1));
    _emit(
      ChannelModeEvent(
        channel: chan.name,
        change: m.params.sublist(1).join(' '),
        setBy: m.prefix?.nick,
        time: m.serverTime,
      ),
    );
    if (membersChanged) _emit(MembersChangedEvent(chan.name));
  }

  /// Applies `+modes args...` to [chan]. Returns true when a member's
  /// prefix (op, voice, ...) changed.
  bool _applyChannelModes(IrcChannel chan, List<String> params) {
    if (params.isEmpty) return false;
    final modes = params.first;
    final args = params.sublist(1);
    final chanmodes = (_isupport.tokens['CHANMODES'] ?? 'b,k,l,imnpst').split(
      ',',
    );
    // Type A (lists, e.g. bans), B (always an argument, e.g. key),
    // C (argument only when set, e.g. limit), D (flags).
    final listArg = chanmodes.isNotEmpty ? chanmodes[0] : '';
    final alwaysArg = chanmodes.length > 1 ? chanmodes[1] : '';
    final setArg = chanmodes.length > 2 ? chanmodes[2] : '';
    var adding = true;
    var argIndex = 0;
    var changed = false;
    String? nextArg() => argIndex < args.length ? args[argIndex++] : null;
    for (final c in modes.split('')) {
      if (c == '+' || c == '-') {
        adding = c == '+';
        continue;
      }
      final symbol = _isupport.prefixes[c];
      if (symbol != null) {
        final nick = nextArg();
        if (nick == null) break;
        final member = chan.members[_isupport.fold(nick)];
        if (member != null) {
          member.prefixes = adding
              ? _sortPrefixes(member.prefixes + symbol)
              : member.prefixes.replaceAll(symbol, '');
          changed = true;
        }
      } else if (listArg.contains(c)) {
        final mask = nextArg();
        if (c == 'b' && mask != null) {
          chan.bans.remove(mask);
          if (adding) chan.bans.add(mask);
        }
      } else if (alwaysArg.contains(c)) {
        final arg = nextArg();
        if (c == 'k') chan.key = adding ? arg : null;
      } else if (setArg.contains(c)) {
        if (adding) {
          final arg = nextArg();
          if (c == 'l') chan.limit = int.tryParse(arg ?? '');
        } else if (c == 'l') {
          chan.limit = null;
        }
      } else if (adding) {
        chan.modes.add(c);
      } else {
        chan.modes.remove(c);
      }
    }
    chan.modesKnown = true;
    return changed;
  }

  /// Whether we are an operator (or higher) in [name].
  bool isOperator(String name) {
    final me = channel(name)?.members[_isupport.fold(_nick)];
    if (me == null) return false;
    // Prefix symbols are ordered highest first; op is the one for 'o'.
    final order = _isupport.prefixSymbols;
    final op = _isupport.prefixes['o'] ?? '@';
    final opRank = order.indexOf(op);
    if (opRank == -1) return me.prefixes.contains(op);
    return me.prefixes.split('').any((p) {
      final rank = order.indexOf(p);
      return rank >= 0 && rank <= opRank;
    });
  }

  String _sortPrefixes(String prefixes) {
    final order = _isupport.prefixSymbols;
    final unique = prefixes.split('').toSet().toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return unique.join();
  }

  void _setChannelTopic(String name, String topic, String? setBy) {
    final chan = channel(name);
    if (chan != null) {
      chan
        ..topic = topic
        ..topicSetBy = setBy;
    }
    _emit(TopicEvent(channel: name, topic: topic, setBy: setBy));
  }

  /// BATCH +ref type params… opens a batch; BATCH -ref closes it.
  void _onBatch(IrcMessage m) {
    final ref = m.param(0) ?? '';
    if (ref.startsWith('+') && ref.length > 1) {
      _batches[ref.substring(1)] = _Batch(m.param(1) ?? '', m.param(2));
    } else if (ref.startsWith('-')) {
      final batch = _batches.remove(ref.substring(1));
      if (batch == null) return;
      if (_isHistoryBatch(batch.type)) {
        _emit(HistoryBatchEvent(target: batch.target, count: batch.count));
      } else if (batch.type == 'soju.im/bouncer-networks') {
        _emit(BouncerNetworksEvent(Map.of(bouncerNetworks)));
      } else if (batch.type.endsWith('chathistory-targets')) {
        _emit(
          HistoryTargetsEvent([
            for (final t in batch.targets) (name: t.$1, latest: t.$2),
          ]),
        );
      }
    }
  }

  /// One `BOUNCER NETWORK <id> <attrs>`: new, changed (only the changed
  /// attributes are sent; an empty value removes one) or `*` for deleted.
  void _onBouncerNetwork(String id, String attrs) {
    if (id.isEmpty) return;
    if (attrs == '*') {
      bouncerNetworks.remove(id);
      return;
    }
    final next = {...?bouncerNetworks[id]?.attributes};
    for (final MapEntry(:key, :value) in IrcMessage.parseTags(attrs).entries) {
      if (value.isEmpty) {
        next.remove(key);
      } else {
        next[key] = value;
      }
    }
    bouncerNetworks[id] = BouncerNetwork(id: id, attributes: next);
  }

  static bool _isHistoryBatch(String type) =>
      type == 'chathistory' || type == 'draft/chathistory';

  /// Some servers prefix LIST topics with channel modes like `[+nt] `.
  static String _stripListModes(String topic) =>
      topic.replaceFirst(RegExp(r'^\[\+[A-Za-z]*(?: [^\]]*)?\]\s?'), '');

  void _onMessage(IrcMessage m, String from, DateTime? time) {
    var target = m.param(0) ?? '';
    var text = m.param(1) ?? '';
    final isNotice = m.command == 'NOTICE';

    // STATUSMSG targets such as `@#channel` belong to the channel buffer.
    final symbols = _isupport.prefixSymbols;
    while (target.length > 1 &&
        symbols.contains(target[0]) &&
        _isupport.isChannel(target.substring(1))) {
      target = target.substring(1);
    }

    final isOwn = isMe(from);
    final batch = _batches[m.tags['batch']];
    final history = batch != null && _isHistoryBatch(batch.type);
    // Ergo replays joins and parts as messages from HistServ ("bob joined
    // the channel") to clients without event-playback: not chat.
    if (history && from == 'HistServ') return;
    if (history) batch.count++;
    // Server notices before/after registration go to the status window.
    if (m.prefix == null || m.prefix!.isServer || target == '*') {
      _emit(ServerNoticeEvent(m, text: text));
      return;
    }

    var isAction = false;
    if (text.length > 1 && text.startsWith('\x01')) {
      final body = text.substring(1).replaceAll('\x01', '');
      final space = body.indexOf(' ');
      final ctcp = (space == -1 ? body : body.substring(0, space))
          .toUpperCase();
      final arg = space == -1 ? '' : body.substring(space + 1);
      if (ctcp == 'ACTION') {
        isAction = true;
        text = arg;
      } else if (ctcp == 'DCC' && !isNotice && !isOwn && !history) {
        _emit(DccOfferEvent(from: from, args: arg));
        return;
      } else {
        // Never answer a CTCP request again from history.
        if (!isNotice && !isOwn && !history) _replyCtcp(from, ctcp, arg);
        return;
      }
    }

    // Private messages are filed under the other person's nick.
    final buffer = _isupport.isChannel(target)
        ? target
        : (isOwn ? target : from);

    _emit(
      MessageEvent(
        target: buffer,
        sender: from,
        text: text,
        isOwn: isOwn,
        isAction: isAction,
        isNotice: isNotice,
        tags: m.tags,
        history: history,
        time: time,
      ),
    );
  }

  void _replyCtcp(String to, String command, String arg) {
    switch (command) {
      case 'VERSION':
        sendRaw('NOTICE $to :\x01VERSION $clientVersion\x01');
      case 'PING':
        sendRaw('NOTICE $to :\x01PING $arg\x01');
      case 'TIME':
        sendRaw('NOTICE $to :\x01TIME ${DateTime.now().toUtc()}\x01');
    }
  }

  /// Username sent when the user hasn't set one.
  ///
  /// Not the nickname: networks such as DALnet treat a login where the nick,
  /// username and real name are all the same as a bot ("drone") and ban it.
  static const String defaultUsername = 'mobile';

  /// Real name ("gecos") sent when the user hasn't set one.
  static const String defaultRealname = 'Mobile IRC user';

  /// A username must be one word of safe characters; fall back otherwise.
  static String _username(String? value) {
    final cleaned = (value ?? '').trim().replaceAll(
      RegExp('[^A-Za-z0-9_.-]'),
      '',
    );
    if (cleaned.isEmpty) return defaultUsername;
    return cleaned.length > 10 ? cleaned.substring(0, 10) : cleaned;
  }

  static String _realname(String? value) {
    final cleaned = (value ?? '').replaceAll(RegExp(r'[\r\n]'), ' ').trim();
    return cleaned.isEmpty ? defaultRealname : cleaned;
  }

  /// Reported in CTCP VERSION replies. `main` adds this build's version.
  static String clientVersion = 'IRCage';
}

/// An open IRCv3 batch: its type, first parameter (the conversation, for
/// chathistory), the messages counted in it and any TARGETS lines.
class _Batch {
  _Batch(this.type, this.target);

  final String type;
  final String? target;
  int count = 0;
  final List<(String, DateTime)> targets = [];
}
