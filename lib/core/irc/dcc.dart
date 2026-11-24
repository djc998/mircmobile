/// DCC SEND: files sent directly between two IRC clients (mIRC, HexChat,
/// irssi…), without a server in between.
///
/// The offer is a CTCP message:
/// `DCC SEND <name> <ip> <port> <size> [token]`. The receiver connects to
/// `<ip>:<port>` and reads `<size>` bytes, acknowledging with the 4-byte
/// count received so far. "Passive"
/// (reverse) DCC has port 0 and a token: the receiver listens instead and
/// answers with its own address, port and the token.
///
/// A direct connection shows each side the other's IP address, and only
/// works when one side can accept connections (same network, or an open
/// port), which is rare on mobile data.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The biggest DCC file the app accepts (it's written to disk, not kept in
/// memory).
const int maxDccBytes = 2 * 1024 * 1024 * 1024;

/// An offer from `DCC SEND`.
@immutable
class DccOffer {
  const DccOffer({
    required this.name,
    required this.host,
    required this.port,
    required this.size,
    this.token,
  });

  /// The file's name as offered (not yet made safe to save).
  final String name;

  /// Where to connect (ignored for a passive offer).
  final InternetAddress host;

  /// 0 for a passive offer: we listen and reply.
  final int port;

  /// Size in bytes; 0 when the sender didn't say.
  final int size;

  /// Set for passive offers, to match the reply.
  final String? token;

  bool get passive => port == 0 && token != null;

  /// Parses the part of a `DCC` CTCP after `DCC `, e.g.
  /// `SEND "my file.txt" 3232235777 5000 1234`. Null if it isn't a usable
  /// SEND offer.
  static DccOffer? parse(String args) {
    final words = _split(args);
    if (words.length < 5 || words[0].toUpperCase() != 'SEND') return null;
    final name = words[1];
    final host = _address(words[2]);
    final port = int.tryParse(words[3]);
    final size = int.tryParse(words[4]) ?? 0;
    final token = words.length > 5 ? words[5] : null;
    if (name.isEmpty || host == null || port == null) return null;
    if (port < 0 || port > 65535 || size < 0) return null;
    if (port == 0 && token == null) return null;
    return DccOffer(
      name: name,
      host: host,
      port: port,
      size: size,
      token: token,
    );
  }

  /// Words, with "double quoted" ones (names with spaces) kept together.
  static List<String> _split(String s) {
    final out = <String>[];
    final m = RegExp(r'"([^"]*)"|(\S+)').allMatches(s.trim());
    for (final w in m) {
      out.add(w.group(1) ?? w.group(2)!);
    }
    return out;
  }

  /// IPv4 written as one number (the classic form), or a literal address.
  static InternetAddress? _address(String s) {
    final n = int.tryParse(s);
    if (n != null) {
      if (n < 0 || n > 0xFFFFFFFF) return null;
      return InternetAddress(
        '${(n >> 24) & 255}.${(n >> 16) & 255}.${(n >> 8) & 255}.${n & 255}',
      );
    }
    return InternetAddress.tryParse(s);
  }
}

/// The CTCP body offering [name] from [address]:[port] (`DCC SEND …`).
String dccSendArgs(
  String name,
  InternetAddress address,
  int port,
  int size, {
  String? token,
}) {
  final safe = name.replaceAll('"', "'");
  final quoted = safe.contains(' ') ? '"$safe"' : safe;
  final host = address.type == InternetAddressType.IPv4
      ? _ipv4Number(address).toString()
      : address.address;
  return 'SEND $quoted $host $port $size${token == null ? '' : ' $token'}';
}

int _ipv4Number(InternetAddress a) {
  final b = a.rawAddress;
  return (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
}

/// This device's address on the local network (Wi-Fi or Ethernet), the one
/// to offer: a private IPv4 if there is one, else any non-loopback IPv4.
Future<InternetAddress?> localAddress() async {
  final List<NetworkInterface> all;
  try {
    all = await NetworkInterface.list(type: InternetAddressType.IPv4);
  } on Object {
    return null;
  }
  InternetAddress? fallback;
  for (final i in all) {
    for (final a in i.addresses) {
      if (a.isLoopback || a.isLinkLocal) continue;
      if (_isPrivate(a)) return a;
      fallback ??= a;
    }
  }
  return fallback;
}

bool _isPrivate(InternetAddress a) {
  final b = a.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] < 32) ||
      (b[0] == 192 && b[1] == 168);
}

