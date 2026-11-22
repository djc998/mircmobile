import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/chat_dividers.dart';
import 'package:irc_client/core/ui/composer.dart';
import 'package:irc_client/core/ui/conversation_row.dart';
import 'package:irc_client/core/ui/empty_state.dart';
import 'package:irc_client/core/ui/message_group.dart';
import 'package:irc_client/core/ui/room_card.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:material_ui/material_ui.dart';

/// Light and dark goldens for each Phase 1 and 2 component, in the Default
/// theme
/// and in Classic mIRC (square corners).
///
/// The images are made on macOS. Linux draws anti-aliased circle edges and
/// scaled text 2-3% differently, so these only run on macOS; the widget
/// tests in test/core/ui check colours, sizes and labels on every platform.
void main() {
  // Goldens are made and checked on macOS only (see above).
  final skip = !Platform.isMacOS;

  final components = <String, Widget>{
    'nick_avatar': const Wrap(
      spacing: 8,
      children: [
        NickAvatar(nick: 'alice'),
        NickAvatar(nick: 'dark_star', role: NickRole.op),
        NickAvatar(nick: 'MaraK', role: NickRole.voiced),
        NickAvatar(nick: 'kai', away: true),
        NickAvatar(nick: 'bob', size: 24),
      ],
    ),
    'room_avatar': const Wrap(
      spacing: 8,
      children: [
        RoomAvatar(name: '#linux'),
        RoomAvatar(name: '##chat'),
        RoomAvatar(name: '#2600', size: 60),
      ],
    ),
    'unread_badge': const Wrap(
      spacing: 8,
      children: [
        UnreadBadge(count: 3),
        UnreadBadge(count: 42),
        UnreadBadge(count: 120),
        UnreadBadge(count: 2, mention: true),
      ],
    ),
    'message_group': const SizedBox(
      width: 360,
      child: Column(
        children: [
          MessageGroup(
            nick: 'devon',
            time: '10:02',
            role: NickRole.op,
            children: [
              Text('Morning all. Anyone tried the new split?'),
              Text('The import change caught me off guard.'),
            ],
          ),
          MessageGroup(
            nick: 'alice',
            time: '10:11',
            mentioned: true,
            children: [Text('dennis, does IRCade run on the Mac too?')],
          ),
          MessageGroup(
            nick: 'dennis',
            time: '10:13',
            own: true,
            children: [Text('It does.')],
          ),
        ],
      ),
    ),
    'message_bubble': const SizedBox(
      width: 360,
      child: Column(
        children: [
          MessageBubble(child: Text('Hey! Are you building IRCade?')),
          SizedBox(height: 2),
          MessageBubble(continued: true, child: Text('Quick call later?')),
          SizedBox(height: 6),
          MessageBubble(own: true, child: Text('Guilty. Sure!')),
        ],
      ),
    ),
    'chat_dividers': SizedBox(
      width: 360,
      child: Column(
        children: [
          DayDivider(day: DateTime(2026, 11, 22), now: DateTime(2026, 11, 22)),
          const SystemEventLine(
            text: 'mara, kai and 3 others joined',
            details: ['mara joined', 'kai joined'],
          ),
          const UnreadDivider(),
          const SystemEventLine(text: 'Cannot send to channel', error: true),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              JumpPill(count: 3, onTap: () {}),
              const SizedBox(width: 8),
              JumpPill(count: 2, mention: true, onTap: () {}),
            ],
          ),
        ],
      ),
    ),
    'conversation_row': SizedBox(
      width: 380,
      child: Column(
        children: [
          ConversationRow(
            name: '#flutter',
            isRoom: true,
            network: 'Libera',
            time: '10:15',
            preview: 'alice: dennis, does IRCade run on the Mac too?',
            unread: 12,
            mention: true,
            favorite: true,
            onTap: () {},
          ),
          ConversationRow(
            name: 'alice',
            isRoom: false,
            network: 'Libera',
            time: '10:00',
            preview: 'Can we do a quick video call later?',
            unread: 2,
            onTap: () {},
          ),
          ConversationRow(
            name: '#linux',
            isRoom: true,
            time: 'Yesterday',
            preview: 'tux42: Thanks!',
            onTap: () {},
          ),
          ConversationRow(
            name: '#python',
            isRoom: true,
            network: 'Libera',
            unread: 3,
            dense: true,
            selected: true,
            onTap: () {},
          ),
        ],
      ),
    ),
    'favorite_tile': Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FavoriteTile(
          name: '#flutter',
          isRoom: true,
          unread: 12,
          mention: true,
          onTap: () {},
        ),
        FavoriteTile(name: '#linux', isRoom: true, onTap: () {}),
        FavoriteTile(name: '#retro', isRoom: true, joined: false, onTap: () {}),
      ],
    ),
    'room_card': SizedBox(
      width: 380,
      child: Column(
        children: [
          RoomCard(
            name: '#help',
            people: 1520,
            topic: 'New to IRC? Ask anything here, friendly volunteers.',
            category: 'Help',
            busy: true,
            onJoin: () {},
            onFavorite: () {},
          ),
          const SizedBox(height: 10),
          RoomCard(
            name: '#linux',
            people: 891,
            topic: 'General Linux help and chat.',
            category: 'Tech',
            network: 'Libera',
            joined: true,
            favorite: true,
            onJoin: () {},
            onFavorite: () {},
          ),
        ],
      ),
    ),
    'empty_state': SizedBox(
      width: 380,
      child: EmptyState(
        icon: Icons.explore_outlined,
        title: 'Find your first room',
        message: 'Discover lists every room on your networks.',
        action: 'Discover rooms',
        onAction: () {},
      ),
    ),
    'composer': const SizedBox(
      width: 360,
      child: Composer(
        onSubmit: print,
        hint: 'Message #flutter',
        replyTo: 'alice',
        replyText: 'does it run on the Mac?',
      ),
    ),
  };

  for (final MapEntry(key: name, value: widget) in components.entries) {
    for (final preset in [ThemePreset.indigo, ThemePreset.classic]) {
      for (final brightness in Brightness.values) {
        final file = '${name}_${preset.name}_${brightness.name}.png';
        testWidgets(file, skip: skip, (tester) async {
          final theme = AppTheme.build(preset, brightness);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: theme,
              home: Scaffold(
                body: Center(
                  child: RepaintBoundary(
                    key: const ValueKey('golden'),
                    child: Container(
                      color: theme.colorScheme.surface,
                      padding: const EdgeInsets.all(12),
                      child: widget,
                    ),
                  ),
                ),
              ),
            ),
          );
          await expectLater(
            find.byKey(const ValueKey('golden')),
            matchesGoldenFile(file),
          );
        });
      }
    }
  }
}
