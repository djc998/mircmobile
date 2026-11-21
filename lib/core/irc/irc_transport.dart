/// Byte transport for IRC: TLS/plain sockets plus the line codec.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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
///
/// [trustedFingerprints] are SHA-256 fingerprints of certificates the user
/// chose to trust even though normal verification fails (self-signed,
/// wrong name or expired), as many EFnet servers use.
typedef IrcTransportFactory = IrcTransport Function(
  String host,
  int port, {
  required bool useTls,
  Set<String> trustedFingerprints,
});

/// Details of a server certificate, shown when asking the user to trust it.
class CertificateInfo {
  const CertificateInfo({
    required this.subject,
    required this.issuer,
    required this.validUntil,
    required this.sha256,
  });

  factory CertificateInfo.fromCertificate(X509Certificate cert) =>
      CertificateInfo(
        subject: cert.subject,
        issuer: cert.issuer,
        validUntil: cert.endValidity,
        sha256: certificateFingerprint(cert.der),
      );

  final String subject;
  final String issuer;
  final DateTime validUntil;

  /// Upper-case hex SHA-256 of the DER certificate, colon separated.
  final String sha256;

  bool get isExpired => validUntil.isBefore(DateTime.now());

  bool get isSelfSigned => subject == issuer;
}

/// SHA-256 fingerprint in the usual `AB:CD:...` form.
String certificateFingerprint(List<int> der) => sha256
    .convert(der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// The server's certificate failed verification and isn't trusted.
class UntrustedCertificateException implements Exception {
  UntrustedCertificateException(this.host, this.certificate);

  final String host;
  final CertificateInfo certificate;

  @override
  String toString() =>
      "The certificate for $host can't be verified "
      '(${certificate.subject}, issued by ${certificate.issuer}).';
}

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
    this.trustedFingerprints = const {},
    this.timeout = const Duration(seconds: 20),
  });

  final String host;
  final int port;

  /// TLS is the default. Plaintext is allowed but the UI warns about it.
  final bool useTls;
  final Set<String> trustedFingerprints;
  final Duration timeout;

  Socket? _socket;
  final StreamController<String> _lines = StreamController<String>();

  /// Set once the connection has failed or been closed. After that,
  /// writes are dropped instead of hitting a dead socket.
  bool _closed = false;

  @override
  Stream<String> get lines => _lines.stream;

  @override
  Future<void> connect() async {
    CertificateInfo? rejected;
    final Socket socket;
    try {
      socket = useTls
          ? await SecureSocket.connect(
              host,
              port,
              timeout: timeout,
              // Only called when normal verification fails. Accept the
              // certificate only if the user trusted this exact one before.
              onBadCertificate: (cert) {
                final info = CertificateInfo.fromCertificate(cert);
                if (trustedFingerprints.contains(info.sha256)) return true;
                rejected = info;
                return false;
              },
            )
          : await Socket.connect(host, port, timeout: timeout);
    } on HandshakeException {
      final info = rejected;
      if (info != null) throw UntrustedCertificateException(host, info);
      rethrow;
    }
    _socket = socket..setOption(SocketOption.tcpNoDelay, true);
    // Write errors (broken pipe, connection reset) are reported on
    // `done`, not where the write happened. Without this handler they
    // become unhandled exceptions and the client never hears about them.
    unawaited(socket.done.then<void>((_) => _fail(null), onError: _fail));
    const IrcLineDecoder()
        .bind(socket)
        .listen(
          _lines.add,
          onError: _fail,
          onDone: () => _fail(null),
          cancelOnError: true,
        );
  }

  /// Reports the end of the connection to [lines] exactly once.
  void _fail(Object? error) {
    if (_closed) return;
    _closed = true;
    if (_lines.isClosed) return;
    if (error != null) _lines.addError(error);
    unawaited(_lines.close());
  }

  @override
  void writeLine(String line) {
    final socket = _socket;
    if (socket == null || _closed) return;
    try {
      socket.add(utf8.encode('$line\r\n'));
    } on Object catch (e) {
      _fail(e);
    }
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    final alreadyDead = _closed;
    _closed = true;
    if (socket == null) return;
    try {
      // Flushing a dead socket never finishes, so only flush a live one,
      // and never wait long (the QUIT line is a courtesy).
      if (!alreadyDead) {
        await socket.flush().timeout(const Duration(seconds: 2));
      }
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
  Set<String> trustedFingerprints = const {},
}) => SocketIrcTransport(
  host,
  port,
  useTls: useTls,
  trustedFingerprints: trustedFingerprints,
);
