import 'dart:async';

import 'package:flutter/gestures.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/conversation_row.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
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

/// Connects with away-notify and joins #flutter with @devon, +kai, alice.
Future<(FakeTransport, ProviderContainer)> start(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
}) async {
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
    ..add(':s CAP * LS :away-notify')
    ..add(':s CAP * ACK :away-notify')
    ..add(':s 001 me :Welcome')
    ..add(':s 005 me NETWORK=Libera.Chat :ok')
    ..add(':me!u@h JOIN #flutter')
    ..add(':s 353 me = #flutter :me @devon +kai alice')
    ..add(':s 366 me #flutter :End');
  await tester.pumpAndSettle();
  return (
    transport,
    ProviderScope.containerOf(tester.element(find.byType(IrcApp))),
  );
}

Future<void> flush(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 600)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('People: Operators, Voiced, Members, then Away', (tester) async {
    final (transport, _) = await start(tester);
    await flush(tester);
    // One WHO after joining tells us who's away already.
    expect(transport.written, contains('WHO #flutter'));
    transport.incoming
      ..add(':s 352 me #flutter u h s alice G :0 Alice')
      ..add(':s 315 me #flutter :End of WHO');
    await tester.pumpAndSettle();
    expect(find.text('Operators · 1'), findsOneWidget);
    expect(find.text('Voiced · 1'), findsOneWidget);
    expect(find.text('Members · 1'), findsOneWidget); // me
    expect(find.text('Away · 1'), findsOneWidget);
    expect(find.textContaining('End of WHO'), findsNothing);

    // away-notify: alice is back, kai goes away.
    transport.incoming
      ..add(':alice!a@h AWAY')
      ..add(':kai!k@h AWAY :lunch');
    await tester.pumpAndSettle();
    expect(find.text('Members · 2'), findsOneWidget);
    expect(find.text('Voiced · 1'), findsNothing);
    expect(find.text('Away · 1'), findsOneWidget);
  });

  testWidgets('profile card: role, Mention, Ignore and Report', (tester) async {
    final (transport, container) = await start(tester);
    transport.incoming
      ..add(':alice!a@h PRIVMSG #flutter :first')
      ..add(':devon!d@h PRIVMSG #flutter :hello');
    await tester.pumpAndSettle();

    await tester.tap(find.text('@devon'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Operator of #flutter'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    await tester.tap(find.text('Mention'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Replying to devon'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pumpAndSettle();

    // Report alice: devon is an operator to tell; Ignore from there.
    await tester.tap(find.text('alice').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report alice'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'devon'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Ignore alice'));
    await tester.pumpAndSettle();
    expect(
      container.read(chatControllerProvider.notifier).isBlocked('alice'),
      isTrue,
    );
    transport.incoming.add(':alice!a@h PRIVMSG #flutter :you cannot see me');
    await tester.pumpAndSettle();
    expect(find.textContaining('you cannot see me'), findsNothing);

    // Settings lists ignored people.
    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Stop ignoring'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('alice'), findsOneWidget);
    await tester.tap(find.text('Stop ignoring'));
    await tester.pumpAndSettle();
    expect(find.text('Nobody'), findsOneWidget);
  });

  testWidgets('Mute: grey badge, out of Mentions, listed in Settings', (
    tester,
  ) async {
    final (transport, container) = await start(tester);
    transport.incoming.add(':me!u@h JOIN #linux');
    await tester.pumpAndSettle();
    // Look at #linux while #flutter gets a mention.
    transport.incoming.add(':alice!a@h PRIVMSG #flutter :me: ping');
    await tester.pumpAndSettle();
    Finder flutterRow() => find.byWidgetPredicate(
      (w) => w is ConversationRow && w.name == '#flutter',
    );
    expect(find.text('@ 1'), findsWidgets); // Mentions badge

    // Right-click the row in the sidebar to mute it.
    await tester.tap(flutterRow(), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute #flutter'));
    await tester.pumpAndSettle();
    expect(tester.widget<ConversationRow>(flutterRow()).muted, isTrue);
    expect(
      container.read(roomPrefsProvider).isMuted('irc.libera.chat', '#flutter'),
      isTrue,
    );
    // A mention still shows coral, but no longer counts for Mentions.
    final badge = tester.widget<UnreadBadge>(
      find.descendant(of: flutterRow(), matching: find.byType(UnreadBadge)),
    );
    expect(badge.mention && badge.muted, isTrue);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Mentions'),
        matching: find.byType(UnreadBadge),
      ),
      findsNothing,
    );

    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Unmute'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('#flutter'), findsOneWidget);
    await tester.tap(find.text('Unmute'));
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);
  });

  testWidgets('Room info: favorite, mute and settings on one page', (
    tester,
  ) async {
    final (_, container) = await start(tester);
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.text('Room info'), findsOneWidget);
    expect(find.text('4 people · Libera.Chat'), findsWidgets);
    await tester.tap(find.text('Mute'));
    await tester.pumpAndSettle();
    expect(
      container.read(roomPrefsProvider).isMuted('irc.libera.chat', '#flutter'),
      isTrue,
    );
    // The room's settings are right here, not in another sheet.
    expect(find.text('Room settings'), findsOneWidget);
    expect(find.widgetWithText(SwitchListTile, 'Private'), findsOneWidget);
    await tester.tap(find.byTooltip('Close room info'));
    await tester.pumpAndSettle();
    expect(find.text('Room info'), findsNothing);
  });

  testWidgets('Monospace font for messages', (tester) async {
    final (transport, container) = await start(tester);
    container.read(appearanceProvider.notifier).setFont(MessageFont.mono);
    transport.incoming.add(':alice!a@h PRIVMSG #flutter :ascii art');
    await tester.pumpAndSettle();
    final style = DefaultTextStyle.of(
      tester.element(find.textContaining('ascii art')),
    ).style;
    expect(style.fontFamily, 'monospace');
    expect(style.fontFamilyFallback, MessageFont.monoFamilies);
  });

  testWidgets('new messages fade in; not with Reduce Motion', (tester) async {
    final (transport, _) = await start(tester);
    transport.incoming.add(':alice!a@h PRIVMSG #flutter :fresh');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    double opacityOf(String text) => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.textContaining(text),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(opacityOf('fresh'), lessThan(1));
    await tester.pumpAndSettle();
    expect(opacityOf('fresh'), 1);

    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    transport.incoming.add(':alice!a@h PRIVMSG #flutter :still');
    await tester.pump();
    await tester.pump();
    expect(opacityOf('still'), 1);
  });

  test('muted badges stay readable', () {
    for (final b in Brightness.values) {
      final t = AppTokens.indigo(b);
      expect(
        tokenContrast(
          t.readable(t.textMuted, t.surfaceOverlay),
          Color.alphaBlend(t.surfaceOverlay, t.surface),
        ),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  testWidgets('ChatScreen still builds without a room', (tester) async {
    await start(tester, size: const Size(390, 844));
    expect(find.byType(ChatScreen), findsOneWidget);
  });
}
