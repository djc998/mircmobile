import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/mirc_text.dart';
import 'package:material_ui/material_ui.dart';

List<TextSpan> flat(List<InlineSpan> spans) => [
  for (final s in spans)
    if (s is TextSpan) ...[
      if (s.text != null) s,
      if (s.children != null) ...flat(s.children!),
    ],
];

void main() {
  for (final b in Brightness.values) {
    final tokens = AppTokens.indigo(b);
    test('colours stay readable (${b.name})', () {
      // Yellow, white, light grey and black: some are invisible on one mode.
      for (final code in ['8', '0', '15', '1', '11', '9']) {
        final spans = flat(
          mircSpans(
            '\x03${code}text',
            tokens: tokens,
            background: tokens.surface,
            textColor: tokens.textPrimary,
          ),
        );
        expect(
          tokenContrast(spans.single.style!.color!, tokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'colour $code',
        );
      }
    });

    test('a run with its own background reads on it (${b.name})', () {
      final span = flat(
        mircSpans(
          '\x030,0white on white',
          tokens: tokens,
          background: tokens.surface,
          textColor: tokens.textPrimary,
        ),
      ).single;
      expect(
        tokenContrast(span.style!.color!, span.style!.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
      final bgOnly = flat(
        mircSpans(
          '\x0399,1on black',
          tokens: tokens,
          background: tokens.surface,
          textColor: tokens.textPrimary,
        ),
      ).single;
      expect(
        tokenContrast(bgOnly.style!.color!, const Color(0xFF000000)),
        greaterThanOrEqualTo(4.5),
      );
    });
  }

  test('styles become TextStyles', () {
    final tokens = AppTokens.indigo(Brightness.light);
    final spans = flat(
      mircSpans(
        '\x02b\x02\x1Di\x1D\x1Fu\x1F\x1Es\x1E\x11m',
        tokens: tokens,
        background: tokens.surface,
        textColor: tokens.textPrimary,
      ),
    );
    expect(spans[0].style!.fontWeight, FontWeight.w700);
    expect(spans[1].style!.fontStyle, FontStyle.italic);
    expect(spans[2].style!.decoration, TextDecoration.underline);
    expect(spans[3].style!.decoration, TextDecoration.lineThrough);
    expect(spans[4].style!.fontFamilyFallback, contains('Menlo'));
  });

  test('turned off: codes removed, plain text', () {
    final tokens = AppTokens.indigo(Brightness.light);
    final spans = flat(
      mircSpans(
        '\x02\x034hi\x0F there',
        tokens: tokens,
        background: tokens.surface,
        textColor: tokens.textPrimary,
        colours: false,
      ),
    );
    expect(spans.single.text, 'hi there');
    expect(spans.single.style, isNull);
  });

  test('your nick is highlighted inside formatted runs', () {
    final tokens = AppTokens.indigo(Brightness.light);
    const hl = TextStyle(fontWeight: FontWeight.w600);
    final spans = flat(
      mircSpans(
        '\x02hey me!\x02 and someone',
        tokens: tokens,
        background: tokens.surface,
        textColor: tokens.textPrimary,
        highlight: 'me',
        highlightStyle: hl,
      ),
    );
    expect(spans.where((s) => s.style == hl).map((s) => s.text), ['me']);
  });
}
