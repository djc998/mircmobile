import 'dart:async';

import 'package:flutter/gestures.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/chat_dividers.dart';
import 'package:irc_client/core/ui/message_group.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
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

/// Connects as `me`, joins #chat with @alice, +bob and carol.
Future<(FakeTransport, ProviderContainer)> start(
  WidgetTester tester, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
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
    ..add(':me!u@h JOIN #chat')
    ..add(':s 353 me = #chat :me @alice +bob carol')
    ..add(':s 366 me #chat :End');
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(IrcApp)),
  );
  return (transport, container);
}

void main() {
  testWidgets('rooms: grouped messages, OP badge, mentions and own bar', (
    tester,
  ) async {
    final (transport, _) = await start(tester);
    transport.incoming
      ..add(':alice!a@h PRIVMSG #chat :Morning all')
      ..add(':alice!a@h PRIVMSG #chat :Anyone here?')
      ..add(':bob!b@h PRIVMSG #chat :me: you around?');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'I am');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    // The list is built newest first; put it back in reading order.
    final groups = tester
        .widgetList<MessageGroup>(find.byType(MessageGroup))
        .toList()
        .reversed
        .toList();
    expect(groups.map((g) => g.nick), ['alice', 'bob', 'me']);
    // alice's two messages share one header.
    expect(groups.first.children, hasLength(2));
    expect(groups.first.role, NickRole.op);
    expect(find.byType(OpBadge), findsOneWidget);
    expect(groups[1].mentioned, isTrue);
    expect(groups[2].own, isTrue);
    expect(find.text('Today'), findsOneWidget);

    // Screen readers hear who and when with each message.
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(RegExp('^bob, .*, message, mentions you')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('joins and leaves collapse into one line that expands', (
    tester,
  ) async {
    final (transport, _) = await start(tester);
    transport.incoming
      ..add(':mara!m@h JOIN #chat')
      ..add(':kai!k@h JOIN #chat')
      ..add(':zed!z@h JOIN #chat')
      ..add(':yan!y@h JOIN #chat')
      ..add(':carol!c@h PART #chat');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('mara, kai and 2 others joined · carol left'),
      findsOneWidget,
    );
    expect(find.text('zed joined'), findsNothing);
    await tester.tap(find.textContaining('mara, kai and 2 others'));
    await tester.pumpAndSettle();
    expect(find.text('zed joined'), findsOneWidget);
  });

  testWidgets('a New messages divider where unread messages start', (
    tester,
  ) async {
    final (transport, container) = await start(tester);
    transport.incoming.add(':alice!a@h PRIVMSG #chat :before');
    await tester.pumpAndSettle();
    // Look at the server tab while two more arrive.
    final controller = container.read(chatControllerProvider.notifier)
      ..selectBuffer(ChatState.bufferKey('irc.libera.chat', '*status'));
    transport.incoming
      ..add(':bob!b@h PRIVMSG #chat :after one')
      ..add(':bob!b@h PRIVMSG #chat :after two');
    await tester.pumpAndSettle();
    expect(find.byType(UnreadDivider), findsNothing);
    controller.selectBuffer(ChatState.bufferKey('irc.libera.chat', '#chat'));
    await tester.pumpAndSettle();
    expect(find.text('New messages'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('New messages')).dy,
      lessThan(tester.getTopLeft(find.textContaining('after one')).dy),
    );
    expect(
      tester.getTopLeft(find.text('New messages')).dy,
      greaterThan(tester.getTopLeft(find.textContaining('before')).dy),
    );

    // Gone after leaving and coming back.
    controller
      ..selectBuffer(ChatState.bufferKey('irc.libera.chat', '*status'))
      ..selectBuffer(ChatState.bufferKey('irc.libera.chat', '#chat'));
    await tester.pumpAndSettle();
    expect(find.text('New messages'), findsNothing);
  });

  testWidgets('private chats use bubbles, yours on the right', (tester) async {
    final (transport, container) = await start(tester);
    transport.incoming
      ..add(':alice!a@h PRIVMSG me :hey there')
      ..add(':alice!a@h PRIVMSG me :you around?');
    await tester.pumpAndSettle();
    container
        .read(chatControllerProvider.notifier)
        .selectBuffer(ChatState.bufferKey('irc.libera.chat', 'alice'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'yes!');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();

    // In reading order, top to bottom.
    final found = find.byType(MessageBubble);
    final order = List.generate(found.evaluate().length, (i) => i)
      ..sort(
        (a, b) => tester
            .getTopLeft(found.at(a))
            .dy
            .compareTo(tester.getTopLeft(found.at(b)).dy),
      );
    final bubbles = [
      for (final i in order) tester.widget<MessageBubble>(found.at(i)),
    ];
    expect(bubbles.map((b) => b.own), [false, false, true]);
    expect(bubbles.map((b) => b.continued), [false, true, false]);
    expect(find.byType(MessageGroup), findsNothing);
    Rect shape(int i) => tester.getRect(
      find.descendant(of: found.at(i), matching: find.byType(Container)).first,
    );
    final theirs = shape(order.first);
    final mine = shape(order.last);
    expect(mine.right, greaterThan(theirs.right));
    expect(mine.left, greaterThan(theirs.left));
    // Header: avatar and network instead of the topic.
    expect(find.byType(NickAvatar), findsWidgets);
    expect(find.byTooltip('Voice call'), findsOneWidget);
  });

  testWidgets('Compact keeps the classic HH:MM <nick> lines', (tester) async {
    final (transport, container) = await start(tester);
    container.read(appearanceProvider.notifier).setDensity(ChatDensity.compact);
    transport.incoming.add(':alice!a@h PRIVMSG #chat :classic');
    await tester.pumpAndSettle();
    expect(find.byType(MessageGroup), findsNothing);
    expect(find.textContaining('<alice> classic'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('composer: chips complete @nick, /command and #room', (
    tester,
  ) async {
    final (transport, _) = await start(tester);
    await tester.enterText(find.byType(TextField), '@al');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '@alice'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '@alice'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'alice: ',
    );
    expect(find.widgetWithText(ActionChip, '@alice'), findsNothing);

    await tester.enterText(find.byType(TextField), '/to');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, '/topic'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '/topic ',
    );

    await tester.enterText(find.byType(TextField), 'see #ch');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ActionChip, '#chat'), findsOneWidget);

    // The + menu starts a command.
    await tester.tap(find.byTooltip('Add a command'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Describe an action (/me)'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '/me waves');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'PRIVMSG #chat :\x01ACTION waves\x01');
  });

  testWidgets('scrolled up: a "new" pill jumps back to the latest', (
    tester,
  ) async {
    final (transport, _) = await start(tester);
    for (var i = 0; i < 80; i++) {
      transport.incoming.add(':bob!b@h PRIVMSG #chat :line $i');
    }
    await tester.pumpAndSettle();
    expect(find.byType(JumpPill), findsNothing);
    await tester.drag(find.textContaining('line 79'), const Offset(0, 500));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':alice!a@h PRIVMSG #chat :new one')
      ..add(':alice!a@h PRIVMSG #chat :me: and you');
    await tester.pumpAndSettle();
    expect(find.byType(JumpPill), findsOneWidget);
    expect(find.text('@ 2 new'), findsOneWidget);
    await tester.tap(find.byType(JumpPill));
    await tester.pumpAndSettle();
    expect(find.byType(JumpPill), findsNothing);
    expect(find.textContaining('and you'), findsOneWidget);
  });

  testWidgets(
    'computers: the reply button shows on hover',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      final (transport, _) = await start(tester);
      transport.incoming.add(':alice!a@h PRIVMSG #chat :anyone here?');
      await tester.pumpAndSettle();
      final button = find.byTooltip('Reply to alice');
      double opacity() => tester
          .widget<Opacity>(
            find.ancestor(of: button, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(opacity(), 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.textContaining('anyone here?')));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Replying to alice', findRichText: true),
        findsOneWidget,
      );
    },
  );

  testWidgets('reduce motion: the pill jumps without animating', (
    tester,
  ) async {
    // Motion.of returns zero when animations are off.
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            expect(Motion.of(context, Motion.slow), Duration.zero);
            return const SizedBox();
          },
        ),
      ),
    );
  });
}
