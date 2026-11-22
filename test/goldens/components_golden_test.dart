import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:material_ui/material_ui.dart';

/// Light and dark goldens for each Phase 1 component, in the Default theme
/// and in Classic mIRC (square corners).
///
/// The images are made on macOS. Linux draws anti-aliased circle edges and
/// scaled text 2-3% differently, so these only run on macOS; the widget
/// tests in test/core/ui check colours, sizes and labels on every platform.
void main() {
  // Goldens are made and checked on macOS only (see above).
  final skip = !Platform.isMacOS;

  final components = <String, Widget>{
    'nick_avatar': const Wrap(
      spacing: 8,
      children: [
        NickAvatar(nick: 'alice'),
        NickAvatar(nick: 'dark_star', role: NickRole.op),
        NickAvatar(nick: 'MaraK', role: NickRole.voiced),
        NickAvatar(nick: 'kai', away: true),
        NickAvatar(nick: 'bob', size: 24),
      ],
    ),
    'room_avatar': const Wrap(
      spacing: 8,
      children: [
        RoomAvatar(name: '#linux'),
        RoomAvatar(name: '##chat'),
        RoomAvatar(name: '#2600', size: 60),
      ],
    ),
    'unread_badge': const Wrap(
      spacing: 8,
      children: [
        UnreadBadge(count: 3),
        UnreadBadge(count: 42),
        UnreadBadge(count: 120),
        UnreadBadge(count: 2, mention: true),
      ],
    ),
  };

  for (final MapEntry(key: name, value: widget) in components.entries) {
    for (final preset in [ThemePreset.indigo, ThemePreset.classic]) {
      for (final brightness in Brightness.values) {
        final file = '${name}_${preset.name}_${brightness.name}.png';
        testWidgets(file, skip: skip, (tester) async {
          final theme = AppTheme.build(preset, brightness);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    child: Container(
                      color: theme.colorScheme.surface,
                      padding: const EdgeInsets.all(12),
                      child: widget,
                    ),
                  ),
                ),
              ),
            ),
          );
          await expectLater(
            find.byType(RepaintBoundary).last,
            matchesGoldenFile(file),
          );
        });
      }
    }
  }
}
