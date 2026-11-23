import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/mirc_compose.dart';

TextEditingValue v(String text, int start, [int? end]) => TextEditingValue(
  text: text,
  selection: TextSelection(baseOffset: start, extentOffset: end ?? start),
);

void main() {
  test('wraps the selection and keeps it selected', () {
    final out = applyStyle(v('say hello now', 4, 9), MircStyle.bold);
    expect(out.text, 'say \x02hello\x02 now');
    expect(out.selection.textInside(out.text), 'hello');
  });

  test('no selection: the code goes in at the cursor', () {
    final out = applyStyle(v('hi ', 3), MircStyle.italic);
    expect(out.text, 'hi \x1D');
    expect(out.selection.baseOffset, 4);
  });

  test('colours use two digits so a digit after stays text', () {
    expect(colorCode(4), '\x0304');
    final out = applyColor(v('2 fast', 0, 1), 4);
    expect(out.text, '\x03042\x03 fast');
  });

  test('reset and invalid selections', () {
    expect(applyReset(v('ab', 1)).text, 'a\x0Fb');
    final noSel = applyStyle(
      const TextEditingValue(text: 'end'),
      MircStyle.underline,
    );
    expect(noSel.text, 'end\x1F');
  });

  test('hasMircCodes', () {
    expect(hasMircCodes('plain'), isFalse);
    expect(hasMircCodes('a\x02b'), isTrue);
    expect(hasMircCodes('\x0304red'), isTrue);
    expect(mircColorNames, hasLength(16));
  });
}
