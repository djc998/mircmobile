import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/empty_state.dart';
import 'package:irc_client/core/ui/room_card.dart';
import 'package:material_ui/material_ui.dart';

Widget host(Widget child, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.build(ThemePreset.indigo, Brightness.light),
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(
      body: Center(child: SizedBox(width: 380, child: child)),
    ),
  ),
);

void main() {
  test('groupedCount', () {
    expect(groupedCount(7), '7');
    expect(groupedCount(4812), '4,812');
    expect(groupedCount(1234567), '1,234,567');
  });

  testWidgets('Join, or Open when you are in the room', (tester) async {
    var joins = 0;
    var taps = 0;
    await tester.pumpWidget(
      host(
        Column(
          children: [
            RoomCard(
              name: '#help',
              people: 1520,
              topic: 'Ask anything',
              category: 'Help',
              busy: true,
              onJoin: () => joins++,
              onTap: () => taps++,
            ),
            RoomCard(
              name: '#linux',
              people: 891,
              topic: '',
              joined: true,
              onJoin: () {},
            ),
          ],
        ),
      ),
    );
    expect(
      find.textContaining('1,520 people · Help · Busy now', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Ask anything'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await tester.tap(find.text('#help'));
    expect(joins, 1);
    expect(taps, 1);

    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Join #help'), findsOneWidget);
    expect(find.bySemanticsLabel('Open #linux'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('"Busy now" is readable in every theme', (tester) async {
    for (final preset in ThemePreset.values) {
      for (final b in Brightness.values) {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(preset, b),
            home: Scaffold(
              body: RoomCard(
                name: '#a',
                people: 200,
                topic: '',
                busy: true,
                onJoin: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final tokens = AppTokens.of(tester.element(find.byType(RoomCard)));
        final rich = tester.widget<RichText>(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().contains('Busy now'),
          ),
        );
        Color? busy;
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'Busy now') {
            busy = span.style!.color;
          }
          return true;
        });
        expect(
          tokenContrast(busy!, tokens.surfaceRaised),
          greaterThanOrEqualTo(4.5),
          reason: '${preset.name} ${b.name}',
        );
      }
    }
  });

  testWidgets('no network: the button is off; fits at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        const RoomCard(
          name: '#a-room-with-a-very-long-name-indeed',
          people: 12345,
          topic: 'A topic that goes on and on and on and on and on and on',
          category: 'Social',
          busy: true,
          network: 'Libera',
          onJoin: null,
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets('EmptyState shows its button; SkeletonList is labelled', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EmptyState(
              icon: Icons.explore,
              title: 'Find your first room',
              message: 'Discover lists every room.',
              action: 'Discover rooms',
              onAction: () => tapped++,
            ),
            const SkeletonList(count: 2, label: 'Fetching rooms'),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Discover rooms'));
    expect(tapped, 1);
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Fetching rooms'), findsOneWidget);
    handle.dispose();
  });
}
