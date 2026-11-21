import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final preset in ThemePreset.values) {
    for (final brightness in Brightness.values) {
      test('${preset.label} ${brightness.name}: chat colours are readable', () {
        final theme = AppTheme.build(preset, brightness);
        final bg = theme.colorScheme.surface;
        final chat = theme.extension<ChatColors>()!;
        final colors = {
          'event': chat.event,
          'notice': chat.notice,
          'action': chat.action,
          'error': theme.colorScheme.error,
          'text': theme.colorScheme.onSurface,
          'timestamp': theme.colorScheme.onSurfaceVariant,
          for (final (i, c) in chat.nicks.indexed) 'nick $i': c,
        };
        for (final MapEntry(:key, :value) in colors.entries) {
          expect(
            contrastRatio(value, bg),
            greaterThanOrEqualTo(4.5),
            reason: '$key $value on $bg',
          );
        }
      });
    }
  }
}
