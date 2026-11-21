import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/input_commands.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/irc/isupport.dart';

/// In-memory transport: records written lines and lets tests push lines in.
class FakeTransport implements IrcTransport {
  final StreamController<String> incoming = StreamController<String>();
  final List<String> written = [];
  bool closed = false;
  Exception? failWith;

  @override
  Future<void> connect() async {
    if (failWith != null) throw failWith!;
  }

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) => written.add(line);

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  late FakeTransport transport;
  late IrcClient client;
  late List<IrcEvent> events;

  Future<void> setUpClient({
    IrcConnectionConfig config = const IrcConnectionConfig(
      host: 'irc.test',
      nick: 'me',
      autoJoin: ['#start'],
      autoReconnect: false,
    ),
  }) async {
    transport = FakeTransport();
    client = IrcClient(
      config,
      transportFactory: (host, port, {required useTls}) => transport,
      floodInterval: Duration.zero,
      floodBurst: 1000,
    );
    events = [];
    client.events.listen(events.add);
    await client.connect();
  }

  Future<void> server(String line) async {
    transport.incoming.add(line);
    await pumpEventQueue();
  }

  Future<void> register() async {
    await server(':s CAP * LS :server-time multi-prefix');
    await server(':s CAP * ACK :server-time multi-prefix');
    await server(':s 001 me :Welcome to the test network');
    await server(
      ':s 005 me PREFIX=(qaohv)~&@%+ CHANTYPES=# NETWORK=TestNet ELIST=CMNTU '
      ':are supported',
    );
  }

  tearDown(() async {
    await client.dispose();
  });

  test('registers with CAP, NICK and USER, then autojoins', () async {
    await setUpClient();
    expect(transport.written.take(3), [
      'CAP LS 302',
      'NICK me',
      'USER me 0 * :me',
    ]);
    expect(client.status, IrcConnectionStatus.registering);
    await register();
    expect(transport.written, contains('CAP REQ :server-time multi-prefix'));
    expect(transport.written, contains('CAP END'));
    expect(transport.written, contains('JOIN #start'));
    expect(client.status, IrcConnectionStatus.connected);
    expect(client.networkName, 'TestNet');
    expect(client.capabilities, containsAll(['server-time', 'multi-prefix']));
    expect(events.whereType<RegisteredEvent>().single.nick, 'me');
  });

  test('sends PASS when a server password is set', () async {
    await setUpClient(
      config: const IrcConnectionConfig(
        host: 'h',
        nick: 'me',
        serverPassword: 'secret',
        autoReconnect: false,
      ),
    );
    expect(transport.written, contains('PASS secret'));
  });

  test('answers PING with PONG', () async {
    await setUpClient();
    await server('PING :abc123');
    expect(transport.written.last, 'PONG :abc123');
  });

  test('picks another nick when ours is taken during registration', () async {
    await setUpClient();
    await server(':s 433 * me :Nickname is already in use');
    expect(transport.written.last, 'NICK me_');
    await server(':s 433 * me_ :Nickname is already in use');
    expect(transport.written.last, 'NICK me__');
    await server(':s 001 me__ :Welcome');
    expect(client.nick, 'me__');
  });

  test(
    'tracks joins, names with multi-prefix, modes, parts and quits',
    () async {
      await setUpClient();
      await register();
      await server(':me!u@h JOIN #chat');
      expect(client.channel('#chat'), isNotNull);
      expect(events.whereType<JoinEvent>().last.isSelf, isTrue);

      await server(':s 332 me #chat :Welcome to #chat');
      await server(':s 353 me = #chat :@+alice +bob me carol!c@host');
      await server(':s 366 me #chat :End of /NAMES list.');
      final chat = client.channel('#CHAT')!;
      expect(chat.topic, 'Welcome to #chat');
      expect(chat.members.keys, containsAll(['alice', 'bob', 'me', 'carol']));
      expect(chat.members['alice']!.prefixes, '@+');
      expect(chat.members['carol']!.nick, 'carol');

      await server(':alice!a@h MODE #chat +o-v bob bob');
      expect(chat.members['bob']!.prefixes, '@');

      await server(':dave!d@h JOIN #chat');
      expect(chat.members, contains('dave'));
      await server(':dave!d@h PART #chat :bye');
      expect(chat.members, isNot(contains('dave')));

      await server(':bob!b@h NICK robert');
      expect(chat.members['robert']!.prefixes, '@');

      await server(':robert!b@h QUIT :Quit: gone');
      expect(chat.members, isNot(contains('robert')));
      expect(events.whereType<QuitEvent>().last.channels, ['#chat']);

      await server(':alice!a@h KICK #chat me :out');
      expect(client.channel('#chat'), isNull);
      expect(events.whereType<PartEvent>().last.kickedBy, 'alice');
    },
  );

  test('channel messages, private messages and actions', () async {
    await setUpClient();
    await register();
    await server(
      '@time=2026-11-21T12:00:00.000Z :alice!a@h PRIVMSG #chat :hello all',
    );
    final m = events.whereType<MessageEvent>().last;
    expect(m.target, '#chat');
    expect(m.sender, 'alice');
    expect(m.text, 'hello all');
    expect(m.isOwn, isFalse);
    expect(m.time, DateTime.utc(2026, 11, 21, 12));

    await server(':alice!a@h PRIVMSG me :psst');
    expect(events.whereType<MessageEvent>().last.target, 'alice');

    await server(':alice!a@h PRIVMSG #chat :\x01ACTION waves\x01');
    final action = events.whereType<MessageEvent>().last;
    expect(action.isAction, isTrue);
    expect(action.text, 'waves');

    await server(':alice!a@h PRIVMSG @#chat :ops only');
    expect(events.whereType<MessageEvent>().last.target, '#chat');
  });

  test('replies to CTCP VERSION and does not show it as a message', () async {
    await setUpClient();
    await register();
    final before = events.whereType<MessageEvent>().length;
    await server(':alice!a@h PRIVMSG me :\x01VERSION\x01');
    expect(transport.written.last, startsWith('NOTICE alice :\x01VERSION '));
    expect(events.whereType<MessageEvent>().length, before);
  });

  test('server notices go to the status window', () async {
    await setUpClient();
    await server(':irc.test NOTICE * :*** Looking up your hostname');
    expect(events.whereType<ServerNoticeEvent>(), isNotEmpty);
    expect(events.whereType<MessageEvent>(), isEmpty);
  });

  test('sending echoes locally unless echo-message is enabled', () async {
    await setUpClient();
    await register();
    client.sendMessage('#chat', 'hi there');
    await pumpEventQueue();
    expect(transport.written.last, 'PRIVMSG #chat :hi there');
    final echo = events.whereType<MessageEvent>().last;
    expect(echo.isOwn, isTrue);
    expect(echo.text, 'hi there');
  });

  test('no local echo with echo-message; server echo is marked own', () async {
    await setUpClient();
    await server(':s CAP * LS :echo-message');
    await server(':s CAP * ACK :echo-message');
    await server(':s 001 me :Welcome');
    client.sendMessage('#chat', 'hi');
    await pumpEventQueue();
    expect(events.whereType<MessageEvent>(), isEmpty);
    await server(':me!u@h PRIVMSG #chat :hi');
    expect(events.whereType<MessageEvent>().single.isOwn, isTrue);
    await server(':me!u@h PRIVMSG bob :private');
    expect(events.whereType<MessageEvent>().last.target, 'bob');
  });

  test('long and multi-line messages are split to fit 512 bytes', () async {
    await setUpClient();
    await register();
    final long = List.generate(200, (i) => 'word$i').join(' ');
    client.sendMessage('#chat', 'first line\n$long');
    final sent = transport.written
        .where((l) => l.startsWith('PRIVMSG'))
        .toList();
    expect(sent.first, 'PRIVMSG #chat :first line');
    expect(sent.length, greaterThan(2));
    for (final line in sent) {
      expect(utf8.encode(line).length, lessThan(512 - 80));
    }
    final rebuilt = sent.skip(1).map((l) => l.split(' :')[1]).join(' ');
    expect(rebuilt, long);
  });

  test('splitUtf8 never cuts a character', () {
    final text = '😀' * 50; // 4 bytes each.
    final parts = IrcClient.splitUtf8(text, 10);
    expect(parts.every((p) => utf8.encode(p).length <= 10), isTrue);
    expect(parts.join(), text);
  });

  test('LIST uses ELIST and collects results', () async {
    await setUpClient();
    await register();
    client.list(minUsers: 10);
    expect(transport.written.last, 'LIST >9');
    await server(':s 321 me Channel :Users  Name');
    await server(':s 322 me #big 120 :[+nt] Big room');
    await server(':s 322 me #small 12 :Small room');
    await server(':s 323 me :End of /LIST');
    final list = events.whereType<ChannelListEvent>().single.entries;
    expect(list.map((e) => e.name), ['#big', '#small']);
    expect(list.first.topic, 'Big room');
    expect(list.first.userCount, 120);
  });

  test('LIST filters locally when ELIST U is unsupported', () async {
    await setUpClient();
    await server(':s 001 me :Welcome');
    client.list(minUsers: 50);
    expect(transport.written.last, 'LIST');
    await server(':s 322 me #a 10 :x');
    await server(':s 322 me #b 60 :y');
    await server(':s 323 me :End');
    expect(
      events.whereType<ChannelListEvent>().single.entries.map((e) => e.name),
      ['#b'],
    );
  });

  test('error numerics are surfaced', () async {
    await setUpClient();
    await register();
    await server(':s 474 me #banned :Cannot join channel (+b)');
    final err = events.whereType<ServerErrorEvent>().last;
    expect(err.code, '474');
    expect(err.target, '#banned');
  });

  test('reconnects with backoff and rejoins channels', () async {
    final transports = <FakeTransport>[];
    client = IrcClient(
      const IrcConnectionConfig(host: 'h', nick: 'me'),
      transportFactory: (host, port, {required useTls}) {
        final t = FakeTransport();
        transports.add(t);
        return t;
      },
      floodInterval: Duration.zero,
      maxReconnectDelay: Duration.zero,
    );
    events = [];
    client.events.listen(events.add);
    await client.connect();
    transport = transports.last;
    await server(':s 001 me :Welcome');
    await server(':me!u@h JOIN #keep');

    await transports.last.incoming.close();
    await pumpEventQueue();
    expect(
      events.whereType<StatusChangedEvent>().map((e) => e.status),
      contains(IrcConnectionStatus.reconnecting),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(transports.length, 2);
    transport = transports.last;
    await server(':s 001 me :Welcome back');
    expect(transport.written, contains('JOIN #keep'));
  });

  test('connection failure reports an error', () async {
    transport = FakeTransport()..failWith = Exception('refused');
    client = IrcClient(
      const IrcConnectionConfig(host: 'h', nick: 'me', autoReconnect: false),
      transportFactory: (host, port, {required useTls}) => transport,
    );
    events = [];
    client.events.listen(events.add);
    await client.connect();
    await pumpEventQueue();
    expect(events.whereType<ServerErrorEvent>().single.code, 'CONNECT');
    expect(client.status, IrcConnectionStatus.disconnected);
  });

  test('SASL outcome is reported', () async {
    await setUpClient(
      config: const IrcConnectionConfig(
        host: 'h',
        nick: 'me',
        sasl: SaslCredentials(account: 'me', password: 'pw'),
        autoReconnect: false,
      ),
    );
    await server(':s CAP * LS :sasl');
    await server(':s CAP * ACK :sasl');
    await server('AUTHENTICATE +');
    await server(':s 903 me :SASL authentication successful');
    expect(events.whereType<SaslEvent>().single.outcome, SaslOutcome.success);
  });

  test('backoff doubles and caps', () {
    const max = Duration(minutes: 5);
    expect(IrcClient.reconnectDelay(0, max), const Duration(seconds: 2));
    expect(IrcClient.reconnectDelay(1, max), const Duration(seconds: 4));
    expect(IrcClient.reconnectDelay(3, max), const Duration(seconds: 16));
    expect(IrcClient.reconnectDelay(20, max), max);
  });

  group('input commands', () {
    setUp(() async {
      await setUpClient();
      await register();
    });

    test('plain text goes to the open conversation', () {
      expect(runInput(client, 'hello', target: '#chat'), isA<InputSent>());
      expect(transport.written.last, 'PRIVMSG #chat :hello');
    });

    test('plain text in the status window is an error', () {
      expect(runInput(client, 'hello'), isA<InputError>());
    });

    test('// sends a literal slash', () {
      runInput(client, '//shrug', target: '#chat');
      expect(transport.written.last, 'PRIVMSG #chat :/shrug');
    });

    test('/join adds # when missing, supports keys', () {
      runInput(client, '/join flutter');
      expect(transport.written.last, 'JOIN #flutter');
      runInput(client, '/j #secret key');
      expect(transport.written.last, 'JOIN #secret key');
    });

    test('/part uses the current channel and a reason', () {
      runInput(client, '/part see you', target: '#chat');
      expect(transport.written.last, 'PART #chat :see you');
    });

    test('/me, /msg, /nick, /topic, /whois, /quote', () {
      runInput(client, '/me waves', target: '#chat');
      expect(transport.written.last, 'PRIVMSG #chat :\x01ACTION waves\x01');
      runInput(client, '/msg bob hi bob');
      expect(transport.written.last, 'PRIVMSG bob :hi bob');
      runInput(client, '/nick newme');
      expect(transport.written.last, 'NICK newme');
      runInput(client, '/topic New topic here', target: '#chat');
      expect(transport.written.last, 'TOPIC #chat :New topic here');
      runInput(client, '/whois bob');
      expect(transport.written.last, 'WHOIS bob');
      runInput(client, '/quote MODE #chat +m');
      expect(transport.written.last, 'MODE #chat +m');
    });

    test('/query opens a conversation', () {
      final r = runInput(client, '/query bob');
      expect(r, isA<InputOpenQuery>());
      expect((r as InputOpenQuery).nick, 'bob');
    });

    test('unknown command and bad usage give errors', () {
      expect(runInput(client, '/bogus'), isA<InputError>());
      expect(runInput(client, '/join'), isA<InputError>());
      expect(runInput(client, '/me hi'), isA<InputError>());
    });
  });

  group('ISupport', () {
    test('parses PREFIX, CHANTYPES and casemapping', () {
      final s = ISupport()
        ..apply(['PREFIX=(ov)@+', 'CHANTYPES=#&', 'CASEMAPPING=rfc1459']);
      expect(s.prefixes, {'o': '@', 'v': '+'});
      expect(s.isChannel('&local'), isTrue);
      expect(s.isChannel('nick'), isFalse);
      expect(s.fold('Nick[A]~'), 'nick{a}^');
    });

    test('negated tokens are removed', () {
      final s = ISupport()
        ..apply(['ELIST=U'])
        ..apply(['-ELIST']);
      expect(s.supportsElist('U'), isFalse);
    });
  });
}
