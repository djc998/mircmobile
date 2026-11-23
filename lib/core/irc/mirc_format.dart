/// Parses mIRC colour and style codes into styled runs of text.
///
/// Codes (see https://modern.ircdocs.horse/formatting):
/// - `\x02` bold, `\x1D` italic, `\x1F` underline, `\x1E` strikethrough,
///   `\x11` monospace, `\x16` reverse (swap colours): each toggles.
/// - `\x03` colour: `\x03F` or `\x03F,B` with one- or two-digit indexes
///   (0–98). A bare `\x03` resets colours.
/// - `\x04` hex colour: `\x04RRGGBB` or `\x04RRGGBB,RRGGBB`.
/// - `\x0F` resets everything.
library;

import 'dart:ui' show Color;

/// One stretch of text with the same style.
class MircRun {
  const MircRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.mono = false,
    this.foreground,
    this.background,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;
  final bool mono;

  /// Null means the normal text or background colour.
  final Color? foreground;
  final Color? background;

  bool get plain =>
      !bold &&
      !italic &&
      !underline &&
      !strike &&
      !mono &&
      foreground == null &&
      background == null;

  @override
  String toString() =>
      'MircRun("$text"${bold ? ' bold' : ''}${italic ? ' italic' : ''}'
      '${underline ? ' underline' : ''}${strike ? ' strike' : ''}'
      '${mono ? ' mono' : ''}'
      '${foreground == null ? '' : ' fg=${_hex(foreground!)}'}'
      '${background == null ? '' : ' bg=${_hex(background!)}'})';

  static String _hex(Color c) =>
      c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
}

/// The 16 standard mIRC colours (0–15).
const List<Color> mircBaseColors = [
  Color(0xFFFFFFFF), // 0 white
  Color(0xFF000000), // 1 black
  Color(0xFF00007F), // 2 blue (navy)
  Color(0xFF009300), // 3 green
  Color(0xFFFF0000), // 4 red
  Color(0xFF7F0000), // 5 brown (maroon)
  Color(0xFF9C009C), // 6 magenta (purple)
  Color(0xFFFC7F00), // 7 orange (olive)
  Color(0xFFFFFF00), // 8 yellow
  Color(0xFF00FC00), // 9 light green (lime)
  Color(0xFF009393), // 10 cyan (teal)
  Color(0xFF00FFFF), // 11 light cyan (aqua)
  Color(0xFF0000FC), // 12 light blue (royal)
  Color(0xFFFF00FF), // 13 pink (light purple)
  Color(0xFF7F7F7F), // 14 grey
  Color(0xFFD2D2D2), // 15 light grey (silver)
];

/// The extended colours 16–98 (mIRC 7.x / modern IRC clients).
const List<int> _extended = [
  0x470000, 0x472100, 0x474700, 0x324700, 0x004700, 0x00472c, 0x004747,
  0x002747, 0x000047, 0x2e0047, 0x470047, 0x47002a, //
  0x740000, 0x743a00, 0x747400, 0x517400, 0x007400, 0x007449, 0x007474,
  0x004074, 0x000074, 0x4b0074, 0x740074, 0x740045, //
  0xb50000, 0xb56300, 0xb5b500, 0x7db500, 0x00b500, 0x00b571, 0x00b5b5,
  0x0063b5, 0x0000b5, 0x7500b5, 0xb500b5, 0xb5006b, //
  0xff0000, 0xff8c00, 0xffff00, 0xb2ff00, 0x00ff00, 0x00ffa0, 0x00ffff,
  0x008cff, 0x0000ff, 0xa500ff, 0xff00ff, 0xff0098, //
  0xff5959, 0xffb459, 0xffff71, 0xcfff60, 0x6fff6f, 0x65ffc9, 0x6dffff,
  0x59b4ff, 0x5959ff, 0xc459ff, 0xff66ff, 0xff59bc, //
  0xff9c9c, 0xffd39c, 0xffff9c, 0xe2ff9c, 0x9cff9c, 0x9cffdb, 0x9cffff,
  0x9cd3ff, 0x9c9cff, 0xdc9cff, 0xff9cff, 0xff94d3, //
  0x000000, 0x131313, 0x282828, 0x363636, 0x4d4d4d, 0x656565, 0x818181,
  0x9f9f9f, 0xbcbcbc, 0xe2e2e2, 0xffffff,
];

