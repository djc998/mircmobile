import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

class FakeTransport implements IrcTransport {
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

/// Every guideline flutter_test checks.
Future<void> meetsAll(WidgetTester tester, String where) async {
  for (final (name, g) in [
    ('Android tap targets', androidTapTargetGuideline),
    ('iOS tap targets', iOSTapTargetGuideline),
    ('labelled tap targets', labeledTapTargetGuideline),
    ('text contrast', textContrastGuideline),
  ]) {
    final result = await g.evaluate(tester);
    expect(result.passed, isTrue, reason: '$where · $name:\n${result.reason}');
  }
}

typedef Screen = (String, Future<void> Function(WidgetTester, FakeTransport));

Future<FakeTransport> launch(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  tester.platformDispatcher
    ..platformBrightnessTestValue = brightness
    ..textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
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
  await tester.pumpAndSettle();
  return transport;
}

Future<void> connect(WidgetTester tester, FakeTransport t) async {
  await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Libera.Chat'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Libera.Chat'));
  await tester.pumpAndSettle();
  t.incoming
    ..add(':s 001 me :Welcome')
    ..add(':s 005 me NETWORK=Libera.Chat :ok')
    ..add(':me!u@h JOIN #flutter')
    ..add(':s 353 me = #flutter :me @devon +kai alice')
    ..add(':s 366 me #flutter :End')
    ..add(':devon!d@h PRIVMSG #flutter :Morning all')
    ..add(':alice!a@h PRIVMSG #flutter :me: does it run on the Mac?')
    ..add(':kai!k@h JOIN #flutter')
    ..add(':alice!a@h PRIVMSG me :hi there');
  await tester.pumpAndSettle();
}

void main() {
  final screens = <Screen>[
    ('welcome', (tester, t) async {}),
    (
      'room chat',
      (tester, t) async {
        await connect(tester, t);
        await tester.tap(find.text('#flutter').first);
        await tester.pumpAndSettle();
      },
    ),
    (
      'rooms home',
      (tester, t) async {
        await connect(tester, t);
        if (find.byTooltip('Back to rooms').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('Back to rooms'));
          await tester.pumpAndSettle();
        }
      },
    ),
    (
      'room info',
      (tester, t) async {
        await connect(tester, t);
        await tester.tap(find.byTooltip('Chat info'));
        await tester.pumpAndSettle();
      },
    ),
    (
      'profile card',
      (tester, t) async {
        await connect(tester, t);
        await tester.tap(find.text('devon').first);
        await tester.pumpAndSettle();
      },
    ),
    (
      'settings',
      (tester, t) async {
        await connect(tester, t);
        final c = ProviderScope.containerOf(
          tester.element(find.byType(IrcApp)),
        );
        unawaited(c.read(routerProvider).push('/settings'));
        await tester.pumpAndSettle();
      },
    ),
    (
      'appearance',
      (tester, t) async {
        final c = ProviderScope.containerOf(
          tester.element(find.byType(IrcApp)),
        );
        unawaited(c.read(routerProvider).push('/appearance'));
        await tester.pumpAndSettle();
      },
    ),
  ];

  for (final (name, open) in screens) {
    for (final b in Brightness.values) {
      testWidgets('$name (${b.name}) meets the guidelines', (tester) async {
        final handle = tester.ensureSemantics();
        final t = await launch(tester, brightness: b);
        await open(tester, t);
        await meetsAll(tester, '$name ${b.name}');
        handle.dispose();
      });
    }
    testWidgets('$name fits at twice the text size', (tester) async {
      final t = await launch(tester, textScale: 2);
      await open(tester, t);
      expect(tester.takeException(), isNull);
    });
  }

  for (final preset in [
    ThemePreset.classic,
    ThemePreset.midnight,
    ThemePreset.solarized,
    ThemePreset.highContrast,
  ]) {
    testWidgets('${preset.label}: a room meets text contrast', (tester) async {
      final handle = tester.ensureSemantics();
      final t = await launch(tester);
      ProviderScope.containerOf(tester.element(find.byType(IrcApp)))
          .read(appearanceProvider.notifier)
          .setPreset(preset);
      await tester.pumpAndSettle();
      await connect(tester, t);
      final result = await textContrastGuideline.evaluate(tester);
      expect(result.passed, isTrue, reason: result.reason);
      handle.dispose();
    });
  }
}