/// A problem with a transfer, worth showing as is.
class DccException implements Exception {
  const DccException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads [size] bytes from [socket] into [into], acknowledging as it goes.
Future<void> _readInto(
  Socket socket,
  File into,
  int size,
  void Function(int received)? onProgress,
  Duration idle,
) async {
  final sink = into.openWrite();
  var received = 0;
  final done = Completer<void>();
  late StreamSubscription<Uint8List> sub;
  Timer? stall;
  void resetStall() {
    stall?.cancel();
    stall = Timer(idle, () {
      if (!done.isCompleted) {
        done.completeError(const DccException('The transfer stalled.'));
      }
    });
  }

  resetStall();
  sub = socket.listen(
    (chunk) {
      var data = chunk;
      if (size > 0 && received + data.length > size) {
        data = Uint8List.sublistView(data, 0, size - received);
      }
      received += data.length;
      if (received > maxDccBytes) {
        if (!done.isCompleted) {
          done.completeError(const DccException('That file is too big.'));
        }
        return;
      }
      sink.add(data);
      // The classic acknowledgement: total bytes received, 4 bytes.
      final ack = ByteData(4)..setUint32(0, received & 0xFFFFFFFF);
      socket.add(ack.buffer.asUint8List());
      onProgress?.call(received);
      resetStall();
      if (size > 0 && received >= size && !done.isCompleted) done.complete();
    },
    onError: (Object e) {
      if (!done.isCompleted) {
        done.completeError(const DccException('The connection failed.'));
      }
    },
    onDone: () {
      if (done.isCompleted) return;
      if (size == 0 || received >= size) {
        done.complete();
      } else {
        done.completeError(
          const DccException('The sender stopped before the end.'),
        );
      }
    },
    cancelOnError: true,
  );
  try {
    await done.future;
  } finally {
    stall?.cancel();
    await sub.cancel();
    await sink.close();
    socket.destroy();
  }
}

/// Receives [offer] into [into] by connecting to the sender.
Future<void> receiveDcc(
  DccOffer offer,
  File into, {
  void Function(int received)? onProgress,
  Duration connectTimeout = const Duration(seconds: 20),
  Duration idle = const Duration(seconds: 60),
}) async {
  if (offer.size > maxDccBytes) {
    throw const DccException('That file is too big.');
  }
  final Socket socket;
  try {
    socket = await Socket.connect(
      offer.host,
      offer.port,
      timeout: connectTimeout,
    );
  } on Object {
    throw const DccException(
      "Couldn't connect to the sender. Direct transfers need you both on "
      'the same network, or an open port on their side.',
    );
  }
  await _readInto(socket, into, offer.size, onProgress, idle);
}

/// Listens for the other side to connect, for sending (or for a passive
/// receive). [address] is what to offer; [port] is where it listens.
class DccListener {
  DccListener._(this._server, this.address);

  final ServerSocket _server;
  final InternetAddress address;

  int get port => _server.port;

  /// Listens on any port on this device's local address. Throws a
  /// [DccException] when there's no usable network.
  static Future<DccListener> open() async {
    final address = await localAddress();
    if (address == null) {
      throw const DccException('No network connection for a direct transfer.');
    }
    final server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    return DccListener._(server, address);
  }

  /// Waits for one connection, at most [timeout].
  Future<Socket> accept({Duration timeout = const Duration(minutes: 2)}) async {
    try {
      return await _server.first.timeout(timeout);
    } on TimeoutException {
      throw const DccException(
        "They didn't connect. Direct transfers need you both on the same "
        'network, or an open port on your side.',
      );
    } finally {
      await _server.close();
    }
  }

  Future<void> close() => _server.close();
}

/// Sends [file] to whoever connects to [listener], then closes.
Future<void> sendDcc(
  DccListener listener,
  File file, {
  void Function(int sent)? onProgress,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final socket = await listener.accept(timeout: timeout);
  // Acknowledgements are read and ignored, so they don't fill buffers.
  final acks = socket.listen((_) {}, onError: (_) {});
  var sent = 0;
  try {
    await for (final chunk in file.openRead()) {
      socket.add(chunk);
      sent += chunk.length;
      onProgress?.call(sent);
      await socket.flush();
    }
    await socket.flush();
  } on Object {
    throw const DccException('The connection broke during the transfer.');
  } finally {
    // Give the receiver a moment to read the last bytes.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await acks.cancel();
    socket.destroy();
  }
}

/// Receives a passive offer: listen, tell the sender where (via [reply]),
/// then read.
Future<void> receivePassiveDcc(
  DccOffer offer,
  File into, {
  required void Function(String ctcpArgs) reply,
  void Function(int received)? onProgress,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final listener = await DccListener.open();
  reply(
    dccSendArgs(
      offer.name,
      listener.address,
      listener.port,
      offer.size,
      token: offer.token,
    ),
  );
  final socket = await listener.accept(timeout: timeout);
  await _readInto(
    socket,
    into,
    offer.size,
    onProgress,
    const Duration(seconds: 60),
  );
}
