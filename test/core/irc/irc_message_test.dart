import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_message.dart';
import 'package:irc_client/core/irc/irc_transport.dart';

void main() {
  group('IrcMessage.parse', () {
    test('command only', () {
      final m = IrcMessage.parse('PING');
      expect(m.command, 'PING');
      expect(m.params, isEmpty);
      expect(m.prefix, isNull);
      expect(m.tags, isEmpty);
    });

    test('lower-case command is normalised', () {
      expect(IrcMessage.parse('privmsg #a :hi').command, 'PRIVMSG');
    });

    test('prefix, middle params and trailing', () {
      final m = IrcMessage.parse(
        ':dan!d@localhost PRIVMSG #chan :Hey what is up! \r\n',
      );
      expect(m.prefix!.nick, 'dan');
      expect(m.prefix!.user, 'd');
      expect(m.prefix!.host, 'localhost');
      expect(m.command, 'PRIVMSG');
      expect(m.params, ['#chan', 'Hey what is up! ']);
      expect(m.trailing, 'Hey what is up! ');
    });

    test('server prefix', () {
      final m = IrcMessage.parse(':irc.example.com 001 nick :Welcome');
      expect(m.prefix!.nick, 'irc.example.com');
      expect(m.prefix!.isServer, isTrue);
      expect(m.numeric, 1);
      expect(m.params, ['nick', 'Welcome']);
    });

    test('nick@host prefix without user', () {
      final p = IrcPrefix.parse('nick@host.example');
      expect(p.nick, 'nick');
      expect(p.user, isNull);
      expect(p.host, 'host.example');
      expect(p.isServer, isFalse);
    });

    test('empty trailing param is kept', () {
      expect(IrcMessage.parse('TOPIC #chan :').params, ['#chan', '']);
    });

    test('trailing may contain colons and leading spaces', () {
      final m = IrcMessage.parse('PRIVMSG #c :  :) a:b');
      expect(m.params.last, '  :) a:b');
    });

    test('multiple spaces between params are tolerated', () {
      final m = IrcMessage.parse(':a!b@c   MODE   #chan  +o   bob');
      expect(m.params, ['#chan', '+o', 'bob']);
    });

    test('last param without colon', () {
      expect(IrcMessage.parse('JOIN #chan').params, ['#chan']);
    });

    test('tags with values, flags and escapes', () {
      final m = IrcMessage.parse(
        r'@time=2026-11-21T10:00:00.000Z;+example.com/flag;msg=a\sb\:c\\d\r\n '
        ':n!u@h PRIVMSG #c :hi',
      );
      expect(m.tags['time'], '2026-11-21T10:00:00.000Z');
      expect(m.tags['+example.com/flag'], '');
      expect(m.tags['msg'], 'a b;c\\d\r\n');
      expect(m.serverTime, DateTime.utc(2026, 11, 21, 10));
    });

    test('unknown escape drops the backslash, trailing backslash dropped', () {
      final m = IrcMessage.parse(r'@a=x\yz;b=end\ CMD');
      expect(m.tags['a'], 'xyz');
      expect(m.tags['b'], 'end');
    });

    test('invalid server-time is ignored', () {
      expect(IrcMessage.parse('@time=nope PING').serverTime, isNull);
    });

    test('numeric getter is null for named commands', () {
      expect(IrcMessage.parse('NOTICE * :hi').numeric, isNull);
      expect(IrcMessage.parse(':s 433 * nick :in use').numeric, 433);
    });

    test('param() returns null when out of range', () {
      final m = IrcMessage.parse('JOIN #a');
      expect(m.param(0), '#a');
      expect(m.param(1), isNull);
    });

    test('missing command throws', () {
      expect(() => IrcMessage.parse(''), throwsA(isA<IrcParseException>()));
      expect(
        () => IrcMessage.parse(':prefix.only'),
        throwsA(isA<IrcParseException>()),
      );
      expect(() => IrcMessage.parse('@a=b'), throwsA(isA<IrcParseException>()));
    });

    test('empty prefix throws', () {
      expect(
        () => IrcMessage.parse(': PING'),
        throwsA(isA<IrcParseException>()),
      );
    });

    test('UTF-8 text survives', () {
      final m = IrcMessage.parse(':a!b@c PRIVMSG #c :héllo 👋 世界');
      expect(m.trailing, 'héllo 👋 世界');
    });
  });

  group('IrcMessage.toLine', () {
    test('adds colon to the last param only when needed', () {
      expect(
        IrcMessage(
          command: 'privmsg',
          params: const ['#c', 'hello world'],
        ).toLine(),
        'PRIVMSG #c :hello world',
      );
      expect(
        IrcMessage(command: 'JOIN', params: const ['#c']).toLine(),
        'JOIN #c',
      );
      expect(
        IrcMessage(command: 'TOPIC', params: const ['#c', '']).toLine(),
        'TOPIC #c :',
      );
      expect(
        IrcMessage(command: 'PRIVMSG', params: const ['#c', ':)']).toLine(),
        'PRIVMSG #c ::)',
      );
    });

    test('rejects spaces in a middle param', () {
      expect(
        () => IrcMessage(command: 'X', params: const ['a b', 'c']).toLine(),
        throwsArgumentError,
      );
    });

    test('round-trips tags, prefix and params', () {
      const line = r'@id=123;msg=a\sb\:c :nick!u@h PRIVMSG #chan :hello there';
      final parsed = IrcMessage.parse(line);
      expect(parsed.toLine(), line);
      expect(IrcMessage.parse(parsed.toLine()).tags, parsed.tags);
    });
  });

  group('IrcLineDecoder', () {
    Future<List<String>> decode(List<List<int>> chunks) =>
        const IrcLineDecoder().bind(Stream.fromIterable(chunks)).toList();

    test('splits on CRLF and LF across chunk boundaries', () async {
      final lines = await decode([
        utf8.encode('PING :a\r\nPRIV'),
        utf8.encode('MSG #c :hi\n'),
        utf8.encode('\r\nNOTICE * :x'),
      ]);
      expect(lines, ['PING :a', 'PRIVMSG #c :hi', 'NOTICE * :x']);
    });

    test('keeps a multi-byte character split across chunks', () async {
      final bytes = utf8.encode('PRIVMSG #c :é\r\n');
      final cut = bytes.indexOf(0xC3) + 1;
      final lines = await decode([bytes.sublist(0, cut), bytes.sublist(cut)]);
      expect(lines, ['PRIVMSG #c :é']);
    });

    test('falls back to Latin-1 for invalid UTF-8', () {
      // 0xE9 is "é" in Latin-1 and invalid on its own in UTF-8.
      final bytes = [...latin1.encode('PRIVMSG #c :caf'), 0xE9, 0x0D, 0x0A];
      expect(IrcLineDecoder.decodeLine(bytes), 'PRIVMSG #c :café');
    });
  });
}
