import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/app/legal.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/safety/content_filter.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/ui/room_card.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/safety/application/safety_controller.dart';
import 'package:irc_client/features/settings/presentation/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

class _Transport implements IrcTransport {
  final StreamController<String> incoming = StreamController<String>();

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) {}

  @override
  Future<void> close() async {}
}

ChannelListEntry _room(String name, [String topic = '']) =>
    ChannelListEntry(name: name, userCount: 10, topic: topic);

Finder _chatText(String text) => find.descendant(
  of: find.byType(ChatScreen),
  matching: find.textContaining(text, findRichText: true),
);

/// Starts the app, connects to Libera.Chat and joins #chat.
Future<_Transport> _inRoom(
  WidgetTester tester, {
  MemoryKeyValueStore? store,
  http.Client? client,
}) async {
  final transport = _Transport();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(store ?? MemoryKeyValueStore()),
        if (client != null)
          pictureServiceProvider.overrideWithValue(
            PictureService(host: 'https://pics.test', client: client),
          ),
        transportFactoryProvider.overrideWithValue(
          (host, port, {required useTls, trustedFingerprints = const {}}) =>
              transport,
        ),
      ],
      child: const IrcApp(),
    ),
  );
  await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
  await tester.ensureVisible(find.text('Libera.Chat'));
  await tester.tap(find.text('Libera.Chat'));
  await tester.pumpAndSettle();
  transport.incoming
    ..add(':s 001 me :Welcome')
    ..add(':me!u@h JOIN #chat')
    ..add(':s 353 me = #chat :me troll')
    ..add(':s 366 me #chat :End');
  await tester.pumpAndSettle();
  return transport;
}