/// The colour for mIRC index [i], or null for 99 ("default") and out of
/// range.
Color? mircColor(int i) {
  if (i >= 0 && i < 16) return mircBaseColors[i];
  if (i >= 16 && i < 16 + _extended.length) {
    return Color(0xFF000000 | _extended[i - 16]);
  }
  return null;
}

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

bool _isHex(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

/// Splits [text] into runs. Adjacent text with the same style is one run;
/// the codes themselves are dropped. Text with no codes is one plain run.
List<MircRun> parseMirc(String text) {
  final runs = <MircRun>[];
  final buf = StringBuffer();
  var bold = false;
  var italic = false;
  var underline = false;
  var strike = false;
  var mono = false;
  var reverse = false;
  Color? fg;
  Color? bg;

  void flush() {
    if (buf.isEmpty) return;
    runs.add(
      MircRun(
        buf.toString(),
        bold: bold,
        italic: italic,
        underline: underline,
        strike: strike,
        mono: mono,
        // Reverse swaps the colours; with none set it swaps the defaults,
        // which the renderer shows as inverted text.
        foreground: reverse ? (bg ?? _reverseFg) : fg,
        background: reverse ? (fg ?? _reverseBg) : bg,
      ),
    );
    buf.clear();
  }

  final units = text.codeUnits;
  var i = 0;
  while (i < units.length) {
    final c = units[i];
    switch (c) {
      case 0x02 || 0x1D || 0x1F || 0x1E || 0x11 || 0x16 || 0x0F:
        flush();
        switch (c) {
          case 0x02:
            bold = !bold;
          case 0x1D:
            italic = !italic;
          case 0x1F:
            underline = !underline;
          case 0x1E:
            strike = !strike;
          case 0x11:
            mono = !mono;
          case 0x16:
            reverse = !reverse;
          case _:
            bold = italic = underline = strike = mono = reverse = false;
            fg = bg = null;
        }
        i++;
      case 0x03:
        flush();
        i++;
        // Up to two digits of foreground, then optionally ,BB.
        var start = i;
        while (i < units.length && i - start < 2 && _isDigit(units[i])) {
          i++;
        }
        if (i == start) {
          // A bare \x03 resets both colours.
          fg = bg = null;
          break;
        }
        final f = int.parse(String.fromCharCodes(units, start, i));
        fg = f == 99 ? null : mircColor(f) ?? fg;
        if (i + 1 < units.length &&
            units[i] == 0x2C /* , */ &&
            _isDigit(units[i + 1])) {
          start = ++i;
          while (i < units.length && i - start < 2 && _isDigit(units[i])) {
            i++;
          }
          final b = int.parse(String.fromCharCodes(units, start, i));
          bg = b == 99 ? null : mircColor(b) ?? bg;
        }
      case 0x04:
        flush();
        i++;
        bool hexAt(int at) {
          if (at + 6 > units.length) return false;
          for (var k = at; k < at + 6; k++) {
            if (!_isHex(units[k])) return false;
          }
          return true;
        }

        Color hex(int at) => Color(
          0xFF000000 |
              int.parse(String.fromCharCodes(units, at, at + 6), radix: 16),
        );
        if (!hexAt(i)) {
          fg = bg = null;
          break;
        }
        fg = hex(i);
        i += 6;
        if (i < units.length && units[i] == 0x2C && hexAt(i + 1)) {
          bg = hex(i + 1);
          i += 7;
        }
      case _:
        buf.writeCharCode(c);
        i++;
    }
  }
  flush();
  return runs;
}

/// Markers for "reverse with no colours set": the renderer swaps the
/// normal text and background colours.
const Color _reverseFg = Color(0x01000000);
const Color _reverseBg = Color(0x01FFFFFF);

/// Whether [c] stands for "the normal background colour" (reverse).
bool isReverseBackground(Color? c) => c == _reverseFg;

/// Whether [c] stands for "the normal text colour" (reverse).
bool isReverseForeground(Color? c) => c == _reverseBg;
