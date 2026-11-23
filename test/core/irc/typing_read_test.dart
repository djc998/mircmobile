import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';

class _Transport implements IrcTransport {
  final StreamController<String> incoming = StreamController<String>();
  final List<String> written = [];

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) => written.add(line);

  @override
  Future<void> close() async {}
}

void main() {
  late _Transport transport;
  late IrcClient client;
  late List<IrcEvent> events;

  Future<void> server(String line) async {
    transport.incoming.add(line);
    await pumpEventQueue();
  }

  Future<void> connect(String caps) async {
    transport = _Transport();
    client = IrcClient(
      const IrcConnectionConfig(
        host: 'irc.test',
        nick: 'me',
        autoReconnect: false,
      ),
      transportFactory: (
        host,
        port, {
        required useTls,
        trustedFingerprints = const {},
      }) => transport,
      floodInterval: Duration.zero,
      floodBurst: 1000,
    );
    events = [];
    client.events.listen(events.add);
    await client.connect();
    await server(':s CAP * LS :$caps');
    await server(':s CAP * ACK :$caps');
    await server(':s 001 me :Welcome');
  }

  tearDown(() => client.dispose());

  test('typing goes out as a TAGMSG, only with message tags', () async {
    await connect('batch');
    client.sendTyping('#chat', 'active');
    expect(transport.written.where((l) => l.contains('TAGMSG')), isEmpty);
    await client.dispose();

    await connect('message-tags');
    client
      ..sendTyping('#chat', 'active')
      ..sendTyping('bob', 'done');
    expect(transport.written, contains('@+typing=active TAGMSG #chat'));
    expect(transport.written, contains('@+typing=done TAGMSG bob'));
  });

  test("others' typing in rooms and private chats; not our own", () async {
    await connect('message-tags');
    await server('@+typing=active :bob!b@h TAGMSG #chat');
    await server('@+typing=paused :ann!a@h TAGMSG me');
    await server('@+typing=active :me!u@h TAGMSG #chat');
    await server('@+react=x :bob!b@h TAGMSG #chat');
    final typing = events.whereType<TypingEvent>().toList();
    expect(
      [for (final t in typing) (t.target, t.nick, t.state)],
      [('#chat', 'bob', 'active'), ('ann', 'ann', 'paused')],
    );
  });

  test(
    'read markers: sent with a timestamp, received from the server',
    () async {
      await connect('message-tags');
      client.markRead('#chat', DateTime.utc(2026, 11, 23, 10));
      expect(transport.written.where((l) => l.startsWith('MARKREAD')), isEmpty);
      await client.dispose();

      await connect('message-tags draft/read-marker');
      client.markRead('#chat', DateTime.utc(2026, 11, 23, 10));
      expect(
        transport.written,
        contains('MARKREAD #chat timestamp=2026-11-23T10:00:00.000Z'),
      );
      // Microseconds (as DateTime.now() has) are cut to milliseconds.
      client.markRead('bob', DateTime.utc(2026, 11, 23, 10, 0, 0, 452, 949));
      expect(
        transport.written,
        contains('MARKREAD bob timestamp=2026-11-23T10:00:00.452Z'),
      );
      await server(':s MARKREAD #chat timestamp=2026-11-23T11:00:00.000Z');
      await server(':s MARKREAD bob *');
      final markers = events.whereType<ReadMarkerEvent>().toList();
      expect(markers.first.target, '#chat');
      expect(markers.first.readUntil, DateTime.utc(2026, 11, 23, 11));
      expect(markers.last.readUntil, isNull);
    },
  );
}
