import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
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

const _caps = 'batch server-time draft/chathistory';
const _net = 'irc.libera.chat';

/// Coming back from the background: check, reconnect, catch up.
void main() {
  late List<_Transport> transports;
  late ProviderContainer container;

  _Transport last() => transports.last;

  Future<void> register(WidgetTester tester, _Transport t) async {
    t.incoming
      ..add(':s CAP * LS :$_caps')
      ..add(':s CAP * ACK :$_caps')
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #chat');
    await tester.pumpAndSettle();
  }

  Future<void> start(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    transports = [];
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
    container = ProviderScope.containerOf(tester.element(find.byType(IrcApp)));
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.ensureVisible(find.text('Libera.Chat'));
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    await register(tester, last());
  }

  ChatState state() => container.read(chatControllerProvider);
  NetworkSession session() => state().networks[_net]!;

  // The system steps through each state in between.
  Future<void> go(WidgetTester tester, List<AppLifecycleState> steps) async {
    steps.forEach(tester.binding.handleAppLifecycleStateChanged);
    await tester.pump();
  }

  Future<void> background(WidgetTester tester) => go(tester, const [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]);

  Future<void> foreground(WidgetTester tester) => go(tester, const [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]);

  Finder reconnectingBar() => find.byType(ReconnectingBar);

  testWidgets('a live connection answers and the bar goes away', (
    tester,
  ) async {
    await start(tester);
    await background(tester);
    expect(reconnectingBar(), findsNothing);

    await foreground(tester);
    expect(last().written.last, 'PING :check-1');
    expect(reconnectingBar(), findsOneWidget);
    expect(find.text('Reconnecting…'), findsWidgets);

    last().incoming.add(':s PONG s :check-1');
    await tester.pumpAndSettle();
    expect(reconnectingBar(), findsNothing);
    expect(session().resuming, isFalse);
    expect(transports, hasLength(1));
  });

  testWidgets(
    'a dead connection reconnects, stays on the open chat and fetches '
    'what was missed',
    (tester) async {
      await start(tester);
      final controller = container.read(chatControllerProvider.notifier)
        ..openPrivateChat('bob');
      await tester.pumpAndSettle();
      final open = ChatState.bufferKey(_net, 'bob');
      expect(state().activeKey, open);

      await background(tester);
      await foreground(tester);
      expect(reconnectingBar(), findsOneWidget);

      // The system dropped the socket: no PONG ever comes.
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(transports, hasLength(2));
      expect(reconnectingBar(), findsOneWidget);

      await register(tester, last());
      expect(reconnectingBar(), findsNothing);
      // Rejoined the room without jumping to it.
      expect(last().written, contains('JOIN #chat'));
      expect(state().activeKey, open);
      // Asked the server for what the room and the private chat missed.
      expect(last().written, contains(startsWith('CHATHISTORY LATEST #chat ')));
      expect(last().written, contains(startsWith('CHATHISTORY LATEST bob ')));
      expect(last().written, contains(startsWith('CHATHISTORY TARGETS ')));
      // No second "You joined" line for the quiet rejoin.
      expect(
        state().buffers[ChatState.bufferKey(_net, '#chat')]!.lines.where(
          (l) => l.text == 'You joined #chat',
        ),
        hasLength(1),
      );
      // One welcome, not one per reconnect.
      expect(
        state().buffers[ChatState.bufferKey(_net, statusBuffer)]!.lines.where(
          (l) => l.text.startsWith('Welcome, me'),
        ),
        hasLength(1),
      );
      controller.selectBuffer(open);
    },
  );

  testWidgets('inactive without being hidden does not check', (tester) async {
    await start(tester);
    // Control Center or the notification shade.
    await go(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(last().written.where((l) => l.startsWith('PING')), isEmpty);
    expect(reconnectingBar(), findsNothing);
  });

  testWidgets('a disconnected network is left alone', (tester) async {
    await start(tester);
    await tester.runAsync(
      () => container.read(chatControllerProvider.notifier).disconnect(),
    );
    await tester.pumpAndSettle();
    await background(tester);
    await foreground(tester);
    expect(session().status, IrcConnectionStatus.disconnected);
    expect(session().resuming, isFalse);
    expect(transports, hasLength(1));
  });
}
