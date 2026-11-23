import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
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

const _caps = 'batch message-tags soju.im/bouncer-networks';

void main() {
  late _Transport transport;
  late IrcClient client;
  var started = false;
  late List<IrcEvent> events;

  Future<void> server(String line) async {
    transport.incoming.add(line);
    await pumpEventQueue();
  }

  Future<void> connect({
    String? network,
    String caps = _caps,
    String? username,
    String? password,
  }) async {
    transport = _Transport();
    started = true;
    client = IrcClient(
      IrcConnectionConfig(
        host: 'bnc.test',
        nick: 'me',
        autoReconnect: false,
        bouncerNetwork: network,
        username: username,
        serverPassword: password,
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
  }

  tearDown(() async {
    if (started) await client.dispose();
    started = false;
  });

  test('asks for soju bouncer networks', () {
    expect(defaultWantedCaps, contains('soju.im/bouncer-networks'));
    expect(defaultWantedCaps, contains('soju.im/bouncer-networks-notify'));
  });

  test('a bound connection sends BIND just before CAP END', () async {
    await connect(network: '7');
    final bind = transport.written.indexOf('BOUNCER BIND 7');
    expect(bind, greaterThan(-1));
    expect(transport.written[bind + 1], 'CAP END');
    await server(':s 001 me :Welcome');
    expect(transport.written, isNot(contains('BOUNCER LISTNETWORKS')));
  });

  test('a bouncer network logs in with SASL so soju allows BIND', () async {
    await connect(
      network: '1',
      caps: '$_caps sasl',
      username: 'tester',
      password: 'pw',
    );
    expect(transport.written, contains('AUTHENTICATE PLAIN'));
    expect(transport.written, isNot(contains('BOUNCER BIND 1')));
    await server('AUTHENTICATE +');
    await server(':s 903 * :SASL authentication successful');
    final bind = transport.written.indexOf('BOUNCER BIND 1');
    expect(bind, greaterThan(transport.written.indexOf('AUTHENTICATE PLAIN')));
    expect(transport.written[bind + 1], 'CAP END');
  });

  test("soju's FAIL replies are shown", () async {
    await connect(network: '1');
    await server(
      ':s FAIL BOUNCER ACCOUNT_REQUIRED BIND :Authentication needed',
    );
    final error = events.whereType<ServerErrorEvent>().single;
    expect(error.code, 'BOUNCER ACCOUNT_REQUIRED');
    expect(error.text, 'Authentication needed');
  });

  test('no BIND when the server is not a soju bouncer', () async {
    await connect(network: '7', caps: 'batch message-tags');
    expect(transport.written, isNot(contains('BOUNCER BIND 7')));
    expect(client.isBouncer, isFalse);
  });

  test("the bouncer's own connection lists and follows its networks", () async {
    await connect();
    await server(':s 001 me :Welcome');
    expect(transport.written, contains('BOUNCER LISTNETWORKS'));
    await server(':s BATCH +n soju.im/bouncer-networks');
    const attrs = [
      r'name=Libera\sChat',
      'state=connected',
      'host=irc.libera.chat',
      'nickname=me',
    ];
    await server('@batch=n :s BOUNCER NETWORK 1 ${attrs.join(';')}');
    await server(
      '@batch=n :s BOUNCER NETWORK 2 host=irc.oftc.net;state=connecting',
    );
    await server(':s BATCH -n');
    var listed = events.whereType<BouncerNetworksEvent>().single.networks;
    expect(listed.keys, ['1', '2']);
    expect(listed['1']!.name, 'Libera Chat');
    expect(listed['2']!.name, 'irc.oftc.net');
    expect(listed['2']!.state, 'connecting');

    // Changes come one network at a time, with only what changed.
    await server(':s BOUNCER NETWORK 2 state=connected;name=OFTC');
    await server(':s BOUNCER NETWORK 1 nickname=');
    await server(':s BOUNCER NETWORK 1 *');
    listed = events.whereType<BouncerNetworksEvent>().last.networks;
    expect(listed.keys, ['2']);
    expect(listed['2']!.attributes, {
      'host': 'irc.oftc.net',
      'state': 'connected',
      'name': 'OFTC',
    });
  });

  test('network keys', () {
    expect(
      const IrcConnectionConfig(host: 'BNC.test', nick: 'me').networkKey,
      'bnc.test',
    );
    expect(
      const IrcConnectionConfig(
        host: 'BNC.test',
        nick: 'me',
        bouncerNetwork: '3',
      ).networkKey,
      'bnc.test/3',
    );
  });
}
