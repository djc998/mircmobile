import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/conversation_row.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
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
  testWidgets('a row: avatar, name, chip, time, preview and badge', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        ConversationRow(
          name: '#flutter',
          isRoom: true,
          network: 'Libera',
          time: '10:15',
          preview: 'alice: hi',
          unread: 3,
          mention: true,
          onTap: () => taps++,
        ),
      ),
    );
    expect(find.byType(RoomAvatar), findsOneWidget);
    expect(find.text('Libera'), findsOneWidget);
    expect(find.text('10:15'), findsOneWidget);
    expect(find.text('alice: hi'), findsOneWidget);
    expect(find.text('@ 3'), findsOneWidget);
    // The time sits at the right edge and is coral for a mention.
    final tokens = AppTokens.of(tester.element(find.text('10:15')));
    final time = tester.widget<Text>(find.text('10:15'));
    expect(time.style!.color, tokens.readable(tokens.mention));
    expect(
      tester.getTopRight(find.text('10:15')).dx,
      greaterThan(tester.getTopRight(find.byType(ConversationRow)).dx - 30),
    );
    await tester.tap(find.byType(ConversationRow));
    expect(taps, 1);

    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel(
        'Room #flutter, on Libera, 3 unread messages, mentions you, '
        'last active 10:15, alice: hi',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('Compact shows icons instead of avatars', (tester) async {
    await tester.pumpWidget(
      host(
        ConversationRow(
          name: 'bob',
          isRoom: false,
          avatars: false,
          onTap: () {},
        ),
      ),
    );
    expect(find.byType(NickAvatar), findsNothing);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('long names give way; everything fits at large text', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        ConversationRow(
          name: '#a-very-long-room-name-that-will-not-fit',
          isRoom: true,
          network: 'Libera',
          time: 'Yesterday',
          preview: 'x' * 200,
          unread: 120,
          onTap: () {},
        ),
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    // At least a 48-pt target.
    expect(
      tester.getSize(find.byType(ConversationRow)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('dense sidebar rows are 44 pt or taller', (tester) async {
    await tester.pumpWidget(
      host(
        ConversationRow(
          name: '#python',
          isRoom: true,
          unread: 2,
          dense: true,
          onTap: () {},
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(ConversationRow)).height,
      greaterThanOrEqualTo(44),
    );
    expect(find.byType(UnreadBadge), findsOneWidget);
  });

  testWidgets('a favorite not joined yet is dimmed and says so', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        FavoriteTile(name: '#retro', isRoom: true, joined: false, onTap: () {}),
      ),
    );
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byType(RoomAvatar),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0.5,
    );
    final handle = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Room #retro, favorite, not joined, tap to join'),
      findsOneWidget,
    );
    handle.dispose();
  });
}
