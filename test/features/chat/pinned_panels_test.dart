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

  testWidgets('on phones the title bar leaves room for the chat name', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    final transport = await pumpApp(tester, store, size: const Size(375, 800));

    // Only People stays up top in a room: no ⋮ menu, no global buttons.
    expect(find.byTooltip('People'), findsOneWidget);
    expect(find.byTooltip('Show menu'), findsNothing);
    expect(find.byTooltip('Browse rooms'), findsNothing);
    expect(find.byTooltip('New private message'), findsNothing);
    expect(find.byTooltip('Join a room'), findsNothing);
    expect(find.byTooltip('Add to favorites'), findsNothing);
    // So the name gets nearly the whole bar.
    expect(tester.getTopLeft(find.byTooltip('People')).dx, greaterThan(300));

    // Tapping the name opens the room's info sheet.
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.text('People (3)'), findsOneWidget);
    expect(find.text('Room settings'), findsOneWidget);
    expect(find.text('Clear history'), findsOneWidget);
    expect(find.text('Leave room'), findsOneWidget);
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Room settings'), findsNothing); // sheet closed
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from favorites'), findsOneWidget);
    // People from the sheet opens the member list.
    await tester.tap(find.text('People (3)'));
    await tester.pumpAndSettle();
    expect(find.text('3 people in #chat'), findsOneWidget);
    await tester.tapAt(const Offset(10, 400));
    await tester.pumpAndSettle();

    // The drawer has Browse / Message / Join, network options, Appearance.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Browse rooms'), findsOneWidget);
    expect(find.byTooltip('Join a room'), findsOneWidget);
    expect(find.text('Create a room'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.byTooltip('New private message'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'bob');
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();

    // A private chat keeps its call buttons and shows the person's name.
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('bob')),
      findsOneWidget,
    );
    expect(find.byTooltip('Voice call'), findsOneWidget);
    expect(find.byTooltip('Video call'), findsOneWidget);
    expect(find.byTooltip('Show menu'), findsNothing);
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.text('Who is this? (whois)'), findsOneWidget);
    await tester.tap(find.text('Close chat'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('bob')),
      findsNothing,
    );

    // A server's options are on its row in the drawer.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Disconnect from'));
    await tester.pumpAndSettle();
    expect(transport.written.any((l) => l.startsWith('QUIT')), isTrue);
  });

  testWidgets('wider screens can open chat info from the name too', (
    tester,
  ) async {
    final store = MemoryKeyValueStore();
    await pumpApp(tester, store, size: const Size(1400, 900));
    expect(find.byTooltip('Show menu'), findsOneWidget);
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.text('Room settings'), findsOneWidget);
    // People is already a button and a pinned panel here.
    expect(find.text('People (3)'), findsNothing);
  });
}
