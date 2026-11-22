/// IRCade design tokens: colours, spacing, radii, type and motion.
///
/// Values come from `docs/design/ui-redesign.md`. Widgets read colours with
/// `AppTokens.of(context)` and sizes from [Insets], [Radii], [TypeScale] and
/// [Motion], so a theme change restyles everything in one place.
library;

import 'package:material_ui/material_ui.dart';

/// Accent colours people can pick for the Default theme. Each has a light
/// and a dark version; a test checks they read at 4.5:1 or better on the
/// chat background and under their own text colour.
enum AccentColor {
  indigo('Indigo', Color(0xFF5B5BF0), Color(0xFF8B8BFF)),
  blue('Blue', Color(0xFF1F6FEB), Color(0xFF6CB6FF)),
  teal('Teal', Color(0xFF0B7A75), Color(0xFF3DD6C8)),
  green('Green', Color(0xFF1E7F3C), Color(0xFF5BD17E)),
  orange('Orange', Color(0xFFB54708), Color(0xFFFFA45C)),
  red('Red', Color(0xFFC42B4A), Color(0xFFFF8095)),
  pink('Pink', Color(0xFFB8327D), Color(0xFFFF8AC9)),
  purple('Purple', Color(0xFF7A3FD1), Color(0xFFC29BFF));

  AccentColor(this.label, this.light, this.dark);

  final String label;
  final Color light;
  final Color dark;

  Color forBrightness(Brightness b) => b == Brightness.dark ? dark : light;
}

/// The colour roles every screen uses. See the token table in
/// `docs/design/ui-redesign.md`.
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  const AppTokens({
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceOverlay,
    required this.line,
    required this.textPrimary,
    required this.textMuted,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.onAccentSoft,
    required this.mention,
    required this.onMention,
    required this.mentionBar,
    required this.mentionSoft,
    required this.success,
    required this.op,
    required this.opText,
    required this.squareCorners,
  });

  /// The Default (Indigo) tokens, optionally with another [accent].
  factory AppTokens.indigo(
    Brightness brightness, {
    AccentColor accent = AccentColor.indigo,
  }) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF0F1117) : const Color(0xFFFFFFFF);
    return AppTokens.derive(
      brightness: brightness,
      surface: surface,
      surfaceRaised: dark ? const Color(0xFF171A23) : const Color(0xFFF5F6FA),
      surfaceOverlay: dark ? const Color(0xFF232838) : const Color(0xFFECEEF5),
      line: dark ? const Color(0xFF262B37) : const Color(0xFFE3E6EE),
      textPrimary: dark ? const Color(0xFFE8EAF2) : const Color(0xFF14161C),
      textMuted: dark ? const Color(0xFF8E94A6) : const Color(0xFF5F6474),
      accent: accent.forBrightness(brightness),
      onAccent: dark ? const Color(0xFF0F1117) : const Color(0xFFFFFFFF),
    );
  }

  /// Tokens for a theme from its main colours. Mention, success and op
  /// colours are shared; text colours derived from them are adjusted until
  /// they read at 4.5:1.
  factory AppTokens.derive({
    required Brightness brightness,
    required Color surface,
    required Color surfaceRaised,
    required Color surfaceOverlay,
    required Color line,
    required Color textPrimary,
    required Color textMuted,
    required Color accent,
    required Color onAccent,
    bool squareCorners = false,
  }) {
    final dark = brightness == Brightness.dark;
    final accentSoft = accent.withValues(alpha: dark ? 0.16 : 0.12);
    final op = dark ? const Color(0xFFF5C15C) : const Color(0xFFA86A00);
    return AppTokens(
      surface: surface,
      surfaceRaised: surfaceRaised,
      surfaceOverlay: surfaceOverlay,
      line: line,
      textPrimary: textPrimary,
      textMuted: textMuted,
      accent: accent,
      onAccent: onAccent,
      accentSoft: accentSoft,
      onAccentSoft: readableOn(
        accent,
        Color.alphaBlend(accentSoft, surface),
        brightness,
      ),
      mention: dark ? const Color(0xFFFF8A7D) : const Color(0xFFC8372A),
      onMention: dark ? const Color(0xFF0F1117) : const Color(0xFFFFFFFF),
      // The spec's light coral (#FF6B5B) is 2.8:1 on white; nudged to the
      // 3:1 that bars and other non-text marks need.
      mentionBar: readableOn(
        dark ? const Color(0xFFFF8A7D) : const Color(0xFFFF6B5B),
        surface,
        brightness,
        ratio: 3,
      ),
      mentionSoft: dark
          ? const Color(0xFFFF8A7D).withValues(alpha: 0.12)
          : const Color(0xFFFF6B5B).withValues(alpha: 0.10),
      // Unchanged on Default's white; nudged to 3:1 on tinted surfaces.
      success: readableOn(
        dark ? const Color(0xFF3DD68C) : const Color(0xFF1FA971),
        surface,
        brightness,
        ratio: 3,
      ),
      op: op,
      opText: readableOn(op, surface, brightness),
      squareCorners: squareCorners,
    );
  }

  /// Chat background.
  final Color surface;

  /// Side panels, composer, cards.
  final Color surfaceRaised;

  /// Sheets, menus, other-person bubbles, icon buttons.
  final Color surfaceOverlay;

  /// Dividers and borders.
  final Color line;

  /// Messages and titles.
  final Color textPrimary;

  /// Timestamps, events, labels.
  final Color textMuted;

  /// Buttons, links, unread badge, own bubbles, active tab.
  final Color accent;

  /// Text and icons on [accent].
  final Color onAccent;

  /// Selected rows and room avatars (translucent [accent]).
  final Color accentSoft;

  /// Text on [accentSoft]: [accent], darkened (light) or lightened (dark)
  /// just enough to read at 4.5:1.
  final Color onAccentSoft;

  /// Mention badge.
  final Color mention;

  /// Text on [mention].
  final Color onMention;

  /// The 3-pt bar beside a line that mentions you, and the unread divider.
  final Color mentionBar;

  /// Background of a line or row that mentions you.
  final Color mentionSoft;

  /// Online dot, call accept.
  final Color success;

  /// Operator ring (a decoration, 3:1).
  final Color op;

  /// Operator badge text: [op] adjusted to read at 4.5:1 on [surface].
  final Color opText;

  /// Classic mIRC: square corners on avatars, badges and cards.
  final bool squareCorners;

  /// Corner radius for this theme: [rounded], or 2 when [squareCorners].
  double radius(double rounded) => squareCorners ? 2 : rounded;

  /// [color] adjusted to read as text (4.5:1) on [background], [surface]
  /// by default. Translucent backgrounds are taken over [surface].
  Color readable(Color color, [Color? background]) {
    final bg = background == null
        ? surface
        : Color.alphaBlend(background, surface);
    return readableOn(
      color,
      bg,
      bg.computeLuminance() < 0.5 ? Brightness.dark : Brightness.light,
    );
  }

  // A lookup like Theme.of, not a constructor.
  // ignore: prefer_constructors_over_static_methods
  static AppTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppTokens>() ?? AppTokens.indigo(theme.brightness);
  }

  /// [color] moved towards black (light) or white (dark) until it reads at
  /// [ratio] on [background]. Returns [color] unchanged if it already does.
  static Color readableOn(
    Color color,
    Color background,
    Brightness brightness, {
    double ratio = 4.5,
  }) {
    final target = brightness == Brightness.dark ? Colors.white : Colors.black;
    var c = color.withValues(alpha: 1);
    for (var t = 0.0; t <= 1; t += 0.02) {
      c = Color.lerp(color.withValues(alpha: 1), target, t)!;
      if (tokenContrast(c, background) >= ratio) return c;
    }
    return target;
  }

  @override
  AppTokens copyWith({
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceOverlay,
    Color? line,
    Color? textPrimary,
    Color? textMuted,
    Color? accent,
    Color? onAccent,
    Color? accentSoft,
    Color? onAccentSoft,
    Color? mention,
    Color? onMention,
    Color? mentionBar,
    Color? mentionSoft,
    Color? success,
    Color? op,
    Color? opText,
    bool? squareCorners,
  }) => AppTokens(
    surface: surface ?? this.surface,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceOverlay: surfaceOverlay ?? this.surfaceOverlay,
    line: line ?? this.line,
    textPrimary: textPrimary ?? this.textPrimary,
    textMuted: textMuted ?? this.textMuted,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    accentSoft: accentSoft ?? this.accentSoft,
    onAccentSoft: onAccentSoft ?? this.onAccentSoft,
    mention: mention ?? this.mention,
    onMention: onMention ?? this.onMention,
    mentionBar: mentionBar ?? this.mentionBar,
    mentionSoft: mentionSoft ?? this.mentionSoft,
    success: success ?? this.success,
    op: op ?? this.op,
    opText: opText ?? this.opText,
    squareCorners: squareCorners ?? this.squareCorners,
  );

  @override
  AppTokens lerp(AppTokens? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTokens(
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceOverlay: l(surfaceOverlay, other.surfaceOverlay),
      line: l(line, other.line),
      textPrimary: l(textPrimary, other.textPrimary),
      textMuted: l(textMuted, other.textMuted),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      accentSoft: l(accentSoft, other.accentSoft),
      onAccentSoft: l(onAccentSoft, other.onAccentSoft),
      mention: l(mention, other.mention),
      onMention: l(onMention, other.onMention),
      mentionBar: l(mentionBar, other.mentionBar),
      mentionSoft: l(mentionSoft, other.mentionSoft),
      success: l(success, other.success),
      op: l(op, other.op),
      opText: l(opText, other.opText),
      squareCorners: t < 0.5 ? squareCorners : other.squareCorners,
    );
  }
}

