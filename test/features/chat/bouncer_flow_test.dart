import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:material_ui/material_ui.dart';

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

const _caps = 'batch message-tags server-time soju.im/bouncer-networks';

void main() {
  testWidgets('a soju bouncer opens each of its networks', (tester) async {
    final transports = <_Transport>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportFactoryProvider.overrideWithValue((
            host,
            port, {
            required useTls,
            trustedFingerprints = const {},
          }) {
            final t = _Transport();
            transports.add(t);
            return t;
          }),
        ],
        child: const IrcApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IrcApp)),
    );
    final controller = container.read(chatControllerProvider.notifier);
    unawaited(
      controller.connect(
        const IrcConnectionConfig(
          host: 'bnc.test',
          port: 6667,
          useTls: false,
          nick: 'me',
          serverPassword: 'secret',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bouncer = transports.single;
    bouncer.incoming
      ..add(':bnc CAP * LS :$_caps')
      ..add(':bnc CAP * ACK :$_caps')
      ..add(':bnc 001 me :Welcome to soju')
      ..add('BATCH +n soju.im/bouncer-networks')
      ..add(r'@batch=n BOUNCER NETWORK 1 name=Libera\sChat;state=connected')
      ..add('@batch=n BOUNCER NETWORK 2 name=OFTC;state=connected')
      ..add('BATCH -n');
    await tester.pumpAndSettle();

    // One connection per network, each bound to it, with the same login.
    expect(transports, hasLength(3));
    final libera = transports[1];
    libera.incoming
      ..add(':bnc CAP * LS :$_caps')
      ..add(':bnc CAP * ACK :$_caps');
    await tester.pumpAndSettle();
    expect(libera.written, contains('PASS secret'));
    expect(libera.written, contains('BOUNCER BIND 1'));
    libera.incoming
      ..add(':bnc 001 me :Welcome')
      ..add(':bnc 005 me NETWORK=Libera.Chat BOUNCER_NETID=1 :ok');
    await tester.pumpAndSettle();
    // Bound connections don't list networks themselves.
    expect(libera.written, isNot(contains('BOUNCER LISTNETWORKS')));

    final networks = container.read(chatControllerProvider).networks;
    expect(
      networks.keys,
      containsAll(['bnc.test', 'bnc.test/1', 'bnc.test/2']),
    );
    expect(networks['bnc.test']!.label, 'bnc.test (bouncer)');
    expect(networks['bnc.test/1']!.label, 'Libera.Chat');

    // Listing again (or a change) doesn't open a network twice.
    bouncer.incoming.add('BOUNCER NETWORK 2 state=disconnected');
    await tester.pumpAndSettle();
    expect(transports, hasLength(3));

    // A network added on the bouncer later opens too.
    bouncer.incoming.add('BOUNCER NETWORK 3 name=EFnet;state=connecting');
    await tester.pumpAndSettle();
    expect(transports, hasLength(4));

    await tester.pumpWidget(const SizedBox());
  });
}
