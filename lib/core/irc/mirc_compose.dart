/// Writing mIRC formatting: wrapping the selection (or the cursor) in
/// codes, for the composer's format menu and Cmd/Ctrl+B/I/U.
library;

import 'package:material_ui/material_ui.dart'
    show
        BuildContext,
        TextEditingController,
        TextEditingValue,
        TextSelection,
        TextSpan,
        TextStyle;

/// A style the composer can add.
enum MircStyle {
  bold('\x02', 'Bold'),
  italic('\x1D', 'Italic'),
  underline('\x1F', 'Underline'),
  strike('\x1E', 'Strikethrough');

  MircStyle(this.code, this.label);

  final String code;
  final String label;
}

/// Names of the 16 standard colours, for the palette and screen readers.
const List<String> mircColorNames = [
  'White',
  'Black',
  'Navy',
  'Green',
  'Red',
  'Maroon',
  'Purple',
  'Orange',
  'Yellow',
  'Lime',
  'Teal',
  'Aqua',
  'Blue',
  'Pink',
  'Grey',
  'Silver',
];

/// The code that starts colour [index] (0–15), always two digits so a
/// digit typed right after isn't read as part of the colour.
String colorCode(int index) => '\x03${index.toString().padLeft(2, '0')}';

/// Resets every style and colour.
const String resetCode = '\x0F';

/// [value] with [open] … [close] around the selection, keeping the same
/// text selected; with nothing selected, [open] goes in at the cursor so
/// what's typed next is formatted.
TextEditingValue wrapSelection(
  TextEditingValue value,
  String open,
  String close,
) {
  final text = value.text;
  final sel = value.selection.isValid
      ? value.selection
      : TextSelection.collapsed(offset: text.length);
  final start = sel.start;
  final end = sel.end;
  if (sel.isCollapsed) {
    final next = text.replaceRange(start, start, open);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + open.length),
    );
  }
  final next =
      text.substring(0, start) +
      open +
      text.substring(start, end) +
      close +
      text.substring(end);
  return TextEditingValue(
    text: next,
    selection: TextSelection(
      baseOffset: start + open.length,
      extentOffset: end + open.length,
    ),
  );
}

/// Adds [style] to the selection (or from the cursor on).
TextEditingValue applyStyle(TextEditingValue value, MircStyle style) =>
    wrapSelection(value, style.code, style.code);

/// Colours the selection with colour [index] (or from the cursor on).
TextEditingValue applyColor(TextEditingValue value, int index) =>
    wrapSelection(value, colorCode(index), '\x03');

/// Inserts a reset at the cursor: what's typed next is plain.
TextEditingValue applyReset(TextEditingValue value) =>
    wrapSelection(value, resetCode, '');

/// Whether [text] has any formatting codes (shows the preview).
bool hasMircCodes(String text) =>
    text.contains(RegExp('[\x02\x03\x04\x0F\x11\x16\x1D\x1E\x1F]'));

/// What each code looks like in the message field: one visible letter per
/// code character, so editing and the cursor work as usual. Colour digits
/// after `K` are drawn the same way.
const Map<int, String> _markers = {
  0x02: 'B',
  0x1D: 'I',
  0x1F: 'U',
  0x1E: 'S',
  0x11: 'M',
  0x16: 'R',
  0x0F: 'O',
  0x03: 'K',
  0x04: '#',
};

/// A text controller that shows formatting codes as small markers instead
/// of invisible characters. [markerStyle] styles them.
class MircEditingController extends TextEditingController {
  MircEditingController({this.markerStyle = const TextStyle()});

  TextStyle markerStyle;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final composing = value.composing;
    if ((withComposing && composing.isValid && !composing.isCollapsed) ||
        !hasMircCodes(text)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <TextSpan>[];
    final plain = StringBuffer();
    void flush() {
      if (plain.isEmpty) return;
      spans.add(TextSpan(text: plain.toString()));
      plain.clear();
    }

    final units = text.codeUnits;
    var i = 0;
    while (i < units.length) {
      final marker = _markers[units[i]];
      if (marker == null) {
        plain.writeCharCode(units[i]);
        i++;
        continue;
      }
      flush();
      final code = StringBuffer(marker);
      final start = i++;
      if (units[start] == 0x03) {
        // Up to two digits, then optionally ,NN: part of the code.
        var n = 0;
        while (i < units.length && n < 2 && _digit(units[i])) {
          code.writeCharCode(units[i++]);
          n++;
        }
        if (n > 0 &&
            i + 1 < units.length &&
            units[i] == 0x2C &&
            _digit(units[i + 1])) {
          code.writeCharCode(units[i++]);
          n = 0;
          while (i < units.length && n < 2 && _digit(units[i])) {
            code.writeCharCode(units[i++]);
            n++;
          }
        }
      }
      spans.add(TextSpan(text: code.toString(), style: markerStyle));
    }
    flush();
    return TextSpan(style: style, children: spans);
  }

  static bool _digit(int c) => c >= 0x30 && c <= 0x39;
}