/// WCAG contrast ratio (1 to 21). Translucent colours are measured as drawn
/// over [b].
double tokenContrast(Color a, Color b) {
  final fg = a.a < 1 ? Color.alphaBlend(a, b) : a;
  final la = fg.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Spacing on a 4-pt grid.
abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Read through `AppTokens.radius` so Classic mIRC can
/// square them off.
abstract final class Radii {
  static const double chip = 8;
  static const double card = 12;
  static const double composer = 18;
  static const double bubble = 20;
  static const double bubbleTail = 6;
}

/// Type scale (size / line height). Sizes scale with the app's text-size
/// setting and the device's text size because they go through Text.
abstract final class TypeScale {
  static const title = TextStyle(
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w600,
  );
  static const heading = TextStyle(
    fontSize: 17,
    height: 22 / 17,
    fontWeight: FontWeight.w600,
  );
  static const body = TextStyle(fontSize: 15, height: 21 / 15);
  static const meta = TextStyle(fontSize: 12, height: 16 / 12);
  static const code = TextStyle(
    fontSize: 14,
    height: 20 / 14,
    fontFamily: 'monospace',
    fontFamilyFallback: ['Menlo', 'Roboto Mono', 'Courier'],
  );
}

/// Animation timing: 150 to 250 ms ease-out, off when the device asks for
/// reduced motion.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 250);
  static const Curve curve = Curves.easeOut;

  /// [d], or zero when the device has reduce motion on.
  static Duration of(BuildContext context, [Duration d = base]) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}
