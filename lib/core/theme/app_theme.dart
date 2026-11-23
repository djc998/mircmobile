import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Light, dark or follow the system.
enum AppearanceMode { system, light, dark }

/// Built-in colour themes. Each has a light and a dark version.
enum ThemePreset {
  indigo('Default', 'Clean and modern, with the accent colour you pick'),
  classic('Classic mIRC', 'mIRC navy, square corners, compact lines'),
  midnight('Midnight', 'Deep blue, easy on the eyes at night'),
  solarized('Solarized', 'Warm, low-glare colours'),
  highContrast('High contrast', 'Black and white with bright colours');

  ThemePreset(this.label, this.description);

  final String label;
  final String description;
}

/// Colours for chat lines. Every colour reads at 4.5:1 or better on the
/// theme's background (WCAG AA), which a test checks.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.event,
    required this.notice,
    required this.action,
    required this.nicks,
  });

  /// Joins, parts, topic changes and other "•" lines.
  final Color event;

  /// Notices (`-nick- text`).
  final Color notice;

  /// `/me` actions.
  final Color action;

  /// Palette for nicknames; each nick always gets the same colour.
  final List<Color> nicks;

  static ChatColors of(BuildContext context) =>
      Theme.of(context).extension<ChatColors>() ??
      (Theme.of(context).brightness == Brightness.dark
          ? AppTheme._classicDark
          : AppTheme._classicLight);

  /// Stable per-nick colour, like mIRC's nick colouring.
  Color nickColor(String nick) {
    final hash = nick.toLowerCase().codeUnits.fold<int>(
      0,
      (h, c) => (h * 31 + c) & 0x7fffffff,
    );
    return nicks[hash % nicks.length];
  }

  @override
  ChatColors copyWith({
    Color? event,
    Color? notice,
    Color? action,
    List<Color>? nicks,
  }) => ChatColors(
    event: event ?? this.event,
    notice: notice ?? this.notice,
    action: action ?? this.action,
    nicks: nicks ?? this.nicks,
  );

  @override
  ChatColors lerp(ChatColors? other, double t) {
    if (other == null) return this;
    return ChatColors(
      event: Color.lerp(event, other.event, t)!,
      notice: Color.lerp(notice, other.notice, t)!,
      action: Color.lerp(action, other.action, t)!,
      nicks: t < 0.5 ? nicks : other.nicks,
    );
  }
}

