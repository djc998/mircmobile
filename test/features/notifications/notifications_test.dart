import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/notifications/application/notification_settings.dart';
import 'package:irc_client/features/notifications/data/message_notifier.dart';
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

/// Records what would reach the system.
class _FakeNotifier implements MessageNotifier {
  _FakeNotifier({this.keepAlive = true});

  final bool keepAlive;
  final shown = <({int id, String title, String body, String payload})>[];
  final cancelled = <int>[];
  int permissionRequests = 0;
  bool running = false;
  void Function(String payload)? tap;

  @override
  bool get supportsMessages => true;
  @override
  bool get supportsKeepAlive => keepAlive;
  @override
  void setOnTap(void Function(String payload)? callback) => tap = callback;
  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async => shown.add((id: id, title: title, body: body, payload: payload));
  @override
  Future<void> cancel(int id) async => cancelled.add(id);
  @override
  Future<void> startKeepAlive() async => running = true;
  @override
  Future<void> stopKeepAlive() async => running = false;
}

const _net = 'irc.libera.chat';

void main() {
  late _Transport transport;
  late _FakeNotifier notifier;
  late ProviderContainer container;

  Future<void> start(WidgetTester tester, {bool keepAlive = true}) async {
    tester.view
      ..physicalSize = const Size(1200, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    notifier = _FakeNotifier(keepAlive: keepAlive);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messageNotifierProvider.overrideWithValue(notifier),
          // A new socket per connection, like the real thing.
          transportFactoryProvider.overrideWithValue(
            (host, port, {required useTls, trustedFingerprints = const {}}) =>
                transport = _Transport(),
          ),
        ],
        child: const IrcApp(),
      ),
    );
    container = ProviderScope.containerOf(tester.element(find.byType(IrcApp)));
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.ensureVisible(find.text('Libera.Chat'));
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #chat');
    await tester.pumpAndSettle();
  }

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

  Future<void> server(WidgetTester tester, String line) async {
    transport.incoming.add(line);
    await tester.pump();
  }

  testWidgets('private messages and mentions notify while in the background', (
    tester,
  ) async {
    await start(tester);
    await background(tester);

    await server(tester, ':bob!b@h PRIVMSG me :\x02hey\x02 there');
    await server(tester, ':ann!a@h PRIVMSG #chat :me: lunch?');
    await server(tester, ':ann!a@h PRIVMSG #chat :\x01ACTION waves at me\x01');
    // Not for: a room message without the nick, a notice, our own echo.
    await server(tester, ':ann!a@h PRIVMSG #chat :just chatting');
    await server(tester, ':NickServ!s@h NOTICE me :Please identify');

    expect(notifier.shown.map((n) => n.title), [
      'bob',
      'ann in #chat',
      'ann in #chat',
    ]);
    expect(notifier.shown.first.body, 'hey there');
    expect(notifier.shown.first.payload, ChatState.bufferKey(_net, 'bob'));
    expect(notifier.shown.last.body, '* ann waves at me');
    // One notification per conversation: the newer replaces the older.
    expect(
      notifier.shown[1].id,
      ChatController.notificationId(ChatState.bufferKey(_net, '#chat')),
    );
    await foreground(tester);
  });

  testWidgets('nothing while the app is in front', (tester) async {
    await start(tester);
    await server(tester, ':bob!b@h PRIVMSG me :hi');
    // On an iPhone a system alert over the app makes it inactive, not
    // hidden.
    await go(tester, const [AppLifecycleState.inactive]);
    await server(tester, ':bob!b@h PRIVMSG me :still here?');
    expect(notifier.shown, isEmpty);
    await go(tester, const [AppLifecycleState.resumed]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android: a message while leaving the app (inactive) notifies', (
    tester,
  ) async {
    await start(tester);
    expect(notifier.shown, isEmpty);
    // Leaving the app is inactive for a second or more before it's paused.
    await go(tester, const [AppLifecycleState.inactive]);
    await server(tester, ':bob!b@h PRIVMSG me :you there?');
    expect(notifier.shown.single.body, 'you there?');
    await go(tester, const [AppLifecycleState.resumed]);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('muted rooms and the setting turned off stay quiet', (
    tester,
  ) async {
    await start(tester);
    container.read(roomPrefsProvider.notifier).toggleMute(_net, '#chat');
    await background(tester);
    await server(tester, ':ann!a@h PRIVMSG #chat :me: hello');
    expect(notifier.shown, isEmpty);

    await container
        .read(notificationSettingsProvider.notifier)
        .setMessages(enabled: false);
    await server(tester, ':bob!b@h PRIVMSG me :hi');
    expect(notifier.shown, isEmpty);
    await foreground(tester);
  });

  testWidgets('tapping a notification opens its chat; opening clears it', (
    tester,
  ) async {
    await start(tester);
    await background(tester);
    await server(tester, ':bob!b@h PRIVMSG me :hi');
    await foreground(tester);
    await server(tester, ':s PONG s :check-1');

    final key = ChatState.bufferKey(_net, 'bob');
    notifier.tap!(key);
    await tester.pumpAndSettle();
    expect(container.read(chatControllerProvider).activeKey, key);
    expect(notifier.cancelled, contains(ChatController.notificationId(key)));
  });

  testWidgets('permission is asked once, after the first login', (
    tester,
  ) async {
    await start(tester);
    expect(notifier.permissionRequests, 1);
    transport.incoming.add(':s 001 me :Welcome again');
    await tester.pumpAndSettle();
    expect(notifier.permissionRequests, 1);
  });

  testWidgets('stay connected runs the service while a network is open', (
    tester,
  ) async {
    await start(tester);
    expect(notifier.running, isFalse);

    await container
        .read(notificationSettingsProvider.notifier)
        .setStayConnected(enabled: true);
    await tester.pump();
    expect(notifier.running, isTrue);

    await tester.runAsync(
      () => container.read(chatControllerProvider.notifier).disconnect(),
    );
    await tester.pump();
    expect(notifier.running, isFalse);

    await tester.runAsync(
      () => container.read(chatControllerProvider.notifier).reconnect(),
    );
    await tester.pump();
    expect(notifier.running, isTrue);

    await container
        .read(notificationSettingsProvider.notifier)
        .setStayConnected(enabled: false);
    await tester.pump();
    expect(notifier.running, isFalse);
  });

  testWidgets('Settings → Notifications has both switches on Android', (
    tester,
  ) async {
    await start(tester);
    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pumpAndSettle();
    expect(find.text('NOTIFICATIONS'), findsOneWidget);
    expect(find.text('Private messages and mentions'), findsOneWidget);
    await tester.tap(find.text('Stay connected in the background'));
    await tester.pumpAndSettle();
    expect(container.read(notificationSettingsProvider).stayConnected, isTrue);
    expect(notifier.running, isTrue);
  });

  testWidgets('iOS explains bouncers instead of staying connected', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await start(tester, keepAlive: false);
    unawaited(container.read(routerProvider).push('/settings'));
    await tester.pumpAndSettle();
    expect(find.text('Stay connected in the background'), findsNothing);
    expect(find.textContaining('bouncer such as soju'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
