@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_transport.dart';

/// Runs a real TLS server with a self-signed certificate (like many EFnet
/// servers) and checks that the transport rejects it until it's trusted.
void main() {
  late Directory dir;
  late SecureServerSocket server;
  late String fingerprint;

  setUpAll(() async {
    dir = await Directory.systemTemp.createTemp('irc_tls_test');
    final result = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=irc.selfsigned.test',
      '-keyout',
      '${dir.path}/key.pem',
      '-out',
      '${dir.path}/cert.pem',
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    final context = SecurityContext()
      ..useCertificateChain('${dir.path}/cert.pem')
      ..usePrivateKey('${dir.path}/key.pem');
    server = await SecureServerSocket.bind('127.0.0.1', 0, context)
      ..listen(
        (client) {
          client.write(':irc.selfsigned.test NOTICE * :hello\r\n');
        },
        onError: (_) {}, // Handshakes the client aborts end up here.
      );

    final der = await Process.run('openssl', [
      'x509',
      '-in',
      '${dir.path}/cert.pem',
      '-outform',
      'DER',
    ], stdoutEncoding: null);
    fingerprint = certificateFingerprint(der.stdout as List<int>);
  });

  tearDownAll(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  test('rejects an untrusted self-signed certificate with its details', () {
    final transport = SocketIrcTransport(
      '127.0.0.1',
      server.port,
      useTls: true,
    );
    expect(
      transport.connect(),
      throwsA(
        isA<UntrustedCertificateException>()
            .having((e) => e.certificate.sha256, 'sha256', fingerprint)
            .having((e) => e.certificate.isSelfSigned, 'self-signed', isTrue)
            .having(
              (e) => e.certificate.subject,
              'subject',
              contains('irc.selfsigned.test'),
            ),
      ),
    );
  });

  test('connects once that exact certificate is trusted', () async {
    final transport = SocketIrcTransport(
      '127.0.0.1',
      server.port,
      useTls: true,
      trustedFingerprints: {fingerprint},
    );
    await transport.connect();
    expect(await transport.lines.first, ':irc.selfsigned.test NOTICE * :hello');
    await transport.close();
  });

  test('a different trusted fingerprint does not help', () {
    final transport = SocketIrcTransport(
      '127.0.0.1',
      server.port,
      useTls: true,
      trustedFingerprints: {'00:11:22'},
    );
    expect(transport.connect(), throwsA(isA<UntrustedCertificateException>()));
  });

  test('fingerprint format is colon-separated upper-case hex', () {
    expect(
      certificateFingerprint([1, 2, 3]),
      matches(RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$')),
    );
  });
}