/// Material 3 themes with readable chat colours.
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF00007F); // mIRC navy

  static const _lightNicks = [
    Color(0xFF0B6E4F),
    Color(0xFF9B1C1C),
    Color(0xFF8E1A8E),
    Color(0xFF8A4500),
    Color(0xFF00696A),
    Color(0xFF1A237E),
    Color(0xFF6A1B9A),
    Color(0xFF2E6B30),
  ];

  static const _darkNicks = [
    Color(0xFF6FE3B5),
    Color(0xFFFF8A80),
    Color(0xFFF48FB1),
    Color(0xFFFFB74D),
    Color(0xFF4DD0E1),
    Color(0xFF90CAF9),
    Color(0xFFCE93D8),
    Color(0xFFA5D6A7),
  ];

  static const _classicLight = ChatColors(
    event: Color(0xFF1B7A2B),
    notice: Color(0xFFA11D1D),
    action: Color(0xFF8E1A8E),
    nicks: _lightNicks,
  );

  static const _classicDark = ChatColors(
    event: Color(0xFF7CDB8A),
    notice: Color(0xFFFF8A80),
    action: Color(0xFFE6A6F2),
    nicks: _darkNicks,
  );

  /// The theme for [preset] in [brightness]. [accent] recolours the
  /// Default theme; the other themes keep their own colours.
  static ThemeData build(
    ThemePreset preset,
    Brightness brightness, {
    AccentColor accent = AccentColor.indigo,
  }) {
    final dark = brightness == Brightness.dark;
    switch (preset) {
      case ThemePreset.indigo:
        final t = AppTokens.indigo(brightness, accent: accent);
        final scheme =
            ColorScheme.fromSeed(
              seedColor: t.accent,
              brightness: brightness,
            ).copyWith(
              primary: t.accent,
              onPrimary: t.onAccent,
              surface: t.surface,
              onSurface: t.textPrimary,
              onSurfaceVariant: t.textMuted,
              outlineVariant: t.line,
              surfaceContainerLowest: t.surface,
              surfaceContainerLow: t.surfaceRaised,
              surfaceContainer: t.surfaceRaised,
              surfaceContainerHigh: t.surfaceOverlay,
              surfaceContainerHighest: t.surfaceOverlay,
            );
        return _theme(scheme, dark ? _classicDark : _classicLight, tokens: t);
      case ThemePreset.classic:
        return _theme(
          ColorScheme.fromSeed(seedColor: seed, brightness: brightness),
          dark ? _classicDark : _classicLight,
          squareCorners: true,
        );
      case ThemePreset.midnight:
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF3D5AFE),
          brightness: brightness,
        );
        return _theme(
          dark
              ? scheme.copyWith(
                  surface: const Color(0xFF0B1020),
                  onSurface: const Color(0xFFE3E7F5),
                  surfaceContainerHighest: const Color(0xFF1C2338),
                )
              : scheme,
          dark ? _classicDark : _classicLight,
        );
      case ThemePreset.solarized:
        final scheme = ColorScheme.fromSeed(
          seedColor: const Color(0xFF268BD2),
          brightness: brightness,
        );
        return _theme(
          dark
              ? scheme.copyWith(
                  surface: const Color(0xFF002B36),
                  onSurface: const Color(0xFFEEE8D5),
                  onSurfaceVariant: const Color(0xFFB4BFBF),
                  surfaceContainerHighest: const Color(0xFF073642),
                )
              : scheme.copyWith(
                  surface: const Color(0xFFFDF6E3),
                  onSurface: const Color(0xFF073642),
                  onSurfaceVariant: const Color(0xFF4F5F64),
                  surfaceContainerHighest: const Color(0xFFEEE8D5),
                ),
          dark
              ? const ChatColors(
                  event: Color(0xFFB5CC4A),
                  notice: Color(0xFFFF8F85),
                  action: Color(0xFFF08FCB),
                  nicks: _darkNicks,
                )
              : const ChatColors(
                  event: Color(0xFF4F6200),
                  notice: Color(0xFFA82522),
                  action: Color(0xFF962A6C),
                  nicks: _lightNicks,
                ),
        );
      case ThemePreset.highContrast:
        final scheme = dark
            ? const ColorScheme.highContrastDark()
            : const ColorScheme.highContrastLight();
        return _theme(
          dark
              ? scheme.copyWith(
                  surface: Colors.black,
                  onSurface: Colors.white,
                  error: const Color(0xFFFFB4AB),
                  onSurfaceVariant: const Color(0xFFE0E0E0),
                )
              : scheme.copyWith(
                  surface: Colors.white,
                  onSurface: Colors.black,
                  onSurfaceVariant: const Color(0xFF303030),
                ),
          dark
              ? const ChatColors(
                  event: Color(0xFF9CFF9C),
                  notice: Color(0xFFFFB3AD),
                  action: Color(0xFFF5B8FF),
                  nicks: [
                    Color(0xFF9CFFD8),
                    Color(0xFFFFB3AD),
                    Color(0xFFFFC2DC),
                    Color(0xFFFFD699),
                    Color(0xFF8FF0FF),
                    Color(0xFFB8DCFF),
                    Color(0xFFE8C2F0),
                    Color(0xFFC8F0C8),
                  ],
                )
              : const ChatColors(
                  event: Color(0xFF005A00),
                  notice: Color(0xFF8B0000),
                  action: Color(0xFF6A006A),
                  nicks: [
                    Color(0xFF004D35),
                    Color(0xFF7A0000),
                    Color(0xFF6A006A),
                    Color(0xFF6B3400),
                    Color(0xFF004F50),
                    Color(0xFF0D1660),
                    Color(0xFF4A0F70),
                    Color(0xFF1E4D20),
                  ],
                ),
        );
    }
  }

  /// Builds the [ThemeData]: [tokens] (derived from [scheme] if not given),
  /// the IRCage type scale, and square corners for Classic mIRC.
  static ThemeData _theme(
    ColorScheme scheme,
    ChatColors chat, {
    AppTokens? tokens,
    bool squareCorners = false,
  }) {
    final t =
        tokens ??
        AppTokens.derive(
          brightness: scheme.brightness,
          surface: scheme.surface,
          surfaceRaised: scheme.surfaceContainerLow,
          surfaceOverlay: scheme.surfaceContainerHighest,
          line: scheme.outlineVariant,
          textPrimary: scheme.onSurface,
          textMuted: scheme.onSurfaceVariant,
          accent: scheme.primary,
          onAccent: scheme.onPrimary,
          squareCorners: squareCorners,
        );
    final base = ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      useMaterial3: true,
      extensions: [chat, t],
    );
    final text = base.textTheme;
    final themed = base.copyWith(
      textTheme: text.copyWith(
        titleLarge: text.titleLarge!.merge(TypeScale.title),
        titleMedium: text.titleMedium!.merge(TypeScale.heading),
        bodyLarge: text.bodyLarge!.merge(TypeScale.body),
        bodyMedium: text.bodyMedium!.merge(TypeScale.body),
        bodySmall: text.bodySmall!.merge(TypeScale.meta),
      ),
    );
    if (!squareCorners) return themed;
    const square = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(2)),
    );
    final buttonShape = ButtonStyle(shape: WidgetStateProperty.all(square));
    return themed.copyWith(
      cardTheme: const CardThemeData(shape: square),
      chipTheme: const ChipThemeData(shape: square),
      dialogTheme: const DialogThemeData(shape: square),
      bottomSheetTheme: const BottomSheetThemeData(shape: square),
      popupMenuTheme: const PopupMenuThemeData(shape: square),
      filledButtonTheme: FilledButtonThemeData(style: buttonShape),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonShape),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonShape),
      textButtonTheme: TextButtonThemeData(style: buttonShape),
      segmentedButtonTheme: SegmentedButtonThemeData(style: buttonShape),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(2)),
        ),
      ),
    );
  }

  static ThemeData light() => build(ThemePreset.indigo, Brightness.light);
  static ThemeData dark() => build(ThemePreset.indigo, Brightness.dark);

  /// Stable per-nick colour in the classic palette.
  static Color nickColor(String nick, Brightness brightness) =>
      (brightness == Brightness.dark ? _classicDark : _classicLight).nickColor(
        nick,
      );
}

/// WCAG contrast ratio between two colours (1 to 21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
