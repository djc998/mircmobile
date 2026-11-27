import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/ui/conversation_row.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/conversations.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/chat/presentation/chat_shell.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
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

/// Connects as `me`, joins #linux then #flutter (which ends up open), and
/// bob writes privately.
Future<(FakeTransport, ProviderContainer)> start(
  WidgetTester tester,
  Size size,
) async {
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
  await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
  await tester.tap(find.text('Libera.Chat'));
  await tester.pumpAndSettle();
  transport.incoming
    ..add(':s 001 me :Welcome')
    ..add(':s 005 me NETWORK=Libera.Chat :are supported')
    ..add(':me!u@h JOIN #linux')
    ..add(':tux!t@h PRIVMSG #linux :Thanks!')
    ..add(':me!u@h JOIN #flutter')
    ..add(':s 353 me = #flutter :me @devon alice')
    ..add(':s 366 me #flutter :End');
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(IrcApp)),
  );
  return (transport, container);
}

const phone = Size(390, 844);
const tablet = Size(820, 1000);
const mac = Size(1280, 800);

Finder row(String name) =>
    find.byWidgetPredicate((w) => w is ConversationRow && w.name == name);

void main() {
  group('phones', () {
    testWidgets('a joined room opens full screen; back shows Rooms home', (
      tester,
    ) async {
      final (transport, _) = await start(tester, phone);
      expect(find.widgetWithText(AppBar, '#flutter'), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.tap(find.byTooltip('Back to rooms'));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('Rooms'), findsWidgets);
      expect(row('#flutter'), findsOneWidget);
      expect(row('#linux'), findsOneWidget);

      // Messages in the chat you left count as unread again.
      transport.incoming.add(':alice!a@h PRIVMSG #flutter :me: you there?');
      await tester.pumpAndSettle();
      final flutterRow = tester.widget<ConversationRow>(row('#flutter'));
      expect(flutterRow.unread, 1);
      expect(flutterRow.mention, isTrue);
      expect(flutterRow.preview, 'alice: me: you there?');
      // Newest activity first.
      expect(
        tester.getTopLeft(row('#flutter')).dy,
        lessThan(tester.getTopLeft(row('#linux')).dy),
      );

      // Mentions has a badge and lists the message; tapping opens it.
      expect(find.byType(Badge), findsOneWidget);
      await tester.tap(find.text('Mentions'));
      await tester.pumpAndSettle();
      expect(find.text('me: you there?'), findsOneWidget);
      await tester.tap(find.text('me: you there?'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '#flutter'), findsOneWidget);

      // The system back gesture also goes back.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(NavigationBar), findsOneWidget);
    });

    testWidgets('the back button counts new messages in other chats', (
      tester,
    ) async {
      final (transport, _) = await start(tester, phone);
      expect(find.bySemanticsLabel('Back to rooms'), findsOneWidget);

      // A message in #linux while you're in #flutter.
      transport.incoming.add(':tux!t@h PRIVMSG #linux :anyone?');
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('Back to rooms, 1 chat with new messages'),
        findsOneWidget,
      );
      expect(find.text('1'), findsOneWidget);

      // A private message, and a mention in #linux: coral `@ 2`.
      transport.incoming
        ..add(':bob!b@h PRIVMSG me :hi there')
        ..add(':tux!t@h PRIVMSG #linux :me: are you around?');
      await tester.pumpAndSettle();
      expect(find.text('@ 2'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Back to rooms, 2 chats with new messages, one mentions you',
        ),
        findsOneWidget,
      );

      // Messages in the open chat don't count.
      transport.incoming.add(':alice!a@h PRIVMSG #flutter :hello');
      await tester.pumpAndSettle();
      expect(find.text('@ 2'), findsOneWidget);

      // Reading them clears the badge.
      await tester.tap(find.byTooltip('Back to rooms'));
      await tester.pumpAndSettle();
      await tester.tap(row('#linux'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back to rooms'));
      await tester.pumpAndSettle();
      await tester.tap(row('bob'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Back to rooms'), findsOneWidget);
    });

    testWidgets('search, and swipe to favorite or leave', (tester) async {
      final (transport, container) = await start(tester, phone);
      await tester.tap(find.byTooltip('Back to rooms'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'lin');
      await tester.pumpAndSettle();
      expect(row('#linux'), findsOneWidget);
      expect(row('#flutter'), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      // Swipe right: favorite (it also shows as a tile).
      await tester.drag(row('#linux'), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(
        container
            .read(roomPrefsProvider)
            .isFavorite('irc.libera.chat', '#linux'),
        isTrue,
      );
      expect(find.byType(FavoriteTile), findsOneWidget);

      // Swipe left: leave.
      await tester.drag(row('#flutter'), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(transport.written.last, startsWith('PART #flutter'));
      expect(row('#flutter'), findsNothing);
    });

    testWidgets('Discover is a tab; joining from it opens the room', (
      tester,
    ) async {
      final (transport, _) = await start(tester, phone);
      await tester.tap(find.byTooltip('Back to rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discover'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Rooms on Libera.Chat'), findsOneWidget);
      transport.incoming
        ..add(':s 321 me Channel :Users Name')
        ..add(':s 322 me #dart 50 :Dart')
        ..add(':s 323 me :End');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();
      expect(transport.written.last, 'JOIN #dart');
      transport.incoming.add(':me!u@h JOIN #dart');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '#dart'), findsOneWidget);
    });

    testWidgets('You has your nickname, networks and settings', (tester) async {
      await start(tester, phone);
      await tester.tap(find.byTooltip('Back to rooms'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      expect(find.text('Connected to 1 network'), findsOneWidget);
      expect(find.byTooltip('Options for Libera.Chat'), findsOneWidget);
      expect(find.text('Appearance'), findsOneWidget);
      // Server messages open full screen too.
      await tester.tap(find.text('Server messages'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Libera.Chat'), findsOneWidget);
      expect(find.byTooltip('Back to rooms'), findsOneWidget);
    });
  });

  testWidgets('small tablets: rail, rooms list and chat side by side', (
    tester,
  ) async {
    await start(tester, tablet);
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(row('#linux'), findsOneWidget);
    expect(find.widgetWithText(AppBar, '#flutter'), findsOneWidget);
    // The open chat's row is highlighted.
    expect(tester.widget<ConversationRow>(row('#flutter')).selected, isTrue);
    await tester.tap(row('#linux'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '#linux'), findsOneWidget);
    expect(find.byType(NavigationRail), findsOneWidget);
  });

  group('wide screens', () {
    testWidgets('sidebar sections, Home, Mentions and You', (tester) async {
      final (transport, container) = await start(tester, mac);
      container
          .read(roomPrefsProvider.notifier)
          .toggleFavorite('irc.libera.chat', '#linux');
      transport.incoming.add(':bob!b@h PRIVMSG me :hi');
      await tester.pumpAndSettle();
      final sidebar = find.byType(Sidebar);
      expect(
        find.descendant(of: sidebar, matching: find.text('Favorites')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sidebar, matching: find.text('Private chats')),
        findsOneWidget,
      );
      final rows = tester
          .widgetList<ConversationRow>(
            find.descendant(
              of: sidebar,
              matching: find.byType(ConversationRow),
            ),
          )
          .map((r) => r.name)
          .toList();
      expect(rows, ['#linux', '#flutter', 'bob']);

      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Active now'), findsOneWidget);
      expect(find.byType(ChatScreen), findsNothing);

      await tester.tap(find.text('Connected to 1 network'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Options for Libera.Chat'), findsOneWidget);

      await tester.tap(
        find.descendant(of: sidebar, matching: find.text('#flutter')),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, '#flutter'), findsOneWidget);
    });

    testWidgets(
      'Mac: menu bar, Cmd+K switcher, Cmd+1…9 and Cmd+F',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        final (transport, _) = await start(tester, mac);
        expect(find.byType(PlatformMenuBar), findsOneWidget);
        transport.incoming.add(':tux!t@h PRIVMSG #flutter :kernel panic');
        await tester.pumpAndSettle();

        final dialogField = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(TextField),
        );

        Future<void> cmd(LogicalKeyboardKey key) async {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
          await tester.sendKeyEvent(key);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
          await tester.pumpAndSettle();
        }

        // Cmd+K, type, Enter.
        await cmd(LogicalKeyboardKey.keyK);
        expect(find.byType(Dialog), findsOneWidget);
        await tester.enterText(dialogField, 'lin');
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(ConversationRow),
          ),
          findsOneWidget,
        );
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(AppBar, '#linux'), findsOneWidget);

        // Cmd+2: the second chat in the sidebar.
        await cmd(LogicalKeyboardKey.digit2);
        expect(find.widgetWithText(AppBar, '#flutter'), findsOneWidget);

        // Cmd+F finds a message in the open chat.
        await cmd(LogicalKeyboardKey.keyF);
        await tester.enterText(dialogField, 'panic');
        await tester.pumpAndSettle();
        expect(find.text('1 match'), findsOneWidget);
        expect(find.textContaining('kernel panic'), findsWidgets);
      },
    );
  });

  group('conversation helpers', () {
    test('short network names', () {
      expect(shortNetworkName('Libera.Chat'), 'Libera');
      expect(shortNetworkName('irc.oftc.net'), 'oftc');
      expect(shortNetworkName('EFnet'), 'EFnet');
    });

    testWidgets('activity labels: time today, Yesterday, then the date', (
      tester,
    ) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      final now = DateTime(2026, 11, 22, 15);
      expect(
        activityLabel(ctx, DateTime(2026, 11, 22, 10, 15), now: now),
        '10:15 AM',
      );
      expect(
        activityLabel(ctx, DateTime(2026, 11, 21, 23), now: now),
        'Yesterday',
      );
      expect(activityLabel(ctx, DateTime(2026, 11, 2), now: now), 'Nov 2');
      expect(activityLabel(ctx, null, now: now), '');
    });

    testWidgets('previews and the quick switcher order', (tester) async {
      final (transport, container) = await start(tester, mac);
      transport.incoming
        ..add(':alice!a@h PRIVMSG #flutter :\x02bold\x02 hello')
        ..add(':alice!a@h PRIVMSG #flutter :\x01ACTION waves\x01');
      await tester.pumpAndSettle();
      final state = container.read(chatControllerProvider);
      final flutter = activeConversations(state).first;
      expect(flutter.name, '#flutter');
      expect(flutter.preview, '* alice waves');
      expect(switcherMatches(state, 'li').map((c) => c.name), ['#linux']);
      // Starts-with matches come before contains matches.
      expect(switcherMatches(state, 'ut').map((c) => c.name), ['#flutter']);
      expect(switcherMatches(state, '').length, 2);
      expect(unreadMentionChats(state), 0);
    });
  });
}
