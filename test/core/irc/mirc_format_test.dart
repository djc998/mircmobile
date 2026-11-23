import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/mirc_format.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('plain text is one plain run', () {
    final runs = parseMirc('hello there');
    expect(runs, hasLength(1));
    expect(runs.single.text, 'hello there');
    expect(runs.single.plain, isTrue);
    expect(parseMirc(''), isEmpty);
  });

  test('styles toggle', () {
    final runs = parseMirc('a\x02b\x1Dc\x02d\x1D\x1Fe\x1F\x1Ef\x1E\x11g');
    expect(runs.map((r) => r.text).join(), 'abcdefg');
    final b = runs.firstWhere((r) => r.text == 'b');
    expect(b.bold && !b.italic, isTrue);
    final c = runs.firstWhere((r) => r.text == 'c');
    expect(c.bold && c.italic, isTrue);
    final d = runs.firstWhere((r) => r.text == 'd');
    expect(!d.bold && d.italic, isTrue);
    expect(runs.firstWhere((r) => r.text == 'e').underline, isTrue);
    expect(runs.firstWhere((r) => r.text == 'f').strike, isTrue);
    expect(runs.firstWhere((r) => r.text == 'g').mono, isTrue);
  });

  test('colour codes: fg, fg,bg, two digits, bare reset', () {
    final runs = parseMirc('\x034red\x0312,8blue on yellow\x03 plain');
    expect(runs[0].text, 'red');
    expect(runs[0].foreground, mircBaseColors[4]);
    expect(runs[0].background, isNull);
    expect(runs[1].text, 'blue on yellow');
    expect(runs[1].foreground, mircBaseColors[12]);
    expect(runs[1].background, mircBaseColors[8]);
    expect(runs[2].text, ' plain');
    expect(runs[2].plain, isTrue);
  });

  test('at most two digits; a comma without a digit is text', () {
    var runs = parseMirc('\x03123');
    expect(runs.single.text, '3');
    expect(runs.single.foreground, mircBaseColors[12]);
    runs = parseMirc('\x034,hi');
    expect(runs.single.text, ',hi');
    expect(runs.single.foreground, mircBaseColors[4]);
    // \x03,5 is a reset then ",5".
    runs = parseMirc('\x03,5x');
    expect(runs.single.text, ',5x');
    expect(runs.single.plain, isTrue);
  });

  test('99 is the default colour; extended colours 16–98', () {
    expect(parseMirc('\x0399,99x').single.plain, isTrue);
    expect(mircColor(16), const Color(0xFF470000));
    expect(mircColor(98), const Color(0xFFFFFFFF));
    expect(mircColor(99), isNull);
    expect(mircColor(52), const Color(0xFFFF0000));
  });

  test('hex colours', () {
    final runs = parseMirc('\x04FF8800,000000orange\x04 back');
    expect(runs[0].foreground, const Color(0xFFFF8800));
    expect(runs[0].background, const Color(0xFF000000));
    expect(runs[1].plain, isTrue);
    expect(parseMirc('\x04zz').single.text, 'zz');
  });

  test(r'\x0F resets everything; reverse swaps colours', () {
    final runs = parseMirc('\x02\x034bold red\x0Fplain');
    expect(runs[0].bold, isTrue);
    expect(runs[1].plain, isTrue);
    final rev = parseMirc('\x034,1\x16swapped');
    expect(rev.single.foreground, mircBaseColors[1]);
    expect(rev.single.background, mircBaseColors[4]);
    // Reverse with no colours: markers for the normal colours, swapped.
    final plainRev = parseMirc('\x16inverted').single;
    expect(isReverseBackground(plainRev.foreground), isTrue);
    expect(isReverseForeground(plainRev.background), isTrue);
  });
}
