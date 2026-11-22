import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
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
    child: Scaffold(body: Center(child: child)),
  ),
);

BoxDecoration decorationOf(WidgetTester tester, Finder f) =>
    tester.widget<Container>(f).decoration! as BoxDecoration;

void main() {
  group('NickAvatar.initials', () {
    for (final (nick, expected) in [
      ('alice', 'A'),
      ('dark_star', 'DS'),
      ('DarkStar', 'DS'),
      ('[x]bob', 'XB'),
      ('mara42', 'M'),
      ('kai|away', 'KA'),
      ('a-b-c', 'AB'),
      ('^^', '^'),
      ('', '?'),
    ]) {
      test('$nick → $expected', () {
        expect(NickAvatar.initials(nick), expected);
      });
    }
  });

  group('RoomAvatar.letter', () {
    for (final (room, expected) in [
      ('#linux', 'L'),
      ('##chat', 'C'),
      ('&local', 'L'),
      ('#2600', '2'),
      ('#', '#'),
    ]) {
      test('$room → $expected', () {
        expect(RoomAvatar.letter(room), expected);
      });
    }
  });

  testWidgets('NickAvatar: initials in the nick colour on its tint', (
    tester,
  ) async {
    await tester.pumpWidget(host(const NickAvatar(nick: 'dark_star')));
    expect(find.text('DS'), findsOneWidget);
    final ctx = tester.element(find.text('DS'));
    final color = ChatColors.of(ctx).nickColor('dark_star');
    final circle = decorationOf(
      tester,
      find
          .ancestor(of: find.text('DS'), matching: find.byType(Container))
          .first,
    );
    expect(circle.shape, BoxShape.circle);
    expect(
      circle.color,
      Color.alphaBlend(
        color.withValues(alpha: 0.12),
        AppTokens.of(ctx).surface,
      ),
    );
    final text = tester.widget<Text>(find.text('DS'));
    expect(tokenContrast(text.style!.color!, circle.color!), greaterThan(4.5));
  });

  testWidgets('NickAvatar: gold ring for ops, accent for voice, dim if away', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NickAvatar(nick: 'op', role: NickRole.op),
            NickAvatar(nick: 'voice', role: NickRole.voiced),
            NickAvatar(nick: 'gone', away: true),
          ],
        ),
      ),
    );
    final tokens = AppTokens.of(tester.element(find.byType(Row)));
    Color? ringOf(String initials) {
      final box = find
          .ancestor(of: find.text(initials), matching: find.byType(Container))
          .last;
      final border = decorationOf(tester, box).border as Border?;
      return border?.top.color;
    }

    expect(ringOf('O'), tokens.op);
    expect(ringOf('V'), tokens.accent);
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(of: find.text('G'), matching: find.byType(Opacity)),
          )
          .opacity,
      0.5,
    );
  });

  testWidgets('NickAvatar: screen readers hear the nick and role', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(const NickAvatar(nick: 'alice', role: NickRole.op, away: true)),
    );
    expect(find.bySemanticsLabel('alice, operator, away'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('RoomAvatar: letter on accent-soft, square in Classic', (
    tester,
  ) async {
    await tester.pumpWidget(host(const RoomAvatar(name: '#linux')));
    final ctx = tester.element(find.text('L'));
    final tokens = AppTokens.of(ctx);
    var box = decorationOf(
      tester,
      find.ancestor(of: find.text('L'), matching: find.byType(Container)).last,
    );
    expect(box.color, Color.alphaBlend(tokens.accentSoft, tokens.surface));
    expect(box.borderRadius, BorderRadius.circular(12));
    expect(
      tester.widget<Text>(find.text('L')).style!.color,
      tokens.onAccentSoft,
    );

    await tester.pumpWidget(
      host(const RoomAvatar(name: '#linux'), preset: ThemePreset.classic),
    );
    await tester.pumpAndSettle(); // the theme change animates
    box = decorationOf(
      tester,
      find.ancestor(of: find.text('L'), matching: find.byType(Container)).last,
    );
    expect(box.borderRadius, BorderRadius.circular(2));
  });

  group('UnreadBadge', () {
    test('text', () {
      expect(UnreadBadge.text(7), '7');
      expect(UnreadBadge.text(100), '99+');
      expect(UnreadBadge.text(3, mention: true), '@ 3');
      expect(UnreadBadge.semanticLabel(1), '1 unread message');
      expect(
        UnreadBadge.semanticLabel(4, mention: true),
        '4 unread messages, mentions you',
      );
    });

    testWidgets('nothing when nothing is unread', (tester) async {
      await tester.pumpWidget(host(const UnreadBadge(count: 0)));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('accent normally, coral for mentions', (tester) async {
      await tester.pumpWidget(
        host(
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              UnreadBadge(count: 5),
              UnreadBadge(count: 2, mention: true),
            ],
          ),
        ),
      );
      final tokens = AppTokens.of(tester.element(find.text('5')));
      Color? bg(String text) => decorationOf(
        tester,
        find.ancestor(of: find.text(text), matching: find.byType(Container)),
      ).color;
      expect(bg('5'), tokens.accent);
      // The pill hugs its text rather than filling the row.
      expect(
        tester.getSize(find.byType(UnreadBadge).first).width,
        lessThan(40),
      );
      expect(bg('@ 2'), tokens.mention);
      expect(
        tester.widget<Text>(find.text('@ 2')).style!.color,
        tokens.onMention,
      );
    });
  });

  testWidgets('components fit at the largest text size', (tester) async {
    await tester.pumpWidget(
      host(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            NickAvatar(nick: 'WWWW_WWWW'),
            RoomAvatar(name: '#wide'),
            UnreadBadge(count: 1234, mention: true),
          ],
        ),
        textScale: 3,
      ),
    );
    expect(tester.takeException(), isNull);
    // Avatars keep their size; the badge grows with the text.
    expect(tester.getSize(find.byType(RoomAvatar)), const Size(36, 36));
    expect(tester.getSize(find.byType(UnreadBadge)).height, greaterThan(30));
  });
}
