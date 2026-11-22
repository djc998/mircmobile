/// Talks to the call server (`server/picture-host/src/calls.js`): starts
/// calls, fetches relay addresses, declines, and carries signaling messages
/// over a WebSocket.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:irc_client/features/calls/domain/call_link.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A problem worth showing to the user as is.
class CallException implements Exception {
  const CallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// STUN/TURN servers for one call, and whether a relay is among them.
typedef IceConfig = ({List<Map<String, Object?>> servers, bool relay});

/// One side of a call's signaling channel. Messages are small JSON maps:
/// `hello`, `joined`, `offer`, `answer`, `ice`, `bye`, `declined`,
/// `timeout`, and `closed` when the connection drops.
abstract interface class CallSignaling {
  Stream<Map<String, Object?>> get messages;
  void send(Map<String, Object?> message);
  Future<void> close();
}

class CallApi {
  CallApi({
    required String host,
    http.Client? client,
    this.appToken = pictureAppToken,
  }) : host = host.isEmpty ? null : Uri.parse(host),
       _http = client ?? http.Client();

  final Uri? host;
  final String appToken;
  final http.Client _http;

  bool get isConfigured => host != null;

  /// Starts a call on the server and returns its link.
  Future<CallLink> create({required bool video}) async {
    final base = host;
    if (base == null) throw const CallException("Calls aren't set up yet.");
    final http.Response res;
    try {
      res = await _http.post(
        base.replace(path: '/call'),
        headers: {
          'content-type': 'application/json',
          if (appToken.isNotEmpty) 'x-app-token': appToken,
        },
        body: jsonEncode({'video': video}),
      );
    } on Object {
      throw const CallException("Couldn't reach the call server.");
    }
    if (res.statusCode != 201) {
      throw CallException(_errorText(res) ?? "Couldn't start the call.");
    }
    final url = (jsonDecode(res.body) as Map<String, Object?>)['url'];
    final link = url is String ? CallLink.parse(url) : null;
    if (link == null) throw const CallException("Couldn't start the call.");
    return link;
  }

  /// STUN and, when the server has a TURN key, relay addresses.
  Future<IceConfig> ice(CallLink link) async {
    try {
      final res = await _http.get(link.ice);
      final body = jsonDecode(res.body) as Map<String, Object?>;
      final servers = (body['iceServers'] as List<Object?>? ?? const [])
          .whereType<Map<String, Object?>>()
          .toList();
      return (servers: servers, relay: body['relay'] == true);
    } on Object {
      return (
        servers: const [
          <String, Object?>{
            'urls': ['stun:stun.cloudflare.com:3478'],
          },
        ],
        relay: false,
      );
    }
  }

  /// Tells the caller the call was declined. Best effort.
  Future<void> decline(CallLink link) async {
    try {
      await _http.post(link.decline);
    } on Object {
      // The call rings out on its own.
    }
  }

  static String? _errorText(http.Response res) {
    try {
      return (jsonDecode(res.body) as Map<String, Object?>)['error'] as String?;
    } on Object {
      return null;
    }
  }
}

/// Opens the signaling WebSocket for [link].
typedef CallSignalingFactory = Future<CallSignaling> Function(CallLink link);

Future<CallSignaling> connectCallSignaling(CallLink link) async {
  final channel = WebSocketChannel.connect(link.socket);
  try {
    await channel.ready;
  } on Object {
    throw const CallException('This call has ended.');
  }
  return _WebSocketSignaling(channel);
}

class _WebSocketSignaling implements CallSignaling {
  _WebSocketSignaling(this._channel) {
    _sub = _channel.stream.listen(
      (data) {
        if (data is! String) return;
        try {
          final msg = jsonDecode(data);
          if (msg is Map<String, Object?>) _messages.add(msg);
        } on FormatException {
          // Ignore junk.
        }
      },
      onError: (Object _) => _finish(),
      onDone: _finish,
      cancelOnError: true,
    );
  }

  final WebSocketChannel _channel;
  late final StreamSubscription<Object?> _sub;
  final _messages = StreamController<Map<String, Object?>>.broadcast();

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void send(Map<String, Object?> message) {
    try {
      _channel.sink.add(jsonEncode(message));
    } on Object {
      // Closed; the done handler reports it.
    }
  }

  void _finish() {
    if (_messages.isClosed) return;
    _messages.add(const {'type': 'closed'});
    unawaited(_messages.close());
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    _finish();
    await _channel.sink.close();
  }
}

final callApiProvider = Provider<CallApi>(
  (ref) => CallApi(
    host: pictureHostSetting.isNotEmpty
        ? pictureHostSetting
        : defaultPictureHost,
  ),
);

final callSignalingFactoryProvider = Provider<CallSignalingFactory>(
  (ref) => connectCallSignaling,
);