void main() {
  group('word filter', () {
    test('masks slurs and strong swearing, keeping the first letter', () {
      expect(maskOffensive('this is shit'), 'this is s***');
      expect(maskOffensive('FUCKING hell'), 'F****** hell');
      expect(maskOffensive('you bitch.'), 'you b****.');
      expect(hasOffensive('what the fuck'), isTrue);
    });

    test('leaves ordinary words alone', () {
      for (final ok in [
        'a class assignment',
        'Scunthorpe is a town',
        'spicy food',
        'fire retardant',
        'Philip K. Dick',
        'shiitake mushrooms',
        'cockpit and peacock',
      ]) {
        expect(maskOffensive(ok), ok, reason: ok);
      }
    });

    test('keeps mIRC formatting codes around masked words', () {
      expect(maskOffensive('\x02shit\x02 happens'), '\x02s***\x02 happens');
    });
  });

  group('adult rooms', () {
    test('by name or topic', () {
      expect(isAdultRoom(_room('#sex')), isTrue);
      expect(isAdultRoom(_room('#nsfw-chat')), isTrue);
      expect(isAdultRoom(_room('#chat', 'Adults only, 18+')), isTrue);
      expect(isAdultRoom(_room('#lounge', '\x02XXX\x02 pics')), isTrue);
    });

    test('not ordinary rooms', () {
      expect(isAdultRoom(_room('#linux', 'Linux help')), isFalse);
      expect(isAdultRoom(_room('#essex', 'Essex locals')), isFalse);
      expect(isAdultRoom(_room('#cybersecurity')), isFalse);
    });
  });

  group('terms on first launch', () {
    setUp(() => debugTermsAgreedByDefault = false);
    tearDown(() => debugTermsAgreedByDefault = true);

    testWidgets('must be agreed to before anything else, once', (tester) async {
      final store = MemoryKeyValueStore();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Terms of use'), findsOneWidget);
      expect(find.text('No tolerance for abuse'), findsOneWidget);
      expect(find.text('Welcome to IRCage'), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);

      await tester.tap(find.text('Agree and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to IRCage'), findsOneWidget);
      expect(
        jsonDecode(store.getString('safety')!),
        containsPair('termsAgreed', termsVersion),
      );

      // Next launch: straight to the welcome screen.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Welcome to IRCage'), findsOneWidget);
    });

    testWidgets('new terms are asked for again', (tester) async {
      final store = MemoryKeyValueStore();
      await store.setString('safety', '{"termsAgreed":0}');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Agree and continue'), findsOneWidget);
    });
  });

  testWidgets('messages and topics are masked, unless turned off', (
    tester,
  ) async {
    final transport = await _inRoom(tester);
    transport.incoming
      ..add(':troll!t@h PRIVMSG #chat :this is shit')
      ..add(':troll!t@h TOPIC #chat :fuck this room');
    await tester.pumpAndSettle();
    expect(_chatText('this is s***'), findsOneWidget);
    expect(_chatText('shit'), findsNothing);
    expect(_chatText('f*** this room'), findsWidgets);

    ProviderScope.containerOf(tester.element(find.byType(IrcApp)))
        .read(safetyProvider.notifier)
        .setFilterWords(enabled: false);
    await tester.pumpAndSettle();
    expect(_chatText('this is shit'), findsOneWidget);
  });

  testWidgets('report a message: sent for review and the sender ignored', (
    tester,
  ) async {
    final reports = <Map<String, Object?>>[];
    final client = MockClient((req) async {
      if (req.url.path == '/report') {
        reports.add(jsonDecode(req.body) as Map<String, Object?>);
        return http.Response('{"ok":true}', 201);
      }
      return http.Response('', 404);
    });
    final transport = await _inRoom(tester, client: client);
    transport.incoming.add(':troll!t@h PRIVMSG #chat :buy cheap pills');
    await tester.pumpAndSettle();

    await tester.longPress(_chatText('buy cheap pills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report message'));
    await tester.pumpAndSettle();
    expect(find.textContaining('troll is ignored'), findsOneWidget);
    await tester.tap(find.text('Spam or scam'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(reports.single, {
      'kind': 'message',
      'text': 'buy cheap pills',
      'sender': 'troll',
      'network': 'irc.libera.chat',
      'room': '#chat',
      'reason': 'Spam or scam',
    });
    expect(find.textContaining("it's been reported"), findsOneWidget);
    final controller = ProviderScope.containerOf(
      tester.element(find.byType(IrcApp)),
    ).read(chatControllerProvider.notifier);
    expect(controller.isBlocked('troll'), isTrue);
  });

  testWidgets('your own messages have no Report', (tester) async {
    await _inRoom(tester);
    ProviderScope.containerOf(tester.element(find.byType(IrcApp)))
        .read(chatControllerProvider.notifier)
        .submit('hello there');
    await tester.pumpAndSettle();
    await tester.longPress(_chatText('hello there'));
    await tester.pumpAndSettle();
    expect(find.text('Copy message'), findsOneWidget);
    expect(find.text('Report message'), findsNothing);
  });

  testWidgets('Discover hides adult rooms; Filters can show them', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = await _inRoom(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IrcApp)),
    );
    container.read(chatControllerProvider.notifier).fetchMissingRooms();
    transport.incoming
      ..add(':s 321 me Channel :Users Name')
      ..add(':s 322 me #linux 891 :General Linux help')
      ..add(':s 322 me #sex 300 :Adults only')
      ..add(':s 322 me #lounge 50 :nsfw pics')
      ..add(':s 322 me #coffee 24 :Small, slow, friendly')
      ..add(':s 323 me :End');
    await tester.pumpAndSettle();
    unawaited(container.read(routerProvider).push('/chat/rooms'));
    await tester.pumpAndSettle();
    expect(find.byType(RoomCard), findsNWidgets(2));
    expect(find.text('#sex'), findsNothing);

    container.read(safetyProvider.notifier).setHideAdultRooms(enabled: false);
    await tester.pumpAndSettle();
    expect(find.byType(RoomCard), findsNWidgets(4));
  });

  testWidgets('Settings: Safety switches, terms and contact', (tester) async {
    final store = MemoryKeyValueStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const IrcApp(),
      ),
    );
    unawaited(
      ProviderScope.containerOf(tester.element(find.byType(IrcApp)))
          .read(routerProvider)
          .push('/settings'),
    );
    await tester.pumpAndSettle();
    final settingsList = find
        .descendant(
          of: find.byType(SettingsScreen),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Hide offensive words'),
      200,
      scrollable: settingsList,
    );
    await tester.ensureVisible(find.text('Hide offensive words'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hide offensive words'));
    await tester.pumpAndSettle();
    expect(
      jsonDecode(store.getString('safety')!),
      containsPair('filterWords', false),
    );
    await tester.scrollUntilVisible(
      find.text('Terms of use'),
      200,
      scrollable: settingsList,
    );
    expect(find.text(supportContact), findsOneWidget);
    await tester.ensureVisible(find.text('Terms of use'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terms of use'));
    await tester.pumpAndSettle();
    expect(find.text('No tolerance for abuse'), findsOneWidget);
    // Read-only: no Agree button.
    expect(find.text('Agree and continue'), findsNothing);
  });
}
