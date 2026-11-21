import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_transport.dart';

void main() {
  test('a dropped connection ends the line stream without crashing', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((client) {
      // Drop the connection straight away, like a network blip.
      client.destroy();
    });

    final transport = SocketIrcTransport(
      '127.0.0.1',
      server.port,
      useTls: false,
    );
    await transport.connect();
    final ended = Completer<void>();
    transport.lines.listen(
      (_) {},
      onError: (Object _) {},
      onDone: ended.complete,
    );

    // Keep writing into the dead connection, as the keep-alive ping does.
    // None of these may throw or leave an unhandled error behind.
    for (var i = 0; i < 50; i++) {
      transport.writeLine('PING :keepalive');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    await ended.future.timeout(const Duration(seconds: 5));
    transport.writeLine('PING :after close');
    await transport.close();
  });
}
