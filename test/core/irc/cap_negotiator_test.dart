import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/irc_message.dart';

void main() {
  late List<String> sent;
  SaslOutcome? finished;

  CapNegotiator make({SaslCredentials? sasl}) {
    sent = [];
    finished = null;
    return CapNegotiator(
      send: sent.add,
      sasl: sasl,
      wanted: const {'server-time', 'multi-prefix', 'echo-message'},
      onFinished: (o) => finished = o,
    )..start();
  }

  void feed(CapNegotiator cap, String line) =>
      expect(cap.handle(IrcMessage.parse(line)), isTrue);

  test('requests only wanted caps the server offers', () {
    final cap = make();
    expect(sent, ['CAP LS 302']);
    feed(cap, ':s CAP * LS :multi-prefix sasl=PLAIN,EXTERNAL foo');
    expect(sent.last, 'CAP REQ :multi-prefix');
    feed(cap, ':s CAP * ACK :multi-prefix');
    expect(sent.last, 'CAP END');
    expect(cap.enabled, {'multi-prefix'});
    expect(cap.isFinished, isTrue);
    expect(finished, SaslOutcome.notAttempted);
  });

  test('waits for multi-line LS before requesting', () {
    final cap = make();
    feed(cap, ':s CAP * LS * :server-time');
    expect(sent, ['CAP LS 302']);
    feed(cap, ':s CAP * LS :echo-message');
    expect(sent.last, 'CAP REQ :server-time echo-message');
  });

  test('ends immediately when nothing useful is offered', () {
    final cap = make();
    feed(cap, ':s CAP * LS :unrelated');
    expect(sent.last, 'CAP END');
  });

  test('NAK still ends negotiation', () {
    final cap = make();
    feed(cap, ':s CAP * LS :server-time');
    feed(cap, ':s CAP * NAK :server-time');
    expect(sent.last, 'CAP END');
    expect(cap.enabled, isEmpty);
  });

  test('SASL PLAIN success', () {
    final cap = make(
      sasl: const SaslCredentials(account: 'dennis', password: 'hunter2'),
    );
    feed(cap, ':s CAP * LS :sasl=PLAIN server-time');
    expect(sent.last, 'CAP REQ :server-time sasl');
    feed(cap, ':s CAP * ACK :server-time sasl');
    expect(sent.last, 'AUTHENTICATE PLAIN');
    feed(cap, 'AUTHENTICATE +');
    final expected = base64.encode(utf8.encode('dennis\x00dennis\x00hunter2'));
    expect(sent.last, 'AUTHENTICATE $expected');
    feed(cap, ':s 900 me me!u@h dennis :You are now logged in');
    feed(cap, ':s 903 me :SASL authentication successful');
    expect(sent.last, 'CAP END');
    expect(finished, SaslOutcome.success);
  });

  test('SASL failure still ends CAP so registration continues', () {
    final cap = make(
      sasl: const SaslCredentials(account: 'a', password: 'wrong'),
    );
    feed(cap, ':s CAP * LS :sasl');
    feed(cap, ':s CAP * ACK :sasl');
    feed(cap, 'AUTHENTICATE +');
    feed(cap, ':s 904 me :SASL authentication failed');
    expect(sent.last, 'CAP END');
    expect(finished, SaslOutcome.failed);
  });

  test('RPL_SASLMECHS alone is not a failure', () {
    final cap = make(
      sasl: const SaslCredentials(account: 'a', password: 'b'),
    );
    feed(cap, ':s CAP * LS :sasl');
    feed(cap, ':s CAP * ACK :sasl');
    feed(cap, ':s 908 me EXTERNAL :are available SASL mechanisms');
    expect(cap.isFinished, isFalse);
    expect(cap.saslOutcome, SaslOutcome.notAttempted);
  });

  test('SASL is skipped when the server lacks PLAIN', () {
    final cap = make(
      sasl: const SaslCredentials(account: 'a', password: 'b'),
    );
    feed(cap, ':s CAP * LS :sasl=EXTERNAL');
    expect(sent.last, 'CAP END');
    expect(finished, SaslOutcome.unavailable);
  });

  test('servers without CAP (421) end negotiation', () {
    final cap = make();
    feed(cap, ':s 421 * CAP :Unknown command');
    expect(sent.last, 'CAP END');
  });

  test('CAP NEW after registration requests newly offered caps', () {
    final cap = make();
    feed(cap, ':s CAP * LS :multi-prefix');
    feed(cap, ':s CAP * ACK :multi-prefix');
    feed(cap, ':s CAP me NEW :server-time');
    expect(sent.last, 'CAP REQ :server-time');
    feed(cap, ':s CAP me ACK :server-time');
    expect(cap.enabled, containsAll(['multi-prefix', 'server-time']));
    feed(cap, ':s CAP me DEL :server-time');
    expect(cap.enabled, {'multi-prefix'});
  });

  test('saslChunks splits at 400 bytes and pads exact multiples', () {
    expect(CapNegotiator.saslChunks(''), ['+']);
    expect(CapNegotiator.saslChunks('abc'), ['abc']);
    final exact = 'a' * 400;
    expect(CapNegotiator.saslChunks(exact), [exact, '+']);
    final long = 'b' * 450;
    expect(CapNegotiator.saslChunks(long), ['b' * 400, 'b' * 50]);
  });

  test('unrelated messages are not consumed', () {
    final cap = make();
    expect(cap.handle(IrcMessage.parse(':s NOTICE * :hello')), isFalse);
  });
}
