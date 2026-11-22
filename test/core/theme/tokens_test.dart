import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Text pairs must read at 4.5:1 (WCAG AA). Dots, rings and bars are not
/// text and need 3:1 (WCAG 1.4.11).
void checkTokens(AppTokens t, String where) {
  final text = <String, (Color, Color)>{
    'textPrimary on surface': (t.textPrimary, t.surface),
    'textPrimary on surfaceRaised': (t.textPrimary, t.surfaceRaised),
    'textPrimary on surfaceOverlay': (t.textPrimary, t.surfaceOverlay),
    'textMuted on surface': (t.textMuted, t.surface),
    'textMuted on surfaceRaised': (t.textMuted, t.surfaceRaised),
    'textMuted on surfaceOverlay': (t.textMuted, t.surfaceOverlay),
    'accent on surface': (t.accent, t.surface),
    'onAccent on accent': (t.onAccent, t.accent),
    'onAccentSoft on accentSoft': (
      t.onAccentSoft,
      Color.alphaBlend(t.accentSoft, t.surface),
    ),
    'onMention on mention': (t.onMention, t.mention),
    'opText on surface': (t.opText, t.surface),
    'textPrimary on mentionSoft': (
      t.textPrimary,
      Color.alphaBlend(t.mentionSoft, t.surface),
    ),
  };
  for (final MapEntry(:key, value: (fg, bg)) in text.entries) {
    expect(
      tokenContrast(fg, bg),
      greaterThanOrEqualTo(4.5),
      reason: '$where: $key ($fg on $bg)',
    );
  }
  final graphics = <String, (Color, Color)>{
    'success dot on surface': (t.success, t.surface),
    'op ring on surface': (t.op, t.surface),
    'mention bar on surface': (t.mentionBar, t.surface),
    'accent ring on surface': (t.accent, t.surface),
  };
  for (final MapEntry(:key, value: (fg, bg)) in graphics.entries) {
    expect(
      tokenContrast(fg, bg),
      greaterThanOrEqualTo(3),
      reason: '$where: $key ($fg on $bg)',
    );
  }
}

void main() {
  group('Default (Indigo) tokens match the spec', () {
    test('light', () {
      final t = AppTokens.indigo(Brightness.light);
      expect(t.surface, const Color(0xFFFFFFFF));
      expect(t.surfaceRaised, const Color(0xFFF5F6FA));
      expect(t.surfaceOverlay, const Color(0xFFECEEF5));
      expect(t.line, const Color(0xFFE3E6EE));
      expect(t.textPrimary, const Color(0xFF14161C));
      expect(t.textMuted, const Color(0xFF5F6474));
      expect(t.accent, const Color(0xFF5B5BF0));
      expect(t.onAccent, const Color(0xFFFFFFFF));
      expect(t.mention, const Color(0xFFC8372A));
      expect(tokenContrast(t.mentionBar, t.surface), greaterThanOrEqualTo(3));
      expect(t.success, const Color(0xFF1FA971));
      expect(t.op, const Color(0xFFA86A00));
      expect(t.accentSoft.a, closeTo(0.12, 0.01));
    });

    test('dark', () {
      final t = AppTokens.indigo(Brightness.dark);
      expect(t.surface, const Color(0xFF0F1117));
      expect(t.surfaceRaised, const Color(0xFF171A23));
      expect(t.surfaceOverlay, const Color(0xFF232838));
      expect(t.line, const Color(0xFF262B37));
      expect(t.textPrimary, const Color(0xFFE8EAF2));
      expect(t.textMuted, const Color(0xFF8E94A6));
      expect(t.accent, const Color(0xFF8B8BFF));
      expect(t.onAccent, const Color(0xFF0F1117));
      expect(t.mention, const Color(0xFFFF8A7D));
      expect(t.success, const Color(0xFF3DD68C));
      expect(t.op, const Color(0xFFF5C15C));
      expect(t.accentSoft.a, closeTo(0.16, 0.01));
    });
  });

  for (final accent in AccentColor.values) {
    for (final brightness in Brightness.values) {
      test('${accent.label} accent, ${brightness.name}: readable', () {
        checkTokens(
          AppTokens.indigo(brightness, accent: accent),
          '${accent.label} ${brightness.name}',
        );
      });
    }
  }

  for (final preset in ThemePreset.values) {
    for (final brightness in Brightness.values) {
      test('${preset.label} ${brightness.name}: every token pair readable', () {
        final theme = AppTheme.build(preset, brightness);
        final t = theme.extension<AppTokens>()!;
        checkTokens(t, '${preset.label} ${brightness.name}');
        expect(t.squareCorners, preset == ThemePreset.classic);
        expect(theme.colorScheme.surface, t.surface);
      });

      test('${preset.label} ${brightness.name}: nick avatars readable', () {
        final theme = AppTheme.build(preset, brightness);
        final t = theme.extension<AppTokens>()!;
        final chat = theme.extension<ChatColors>()!;
        for (final nick in chat.nicks) {
          final fill = Color.alphaBlend(
            nick.withValues(alpha: brightness == Brightness.dark ? .2 : .12),
            t.surface,
          );
          final text = AppTokens.readableOn(nick, fill, brightness);
          expect(tokenContrast(text, fill), greaterThanOrEqualTo(4.5));
        }
      });
    }
  }

  test('the accent recolours only the Default theme', () {
    final pink = AppTheme.build(
      ThemePreset.indigo,
      Brightness.light,
      accent: AccentColor.pink,
    );
    expect(pink.colorScheme.primary, AccentColor.pink.light);
    final classic = AppTheme.build(
      ThemePreset.classic,
      Brightness.light,
      accent: AccentColor.pink,
    );
    expect(classic.colorScheme.primary, isNot(AccentColor.pink.light));
  });

  test('Classic mIRC has square corners', () {
    final theme = AppTheme.build(ThemePreset.classic, Brightness.light);
    final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(2));
    expect(theme.extension<AppTokens>()!.radius(12), 2);
    expect(
      AppTheme.build(
        ThemePreset.indigo,
        Brightness.light,
      ).extension<AppTokens>()!.radius(12),
      12,
    );
  });

  test('type scale follows the spec', () {
    final text = AppTheme.build(ThemePreset.indigo, Brightness.light).textTheme;
    expect(text.titleLarge!.fontSize, 22);
    expect(text.titleLarge!.fontWeight, FontWeight.w600);
    expect(text.titleMedium!.fontSize, 17);
    expect(text.bodyMedium!.fontSize, 15);
    expect(text.bodySmall!.fontSize, 12);
  });

  test('readableOn only moves a colour as far as it must', () {
    const white = Color(0xFFFFFFFF);
    // Already readable: unchanged.
    expect(
      AppTokens.readableOn(const Color(0xFF14161C), white, Brightness.light),
      const Color(0xFF14161C),
    );
    // Op gold on white is 4.44:1; it gets a little darker.
    final op = AppTokens.readableOn(
      const Color(0xFFA86A00),
      white,
      Brightness.light,
    );
    expect(tokenContrast(op, white), greaterThanOrEqualTo(4.5));
    expect(tokenContrast(op, white), lessThan(5.2));
  });

  testWidgets('Motion turns off with reduce motion', (tester) async {
    late Duration on;
    late Duration off;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          on = Motion.of(context);
          return MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(
              builder: (context) {
                off = Motion.of(context);
                return const SizedBox();
              },
            ),
          );
        },
      ),
    );
    expect(on, Motion.base);
    expect(off, Duration.zero);
  });
}
