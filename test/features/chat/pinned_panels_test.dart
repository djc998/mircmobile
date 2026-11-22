import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:material_ui/material_ui.dart';

class FakeTransport implements IrcTransport {
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
  Future<FakeTransport> pumpApp(
    WidgetTester tester,
    KeyValueStore store, {
    required Size size,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          transportFactoryProvider.overrideWithValue(
            (host, port, {required useTls, trustedFingerprints = const {}}) =>
                transport,
          ),
        ],
        child: const IrcApp(),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #chat')
      ..add(':s 353 me = #chat :@me alice bob')
      ..add(':s 366 me #chat :End of /NAMES list.');
    await tester.pumpAndSettle();
    return transport;
  }

  testWidgets('on wide screens people and chats are pinned at the sides', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await pumpApp(tester, store, size: const Size(1400, 900));

    // Both panels are open without tapping anything.
    expect(find.text('3 people in #chat'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.byTooltip('Hide servers and chats'), findsOneWidget);
    // "#chat" is in the title and in the pinned chat list.
    final withChats = find.text('#chat').evaluate().length;
    expect(withChats, greaterThanOrEqualTo(2));

    // Hide both.
    await tester.tap(find.byTooltip('Hide people'));
    await tester.tap(find.byTooltip('Hide servers and chats'));
    await tester.pumpAndSettle();
    expect(find.text('3 people in #chat'), findsNothing);
    expect(find.byTooltip('Show people'), findsOneWidget);
    expect(find.byTooltip('Show servers and chats'), findsOneWidget);
    expect(find.text('#chat').evaluate().length, lessThan(withChats));
    expect(store.getString('pinPeoplePanel'), 'false');
    expect(store.getString('pinChatsPanel'), 'false');

    // Show them again.
    await tester.tap(find.byTooltip('Show people'));
    await tester.tap(find.byTooltip('Show servers and chats'));
    await tester.pumpAndSettle();
    expect(find.text('3 people in #chat'), findsOneWidget);
    expect(store.getString('pinPeoplePanel'), 'true');
  });

  testWidgets('the choice is remembered on the next launch', (tester) async {
    final store = MemoryKeyValueStore();
    await store.setString('pinPeoplePanel', 'false');
    await pumpApp(tester, store, size: const Size(1400, 900));
    expect(find.text('3 people in #chat'), findsNothing);
    expect(find.byTooltip('Show people'), findsOneWidget);
  });

  testWidgets('on phones the panels slide out instead', (tester) async {
    final store = MemoryKeyValueStore();
    await pumpApp(tester, store, size: const Size(400, 800));
    expect(find.text('3 people in #chat'), findsNothing);
    expect(find.byTooltip('Hide servers and chats'), findsNothing);
    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    expect(find.text('3 people in #chat'), findsOneWidget);
  });
}
