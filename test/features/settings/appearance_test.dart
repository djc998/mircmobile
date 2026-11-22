import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
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

void main() {
  group('saved appearance', () {
    test('new installs get Default (Indigo), Comfortable', () {
      const a = Appearance();
      expect(a.preset, ThemePreset.indigo);
      expect(a.accent, AccentColor.indigo);
      expect(a.density, ChatDensity.comfortable);
    });

    test('settings from before the redesign move to Default', () {
      // The old default was saved as "classic" by anyone who changed
      // anything (text size, mode).
      final a = Appearance.fromJson({
        'mode': 'dark',
        'preset': 'classic',
        'textScale': 1.15,
      });
      expect(a.preset, ThemePreset.indigo);
      expect(a.mode, AppearanceMode.dark);
      expect(a.textScale, 1.15);
      // Other old themes stay.
      expect(
        Appearance.fromJson({'preset': 'solarized'}).preset,
        ThemePreset.solarized,
      );
    });

    test('Classic mIRC picked after the redesign stays', () {
      final saved = const Appearance(
        preset: ThemePreset.classic,
        accent: AccentColor.teal,
        density: ChatDensity.compact,
      ).toJson();
      final a = Appearance.fromJson(
        jsonDecode(jsonEncode(saved)) as Map<String, Object?>,
      );
      expect(a.preset, ThemePreset.classic);
      expect(a.accent, AccentColor.teal);
      expect(a.density, ChatDensity.compact);
    });

    test('unknown values fall back to defaults', () {
      final a = Appearance.fromJson({
        'version': 2,
        'preset': 'neon',
        'accent': 'gold',
        'density': 'tiny',
      });
      expect(a.preset, ThemePreset.indigo);
      expect(a.accent, AccentColor.indigo);
      expect(a.density, ChatDensity.comfortable);
    });

    test('picking Classic mIRC switches to Compact lines', () {
      final store = MemoryKeyValueStore();
      final container = ProviderContainer(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      container
          .read(appearanceProvider.notifier)
          .setPreset(ThemePreset.classic);
      expect(container.read(appearanceProvider).density, ChatDensity.compact);
      // Density can still be changed back.
      container
          .read(appearanceProvider.notifier)
          .setDensity(ChatDensity.comfortable);
      container
          .read(appearanceProvider.notifier)
          .setPreset(ThemePreset.classic);
      expect(
        container.read(appearanceProvider).density,
        ChatDensity.comfortable,
      );
    });
  });

  testWidgets('pick an accent and density; remembered on the next launch', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    Future<void> launch() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    await launch();
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    BuildContext ctx() => tester.element(find.byType(Scaffold).last);
    expect(Theme.of(ctx()).colorScheme.primary, AccentColor.indigo.light);

    await tester.tap(find.bySemanticsLabel('Teal accent'));
    await tester.pumpAndSettle();
    expect(Theme.of(ctx()).colorScheme.primary, AccentColor.teal.light);
    expect(AppTokens.of(ctx()).accent, AccentColor.teal.light);

    await tester.tap(find.text('Compact'));
    await tester.pumpAndSettle();
    expect(find.textContaining('HH:MM'), findsOneWidget);

    await launch();
    expect(Theme.of(ctx()).colorScheme.primary, AccentColor.teal.light);
    final saved =
        jsonDecode(store.getString('appearance')!) as Map<String, Object?>;
    expect(saved['accent'], 'teal');
    expect(saved['density'], 'compact');
  });

  testWidgets('the accent picker is off for themes with their own colours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [keyValueStoreProvider.overrideWithValue(store)],
        child: const IrcApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Classic mIRC'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Classic mIRC keeps its own colours'),
      findsOneWidget,
    );
    await tester.tap(find.bySemanticsLabel('Teal accent'));
    await tester.pumpAndSettle();
    final saved =
        jsonDecode(store.getString('appearance')!) as Map<String, Object?>;
    expect(saved['accent'], 'indigo');
    expect(saved['density'], 'compact');
  });

  testWidgets('Comfortable shows avatars in the chat list; Compact does not', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
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
      ..add(':me!u@h JOIN #linux')
      ..add(':s 353 me = #linux :@me +alice bob')
      ..add(':s 366 me #linux :End of /NAMES list.')
      ..add(':carol!c@h PRIVMSG me :psst')
      ..add(':bob!b@h PRIVMSG #linux :me: hello');
    await tester.pumpAndSettle();

    // Chat list: room and private chat avatars; people list: role rings.
    expect(find.byType(RoomAvatar), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is NickAvatar && w.nick == 'carol'),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is NickAvatar && w.nick == 'me' && w.role == NickRole.op,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is NickAvatar && w.nick == 'alice' && w.role == NickRole.voiced,
      ),
      findsOneWidget,
    );
    // carol's unread private message gets a badge.
    expect(find.byType(UnreadBadge), findsWidgets);

    // Compact: icons as before, no avatars.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    container.read(appearanceProvider.notifier).setDensity(ChatDensity.compact);
    await tester.pumpAndSettle();
    expect(find.byType(RoomAvatar), findsNothing);
    expect(find.byType(NickAvatar), findsNothing);
    expect(find.byIcon(Icons.tag), findsOneWidget);
  });
}
