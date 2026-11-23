import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/chat_dividers.dart';
import 'package:irc_client/core/ui/composer.dart';
import 'package:irc_client/core/ui/message_group.dart';
import 'package:material_ui/material_ui.dart';

Widget host(
  Widget child, {
  ThemePreset preset = ThemePreset.indigo,
  Brightness brightness = Brightness.light,
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.build(preset, brightness),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(child: SizedBox(width: 360, child: child)),
    ),
  ),
);

void main() {
  testWidgets('DayDivider: Today, Yesterday, then the date', (tester) async {
    final now = DateTime(2026, 11, 22, 15);
    late BuildContext ctx;
    await tester.pumpWidget(
      host(
        Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(DayDivider.label(ctx, DateTime(2026, 11, 22), now: now), 'Today');
    expect(
      DayDivider.label(ctx, DateTime(2026, 11, 21), now: now),
      'Yesterday',
    );
    expect(
      DayDivider.label(ctx, DateTime(2026, 11, 18), now: now),
      'Wed, Nov 18',
    );
    // Across New Year.
    expect(
      DayDivider.label(
        ctx,
        DateTime(2026, 12, 31),
        now: DateTime(2027, 1, 1, 9),
      ),
      'Yesterday',
    );
  });

  testWidgets('UnreadDivider text is readable in every theme', (tester) async {
    for (final preset in ThemePreset.values) {
      for (final b in Brightness.values) {
        await tester.pumpWidget(
          host(const UnreadDivider(), preset: preset, brightness: b),
        );
        await tester.pumpAndSettle();
        final tokens = AppTokens.of(tester.element(find.text('New messages')));
        final color = tester
            .widget<Text>(find.text('New messages'))
            .style!
            .color!;
        expect(
          tokenContrast(color, tokens.surface),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name} ${b.name}',
        );
      }
    }
  });

  testWidgets('SystemEventLine expands to show each event', (tester) async {
    await tester.pumpWidget(
      host(
        const SystemEventLine(
          text: 'mara and kai joined',
          details: ['mara joined', 'kai joined'],
        ),
      ),
    );
    expect(find.text('kai joined'), findsNothing);
    await tester.tap(find.text('mara and kai joined'));
    await tester.pump();
    expect(find.text('kai joined'), findsOneWidget);
    // A single event isn't a button.
    await tester.pumpWidget(host(const SystemEventLine(text: 'sam left')));
    expect(find.byType(InkWell), findsNothing);
  });

  group('JumpPill', () {
    test('text', () {
      expect(JumpPill.text(3), '3 new');
      expect(JumpPill.text(250), '99+ new');
      expect(JumpPill.text(2, mention: true), '@ 2 new');
    });

    testWidgets('accent, or coral with a mention; a 48-pt target', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          Row(
            children: [
              JumpPill(count: 3, onTap: () => taps++),
              JumpPill(count: 1, mention: true, onTap: () {}),
            ],
          ),
        ),
      );
      final tokens = AppTokens.of(tester.element(find.text('3 new')));
      Color colorOf(String text) => tester
          .widget<Material>(
            find
                .ancestor(of: find.text(text), matching: find.byType(Material))
                .first,
          )
          .color!;
      expect(colorOf('3 new'), tokens.accent);
      expect(colorOf('@ 1 new'), tokens.mention);
      expect(
        tester.getSize(find.byType(JumpPill).first).width,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(find.text('3 new'));
      expect(taps, 1);
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel('3 new messages. Jump to latest'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('MessageGroup: coral bar and tint for mentions, accent for own', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Column(
          children: [
            MessageGroup(
              nick: 'alice',
              time: '10:11',
              mentioned: true,
              children: [Text('hi me')],
            ),
            MessageGroup(
              nick: 'me',
              time: '10:12',
              own: true,
              children: [Text('hi')],
            ),
            MessageGroup(
              nick: 'devon',
              time: '10:13',
              role: NickRole.op,
              children: [Text('morning')],
            ),
          ],
        ),
      ),
    );
    final tokens = AppTokens.of(tester.element(find.text('hi me')));
    BoxDecoration boxOf(String text) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(text),
                        matching: find.byType(Container),
                      )
                      .last,
                )
                .decoration!
            as BoxDecoration;
    final mention = boxOf('hi me');
    expect(mention.color, tokens.mentionSoft);
    expect((mention.border! as Border).left.color, tokens.mentionBar);
    final own = boxOf('hi');
    expect(own.color, isNull);
    expect((own.border! as Border).left.color, tokens.accent);
    expect(boxOf('morning').border, isNull);
    expect(find.byType(OpBadge), findsOneWidget);
    // The nick on a tinted row is still readable.
    final nick = tester.widget<Text>(find.text('alice'));
    expect(
      tokenContrast(
        nick.style!.color!,
        Color.alphaBlend(tokens.mentionSoft, tokens.surface),
      ),
      greaterThanOrEqualTo(4.5),
    );
  });

  testWidgets('OpBadge text is readable in every theme', (tester) async {
    for (final preset in ThemePreset.values) {
      for (final b in Brightness.values) {
        await tester.pumpWidget(
          host(const OpBadge(), preset: preset, brightness: b),
        );
        await tester.pumpAndSettle();
        final tokens = AppTokens.of(tester.element(find.text('OP')));
        expect(
          tokenContrast(
            tester.widget<Text>(find.text('OP')).style!.color!,
            tokens.surface,
          ),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name} ${b.name}',
        );
      }
    }
  });

  group('MessageBubble', () {
    test('the corner by the sender is tucked; also the top when continued', () {
      final t = AppTokens.indigo(Brightness.light);
      const round = Radius.circular(Radii.bubble);
      const tail = Radius.circular(Radii.bubbleTail);
      expect(
        MessageBubble.shape(t, own: false, continued: false),
        const BorderRadius.only(
          topLeft: round,
          topRight: round,
          bottomLeft: tail,
          bottomRight: round,
        ),
      );
      expect(
        MessageBubble.shape(t, own: true, continued: true),
        const BorderRadius.only(
          topLeft: round,
          topRight: tail,
          bottomLeft: round,
          bottomRight: tail,
        ),
      );
    });

    testWidgets('accent with readable text for yours; at most 76% wide', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Column(
            children: [
              const MessageBubble(own: true, child: Text('mine')),
              MessageBubble(child: Text('theirs ' * 30)),
            ],
          ),
        ),
      );
      final tokens = AppTokens.of(tester.element(find.text('mine')));
      final mine = tester.widget<Container>(
        find.ancestor(of: find.text('mine'), matching: find.byType(Container)),
      );
      expect((mine.decoration! as BoxDecoration).color, tokens.accent);
      final style = DefaultTextStyle.of(tester.element(find.text('mine')));
      expect(style.style.color, tokens.onAccent);
      final long = find
          .ancestor(
            of: find.textContaining('theirs'),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getSize(long).width, lessThanOrEqualTo(360 * 0.76));
    });
  });

  group('Composer', () {
    testWidgets('sends, clears, and Enter sends too', (tester) async {
      final sent = <String>[];
      await tester.pumpWidget(host(Composer(onSubmit: sent.add)));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();
      expect(sent, ['hello']);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), 'again');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      expect(sent, ['hello', 'again']);
      // Blank lines aren't sent.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.byTooltip('Send'));
      expect(sent, hasLength(2));
    });

    testWidgets(
      'computers: Enter sends, Shift+Enter adds a line',
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
      (tester) async {
        final sent = <String>[];
        await tester.pumpWidget(host(Composer(onSubmit: sent.add)));
        await tester.enterText(find.byType(TextField), 'one');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(sent, isEmpty);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          'one\n',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(sent, ['one\n']);
      },
    );

    testWidgets('the + menu offers a picture only when allowed', (
      tester,
    ) async {
      var attached = 0;
      await tester.pumpWidget(
        host(Composer(onSubmit: (_) {}, onAttach: () => attached++)),
      );
      await tester.tap(find.byTooltip('Add a picture or command'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send a picture'));
      await tester.pumpAndSettle();
      expect(attached, 1);

      await tester.pumpWidget(host(Composer(onSubmit: (_) {})));
      await tester.tap(find.byTooltip('Add a command'));
      await tester.pumpAndSettle();
      expect(find.text('Send a picture'), findsNothing);
      await tester.tap(find.text('Change nickname (/nick)'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '/nick ',
      );
    });

    testWidgets('buttons are 48-pt targets and fit at the largest text', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          Composer(onSubmit: (_) {}, replyTo: 'alice', replyText: 'hi'),
          textScale: 3,
        ),
      );
      expect(tester.takeException(), isNull);
      for (final tip in ['Send', 'Add a command', 'Cancel reply']) {
        final size = tester.getSize(
          find.ancestor(
            of: find.byTooltip(tip),
            matching: find.byType(IconButton),
          ),
        );
        expect(size.width, greaterThanOrEqualTo(48), reason: tip);
        expect(size.height, greaterThanOrEqualTo(48), reason: tip);
      }
    });
  });
}
