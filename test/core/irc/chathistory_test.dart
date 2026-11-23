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

  Future<void> connect({String caps = 'batch server-time message-tags'}) async {
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

  test('asks for chathistory when the server offers it', () async {
    await connect(caps: 'batch server-time message-tags draft/chathistory');
    expect(
      transport.written,
      contains('CAP REQ :server-time message-tags batch draft/chathistory'),
    );
    expect(client.supportsHistory, isTrue);
  });

  test('without the capability, nothing is requested', () async {
    await connect();
    expect(client.supportsHistory, isFalse);
    client.requestHistory('#chat');
    expect(
      transport.written.where((l) => l.startsWith('CHATHISTORY')),
      isEmpty,
    );
  });

  test('requests use timestamps and the server limit (at most 100)', () async {
    await connect(caps: 'batch server-time message-tags draft/chathistory');
    await server(':s 005 me CHATHISTORY=40 :are supported');
    client
      ..requestHistory('#chat')
      ..requestHistory('#chat', after: DateTime.utc(2026, 11, 23, 9, 30))
      ..requestHistoryBefore('bob', DateTime.utc(2026, 11, 22), limit: 50)
      ..requestHistoryTargets(
        DateTime.utc(2026, 11, 22),
        DateTime.utc(2026, 11, 23),
      );
    const targets = 'CHATHISTORY TARGETS timestamp=2026-11-22T00:00:00.000Z';
    expect(transport.written.where((l) => l.startsWith('CHATHISTORY')), [
      'CHATHISTORY LATEST #chat * 40',
      'CHATHISTORY LATEST #chat timestamp=2026-11-23T09:30:00.000Z 40',
      'CHATHISTORY BEFORE bob timestamp=2026-11-22T00:00:00.000Z 50',
      '$targets timestamp=2026-11-23T00:00:00.000Z 40',
    ]);
  });

  test('messages in a history batch are marked, then the batch ends', () async {
    await connect(caps: 'batch server-time message-tags draft/chathistory');
    await server(':s BATCH +h1 chathistory #chat');
    await server(
      '@batch=h1;time=2026-11-23T08:00:00.000Z;msgid=a1 '
      ':bob!b@h PRIVMSG #chat :while you were out',
    );
    await server(
      '@batch=h1;time=2026-11-23T08:01:00.000Z;msgid=a2 '
      ':bob!b@h PRIVMSG #chat :\x01VERSION\x01',
    );
    // Ergo's join/part replay is left out.
    await server(
      '@batch=h1;time=2026-11-23T08:02:00.000Z '
      ':HistServ!HistServ@localhost PRIVMSG #chat :bob joined the channel',
    );
    await server(':s BATCH -h1');
    await server('@msgid=a3 :bob!b@h PRIVMSG #chat :live now');

    final messages = events.whereType<MessageEvent>().toList();
    expect(messages.map((m) => m.sender), isNot(contains('HistServ')));
    expect(messages.first.history, isTrue);
    expect(messages.first.msgid, 'a1');
    expect(messages.first.time, DateTime.utc(2026, 11, 23, 8));
    expect(messages.last.history, isFalse);
    // An old CTCP request is not answered again.
    expect(transport.written.where((l) => l.contains('VERSION')), isEmpty);
    final end = events.whereType<HistoryBatchEvent>().single;
    expect((end.target, end.count, end.failed), ('#chat', 2, false));
  });

  test('TARGETS replies list conversations with their latest time', () async {
    await connect(caps: 'batch server-time message-tags draft/chathistory');
    await server(':s BATCH +t1 draft/chathistory-targets');
    await server(
      '@batch=t1 :s CHATHISTORY TARGETS bob timestamp=2026-11-23T07:00:00.000Z',
    );
    await server(
      '@batch=t1 :s CHATHISTORY TARGETS #chat '
      'timestamp=2026-11-23T06:00:00.000Z',
    );
    await server(':s BATCH -t1');
    final targets = events.whereType<HistoryTargetsEvent>().single.targets;
    expect([for (final t in targets) t.name], ['bob', '#chat']);
    expect(targets.first.latest, DateTime.utc(2026, 11, 23, 7));
  });

  test('a refused request ends as failed', () async {
    await connect(caps: 'batch server-time message-tags draft/chathistory');
    await server(':s FAIL CHATHISTORY INVALID_TARGET LATEST #nope :No such');
    expect(events.whereType<HistoryBatchEvent>().single.failed, isTrue);
  });
}
