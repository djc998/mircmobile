import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/ui/empty_state.dart';
import 'package:irc_client/core/ui/room_card.dart';
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

Future<FakeTransport> launch(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transport = FakeTransport();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
        transportFactoryProvider.overrideWithValue(
          (host, port, {required useTls, trustedFingerprints = const {}}) =>
              transport,
        ),
      ],
      child: const IrcApp(),
    ),
  );
  return transport;
}

Future<void> connect(WidgetTester tester, FakeTransport transport) async {
  await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
  await tester.tap(find.text('Libera.Chat'));
  await tester.pumpAndSettle();
  transport.incoming
    ..add(':s 001 me :Welcome')
    ..add(':s 005 me NETWORK=Libera.Chat :ok');
  await tester.pumpAndSettle();
}

void sendRooms(FakeTransport transport) => transport.incoming
  ..add(':s 321 me Channel :Users Name')
  ..add(':s 322 me #help 1520 :New to IRC? Ask anything here.')
  ..add(':s 322 me #linux 891 :General Linux help and chat.')
  ..add(':s 322 me #chillhop 87 :Lo-fi beats')
  ..add(':s 322 me #coffee 24 :Small, slow, friendly.')
  ..add(':s 323 me :End');

void main() {
  testWidgets('welcome: three steps, advanced options folded away', (
    tester,
  ) async {
    await launch(tester, const Size(390, 1400));
    expect(find.text('Welcome to IRCage'), findsOneWidget);
    expect(
      find.text('Chat rooms, the way they used to be. Only better.'),
      findsOneWidget,
    );
    expect(find.text('Pick a nickname'), findsOneWidget);
    expect(find.text('Choose a network'), findsOneWidget);
    expect(find.text('Find your first room'), findsOneWidget);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Step 3'), findsOneWidget);
    handle.dispose();
    expect(
      find.widgetWithText(TextField, 'Rooms to join (optional)'),
      findsNothing,
    );
    await tester.ensureVisible(find.text('Advanced options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Advanced options'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Rooms to join (optional)'),
      findsOneWidget,
    );
  });

  testWidgets('step 3: Rooms home sends you to Discover; categories', (
    tester,
  ) async {
    final transport = await launch(tester, const Size(390, 844));
    await connect(tester, transport);
    // No rooms yet: Rooms home points to Discover.
    expect(find.text('Find your first room'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Discover rooms'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Discover'), findsWidgets);
    expect(find.byType(SkeletonList), findsOneWidget);
    sendRooms(transport);
    await tester.pumpAndSettle();
    expect(find.byType(RoomCard), findsNWidgets(4));
    expect(find.widgetWithText(TextField, 'Search 4 rooms'), findsOneWidget);
    // Popular is sorted by size.
    expect(
      tester.getTopLeft(find.text('#help')).dy,
      lessThan(tester.getTopLeft(find.text('#linux')).dy),
    );

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Music'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Music'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomCard), findsOneWidget);
    expect(find.text('#chillhop'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Gaming'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Gaming'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No Gaming rooms match'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Popular'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Popular'));
    await tester.pumpAndSettle();

    // Filters: favorites, size and sort, with a count on the button.
    await tester.tap(find.byTooltip('Filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50+ people'));
    await tester.tap(find.text('A–Z'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsWidgets); // badge
    expect(find.text('#coffee'), findsNothing);
    expect(
      tester.getTopLeft(find.text('#chillhop')).dy,
      lessThan(tester.getTopLeft(find.text('#help')).dy),
    );
  });

  testWidgets('preview sheet; Join becomes Open once you are in', (
    tester,
  ) async {
    final transport = await launch(tester, const Size(390, 844));
    await connect(tester, transport);
    await tester.tap(find.text('Discover'));
    await tester.pump();
    sendRooms(transport);
    await tester.pumpAndSettle();

    await tester.tap(find.text('#linux'));
    await tester.pumpAndSettle();
    expect(find.text('891 people here now'), findsOneWidget);
    expect(find.text('Tech'), findsWidgets);
    expect(find.text('General Linux help and chat.'), findsWidgets);
    await tester.tap(find.text('Join room'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'JOIN #linux');
    transport.incoming.add(':me!u@h JOIN #linux');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '#linux'), findsOneWidget);

    // Back on Discover, #linux says Open and opens without joining again.
    await tester.tap(find.byTooltip('Back to rooms'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    final linux = find.widgetWithText(RoomCard, '#linux');
    expect(
      find.descendant(of: linux, matching: find.text('Open')),
      findsOneWidget,
    );
    final sent = transport.written.length;
    await tester.tap(find.descendant(of: linux, matching: find.text('Open')));
    await tester.pumpAndSettle();
    expect(transport.written.length, sent);
    expect(find.widgetWithText(AppBar, '#linux'), findsOneWidget);
  });

  testWidgets('two columns of cards on wide screens', (tester) async {
    final transport = await launch(tester, const Size(1280, 800));
    await connect(tester, transport);
    await tester.tap(find.text('Discover rooms'));
    await tester.pump();
    sendRooms(transport);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.widgetWithText(RoomCard, '#help')).dy,
      tester.getTopLeft(find.widgetWithText(RoomCard, '#linux')).dy,
    );
    expect(
      tester.getTopLeft(find.widgetWithText(RoomCard, '#linux')).dx,
      greaterThan(tester.getTopLeft(find.widgetWithText(RoomCard, '#help')).dx),
    );
  });
}
