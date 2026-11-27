import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';

/// In-memory transport: records written lines and lets tests push lines in.
class _Transport implements IrcTransport {
  final StreamController<String> incoming = StreamController<String>();
  final List<String> written = [];
  Exception? writeFailsWith;

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) {
    if (writeFailsWith != null) throw writeFailsWith!;
    written.add(line);
  }

  @override
  Future<void> close() async {}
}

/// `IrcClient.checkConnection`: what happens when the app comes back from
/// the background.
void main() {
  late List<_Transport> transports;
  late IrcClient client;
  late List<IrcEvent> events;

  _Transport last() => transports.last;

  Future<void> server(String line) async {
    last().incoming.add(line);
    await pumpEventQueue();
  }

  Future<void> start({bool autoReconnect = true}) async {
    transports = [];
    client = IrcClient(
      IrcConnectionConfig(host: 'h', nick: 'me', autoReconnect: autoReconnect),
      transportFactory:
          (host, port, {required useTls, trustedFingerprints = const {}}) {
            final t = _Transport();
            transports.add(t);
            return t;
          },
      floodInterval: Duration.zero,
      floodBurst: 1000,
      // The default backoff (2 s and up) is long enough that only an
      // immediate reconnect shows up in these tests.
    );
    events = [];
    client.events.listen(events.add);
    await client.connect();
    await server(':s 001 me :Welcome');
    await server(':me!u@h JOIN #keep');
  }

  tearDown(() async {
    await client.dispose();
  });

  List<IrcConnectionStatus> statuses() =>
      events.whereType<StatusChangedEvent>().map((e) => e.status).toList();

  test('a live connection answers the check and stays up', () async {
    await start();
    client.checkConnection(timeout: const Duration(milliseconds: 50));
    expect(last().written.last, 'PING :check-1');

    await server(':s PONG s :check-1');
    expect(events.whereType<ConnectionCheckedEvent>(), hasLength(1));

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(transports, hasLength(1));
    expect(client.status, IrcConnectionStatus.connected);
  });

  test('other traffic does not count as an answer', () async {
    await start();
    client.checkConnection(timeout: const Duration(milliseconds: 50));
    // Lines the socket had buffered before it died.
    await server(':a!u@h PRIVMSG #keep :old news');
    await server(':s PONG s :keepalive');
    expect(events.whereType<ConnectionCheckedEvent>(), isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(statuses(), contains(IrcConnectionStatus.reconnecting));
  });

  test('no answer reconnects at once and rejoins the rooms', () async {
    await start();
    client.checkConnection(timeout: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 60));

    // No 2-second backoff: the new connection is already open.
    expect(transports, hasLength(2));
    await server(':s 001 me :Welcome back');
    expect(last().written, contains('JOIN #keep'));
    expect(client.status, IrcConnectionStatus.connected);
  });

  test('only the automatic rejoin is marked as one', () async {
    await start();
    expect(events.whereType<JoinEvent>().single.isRejoin, isFalse);
    client.checkConnection(timeout: const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await server(':s 001 me :Welcome back');
    await server(':me!u@h JOIN #KEEP');
    await server(':me!u@h JOIN #other');
    await server(':me!u@h PART #keep');
    await server(':me!u@h JOIN #keep');

    final joins = events.whereType<JoinEvent>().skip(1).toList();
    expect(joins.map((e) => e.isRejoin), [true, false, false]);
  });

  test('a write that fails on the dead socket reconnects at once', () async {
    await start();
    last().writeFailsWith = Exception('Broken pipe');
    client.checkConnection();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(transports, hasLength(2));
  });

  test('while waiting to reconnect, it retries now', () async {
    await start();
    await last().incoming.close();
    await pumpEventQueue();
    expect(client.status, IrcConnectionStatus.reconnecting);
    expect(transports, hasLength(1));

    client.checkConnection();
    await pumpEventQueue();
    expect(transports, hasLength(2));
  });

  test('does nothing once disconnected by the user', () async {
    await start();
    await client.disconnect();
    client.checkConnection();
    await pumpEventQueue();
    expect(transports, hasLength(1));
    expect(client.status, IrcConnectionStatus.disconnected);
  });

  test('checks only once at a time', () async {
    await start();
    client
      ..checkConnection(timeout: const Duration(milliseconds: 50))
      ..checkConnection(timeout: const Duration(milliseconds: 50));
    expect(last().written.where((l) => l.startsWith('PING')), hasLength(1));
    await server(':s PONG s :check-1');
  });
}
