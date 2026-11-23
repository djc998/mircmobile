import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/connection/data/custom_networks.dart';
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

void main() {
  group('parseServer', () {
    test('a plain address', () {
      final p = parseServer('  irc.example.net ')!;
      expect(p.host, 'irc.example.net');
      expect(p.port, isNull);
      expect(p.tls, isNull);
    });

    test('address with a port, +port and irc:// links', () {
      expect(parseServer('irc.example.net:6667')!.port, 6667);
      final plus = parseServer('irc.example.net:+7000')!;
      expect((plus.port, plus.tls), (7000, true));
      final link = parseServer('ircs://irc.example.net:6697/#room')!;
      expect((link.host, link.port, link.tls), ('irc.example.net', 6697, true));
      expect(parseServer('irc://10.0.0.2')!.host, '10.0.0.2');
    });

    test('rejects junk', () {
      expect(parseServer(''), isNull);
      expect(parseServer('irc example net'), isNull);
      expect(parseServer('irc.example.net:99999'), isNull);
    });
  });

  test('saves, edits and removes networks with their password', () async {
    final store = MemoryKeyValueStore();
    final secrets = MemorySecretStore();
    final container = ProviderContainer(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store),
        secretStoreProvider.overrideWithValue(secrets),
      ],
    );
    addTearDown(container.dispose);
    final c = container.read(customNetworksProvider.notifier);

    await c.save(
      const CustomNetwork(host: 'bnc.example.net', name: 'My bouncer'),
      password: 'me/libera:secret',
    );
    expect(
      container.read(customNetworksProvider).single.displayName,
      'My bouncer',
    );
    expect(await c.password('bnc.example.net'), 'me/libera:secret');

    // Edited to a new address: the password moves with it.
    await c.save(
      const CustomNetwork(host: 'bnc2.example.net', port: 6667, useTls: false),
      previousHost: 'bnc.example.net',
    );
    final n = container.read(customNetworksProvider).single;
    expect((n.host, n.port, n.useTls), ('bnc2.example.net', 6667, false));
    expect(n.displayName, 'bnc2.example.net');
    expect(n.network.description, 'port 6667 · not encrypted');
    expect(await c.password('bnc2.example.net'), 'me/libera:secret');
    expect(await c.password('bnc.example.net'), isNull);

    // Read back after a restart.
    final again = ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );
    addTearDown(again.dispose);
    expect(again.read(customNetworksProvider).single.host, 'bnc2.example.net');

    await c.remove('BNC2.example.net');
    expect(container.read(customNetworksProvider), isEmpty);
    expect(await c.password('bnc2.example.net'), isNull);
  });

  testWidgets('add your own network and connect to it', (tester) async {
    final transport = _Transport();
    String? host;
    int? port;
    bool? tls;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportFactoryProvider.overrideWithValue((
            h,
            p, {
            required useTls,
            trustedFingerprints = const {},
          }) {
            (host, port, tls) = (h, p, useTls);
            return transport;
          }),
        ],
        child: const IrcApp(),
      ),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.ensureVisible(find.text('Add your own network'));
    await tester.tap(find.text('Add your own network'));
    await tester.pumpAndSettle();

    // Nothing typed: the address is asked for.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a server address'), findsOneWidget);

    // host:port fills in the port; turning TLS off keeps a typed port.
    await tester.enterText(
      find.widgetWithText(TextField, 'Server address'),
      'irc.example.net:7000',
    );
    await tester.pump();
    expect(find.widgetWithText(TextField, '7000'), findsOneWidget);
    await tester.tap(find.text('Secure connection (TLS)'));
    await tester.pump();
    expect(find.widgetWithText(TextField, '7000'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Name (optional)'),
      'Home',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Server password (optional)'),
      'hunter2',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();

    expect((host, port, tls), ('irc.example.net', 7000, false));
    expect(transport.written, contains('PASS hunter2'));
    expect(transport.written, contains('NICK me'));
  });

  testWidgets('added networks are listed and can be edited and removed', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await store.setString(
      'customNetworks',
      '[{"host":"irc.example.net","name":"Home","port":6697,"useTls":true}]',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const IrcApp(),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('irc.example.net · port 6697'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);

    await tester.ensureVisible(find.byTooltip('Edit Home'));
    await tester.tap(find.byTooltip('Edit Home'));
    await tester.pumpAndSettle();
    expect(find.text('Edit network'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Home'), 'Work');
    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit Work'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Remove'));
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsNothing);
    expect(store.getString('customNetworks'), '[]');
  });

  testWidgets('a built-in network cannot be added twice', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: IrcApp()));
    await tester.ensureVisible(find.text('Add your own network'));
    await tester.tap(find.text('Add your own network'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Server address'),
      'IRC.libera.chat',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(
      find.text('That network is already in the list above'),
      findsOneWidget,
    );
  });
}
