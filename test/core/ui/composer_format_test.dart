import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/ui/composer.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.build(ThemePreset.indigo, Brightness.light),
  home: Scaffold(
    body: Center(child: SizedBox(width: 380, child: child)),
  ),
);

TextField field(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField));

void main() {
  testWidgets('format menu: bold the selection, then a colour', (tester) async {
    final sent = <String>[];
    await tester.pumpWidget(host(Composer(onSubmit: sent.add)));
    await tester.enterText(find.byType(TextField), 'hello world');
    field(tester).controller!.selection = const TextSelection(
      baseOffset: 6,
      extentOffset: 11,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Format text'));
    await tester.pumpAndSettle();
    expect(find.text('Format the selected text'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Bold'));
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, 'hello \x02world\x02');

    // The preview shows how it will look (the codes are invisible).
    expect(find.textContaining('Preview', findRichText: true), findsOneWidget);

    await tester.tap(find.byTooltip('Format text'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Red text'));
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, 'hello \x02\x0304world\x03\x02');

    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    expect(sent.single, 'hello \x02\x0304world\x03\x02');
    expect(find.textContaining('Preview', findRichText: true), findsNothing);
  });

  testWidgets('Plain resets what comes next', (tester) async {
    await tester.pumpWidget(host(Composer(onSubmit: (_) {})));
    await tester.enterText(find.byType(TextField), 'x');
    await tester.tap(find.byTooltip('Format text'));
    await tester.pumpAndSettle();
    expect(find.text('Format what you type next'), findsOneWidget);
    await tester.tap(find.text('Plain'));
    await tester.pumpAndSettle();
    expect(field(tester).controller!.text, 'x\x0F');
  });

  testWidgets(
    'computers: Cmd+B, Cmd+I, Cmd+U',
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    (tester) async {
      await tester.pumpWidget(host(Composer(onSubmit: (_) {})));
      await tester.enterText(find.byType(TextField), 'loud');
      field(tester).controller!.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 4,
      );
      await tester.pump();
      Future<void> cmd(LogicalKeyboardKey key) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyEvent(key);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        await tester.pump();
      }

      await cmd(LogicalKeyboardKey.keyB);
      expect(field(tester).controller!.text, '\x02loud\x02');
      await cmd(LogicalKeyboardKey.keyI);
      await cmd(LogicalKeyboardKey.keyU);
      expect(field(tester).controller!.text, '\x02\x1D\x1Floud\x1F\x1D\x02');
    },
  );

  testWidgets('the format button and swatches are 48-pt targets', (
    tester,
  ) async {
    await tester.pumpWidget(host(Composer(onSubmit: (_) {})));
    final button = tester.getSize(
      find.ancestor(
        of: find.byTooltip('Format text'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.width, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Format text'));
    await tester.pumpAndSettle();
    final handle = tester.ensureSemantics();
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('the field shows codes as small letters, one per character', (
    tester,
  ) async {
    await tester.pumpWidget(host(Composer(onSubmit: (_) {})));
    await tester.enterText(find.byType(TextField), 'a\x02b\x0304,01c\x03');
    await tester.pump();
    final controller = field(tester).controller!;
    final span = controller.buildTextSpan(
      context: tester.element(find.byType(TextField)),
      withComposing: false,
    );
    final shown = span.toPlainText();
    expect(shown, 'aBbK04,01cK');
    // Same length, so the cursor lines up with the real text.
    expect(shown.length, controller.text.length);
  });
}
