/// Byte transport for IRC: TLS/plain sockets plus the line codec.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A bidirectional line-oriented connection to an IRC server.
///
/// The client only talks to this interface, so a bouncer or WebSocket
/// transport can be added later without touching the protocol code.
abstract interface class IrcTransport {
  /// Opens the connection. Completes once it is ready for [writeLine].
  Future<void> connect();

  /// Incoming lines, without CR/LF. Closes when the connection ends.
  Stream<String> get lines;

  /// Sends one line. The transport appends CRLF.
  void writeLine(String line);

  /// Closes the connection.
  Future<void> close();
}

/// Creates a transport for a server address.
typedef IrcTransportFactory = IrcTransport Function(
  String host,
  int port, {
  required bool useTls,
});

/// Splits a byte stream into IRC lines.
///
/// Lines end with LF (CR is stripped). Each line is decoded as UTF-8 and
/// falls back to Latin-1 when the bytes are not valid UTF-8, which is common
/// on older networks.
class IrcLineDecoder extends StreamTransformerBase<List<int>, String> {
  const IrcLineDecoder();

  /// Decodes one line of raw bytes.
  static String decodeLine(List<int> bytes) {
    var end = bytes.length;
    while (end > 0 && (bytes[end - 1] == 0x0A || bytes[end - 1] == 0x0D)) {
      end--;
    }
    final slice = bytes.sublist(0, end);
    try {
      return utf8.decode(slice);
    } on FormatException {
      return latin1.decode(slice);
    }
  }

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    return Stream<String>.eventTransformed(stream, _LineSink.new);
  }
}

class _LineSink implements EventSink<List<int>> {
  _LineSink(this._out);

  final EventSink<String> _out;
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  @override
  void add(List<int> chunk) {
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0A) continue;
      _buffer.add(chunk.sublist(start, i));
      start = i + 1;
      final line = IrcLineDecoder.decodeLine(_buffer.takeBytes());
      if (line.isNotEmpty) _out.add(line);
    }
    if (start < chunk.length) _buffer.add(chunk.sublist(start));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _out.addError(error, stackTrace);

  @override
  void close() {
    if (_buffer.isNotEmpty) {
      final line = IrcLineDecoder.decodeLine(_buffer.takeBytes());
      if (line.isNotEmpty) _out.add(line);
    }
    _out.close();
  }
}

/// Real network transport using `dart:io` sockets.
class SocketIrcTransport implements IrcTransport {
  SocketIrcTransport(
    this.host,
    this.port, {
    required this.useTls,
    this.timeout = const Duration(seconds: 20),
  });

  final String host;
  final int port;

  /// TLS is the default. Plaintext is allowed but the UI warns about it.
  final bool useTls;
  final Duration timeout;

  Socket? _socket;
  final StreamController<String> _lines = StreamController<String>();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> connect() async {
    final socket = useTls
        ? await SecureSocket.connect(host, port, timeout: timeout)
        : await Socket.connect(host, port, timeout: timeout);
    _socket = socket..setOption(SocketOption.tcpNoDelay, true);
    const IrcLineDecoder()
        .bind(socket)
        .listen(
          _lines.add,
          onError: _lines.addError,
          onDone: _lines.close,
          cancelOnError: true,
        );
  }

  @override
  void writeLine(String line) {
    _socket?.add(utf8.encode('$line\r\n'));
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    try {
      await socket.flush();
    } on Object {
      // The socket may already be gone; closing below is what matters.
    }
    socket.destroy();
  }
}

/// Default factory used by the app.
IrcTransport defaultTransportFactory(
  String host,
  int port, {
  required bool useTls,
}) => SocketIrcTransport(host, port, useTls: useTls);
