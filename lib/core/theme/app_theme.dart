import 'package:material_ui/material_ui.dart';

/// Material 3 theme with a nod to classic mIRC navy and teal.
class AppTheme {
  const AppTheme._();

  static const Color seed = Color(0xFF00007F); // mIRC navy

  static ThemeData light() => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: seed),
    useMaterial3: true,
  );

  static ThemeData dark() => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  /// Stable per-nick colour, like mIRC's nick colouring.
  static Color nickColor(String nick, Brightness brightness) {
    const palette = [
      Color(0xFF0B6E4F),
      Color(0xFF7F0000),
      Color(0xFF9C009C),
      Color(0xFFB35900),
      Color(0xFF00807F),
      Color(0xFF00007F),
      Color(0xFF6A1B9A),
      Color(0xFF2E7D32),
    ];
    const darkPalette = [
      Color(0xFF6FE3B5),
      Color(0xFFFF8A80),
      Color(0xFFF48FB1),
      Color(0xFFFFB74D),
      Color(0xFF4DD0E1),
      Color(0xFF90CAF9),
      Color(0xFFCE93D8),
      Color(0xFFA5D6A7),
    ];
    final hash = nick.toLowerCase().codeUnits.fold<int>(
      0,
      (h, c) => (h * 31 + c) & 0x7fffffff,
    );
    final colors = brightness == Brightness.dark ? darkPalette : palette;
    return colors[hash % colors.length];
  }
}
