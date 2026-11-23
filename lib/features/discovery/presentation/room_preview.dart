/// The sheet a room card opens: everything known about the room before you
/// join it.
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/room_card.dart';
import 'package:irc_client/features/discovery/domain/room_category.dart';
import 'package:material_ui/material_ui.dart';

/// Shows [room]'s name, network, people, category and full topic, with
/// Join (or Open) and a favorite button.
Future<void> showRoomPreview(
  BuildContext context, {
  required ChannelListEntry room,
  required String networkLabel,
  required bool joined,
  required bool favorite,
  required VoidCallback? onJoin,
  required VoidCallback onFavorite,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (sheet) {
    final tokens = AppTokens.of(sheet);
    final category = categoryOf(room);
    final topic = stripFormatting(room.topic).trim();
    final muted = TypeScale.body.copyWith(color: tokens.textMuted);
    // The details scroll; the buttons stay at the bottom.
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      RoomAvatar(name: room.name, size: 56),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              style: TypeScale.title.copyWith(
                                color: tokens.textPrimary,
                              ),
                            ),
                            Text(networkLabel, style: muted),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.people_outline, size: 18),
                        label: Text(
                          '${groupedCount(room.userCount)} '
                          '${room.userCount == 1 ? 'person' : 'people'} '
                          'here now',
                        ),
                      ),
                      if (category != RoomCategory.other)
                        Chip(label: Text(category.label)),
                      if (isBusyRoom(room))
                        Chip(
                          avatar: Icon(
                            Icons.local_fire_department_outlined,
                            size: 18,
                            color: tokens.readable(tokens.success),
                          ),
                          label: const Text('Busy now'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Topic',
                    style: TypeScale.meta.copyWith(
                      color: tokens.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    topic.isEmpty ? 'No topic set.' : topic,
                    style: TypeScale.body.copyWith(color: tokens.textPrimary),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Side by side when they fit, stacked otherwise (large
                // text, narrow phones).
                OverflowBar(
                  spacing: 12,
                  overflowSpacing: 8,
                  overflowAlignment: OverflowBarAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: Icon(joined ? Icons.forum_outlined : Icons.login),
                      label: Text(joined ? 'Open room' : 'Join room'),
                      onPressed: onJoin == null
                          ? null
                          : () {
                              Navigator.pop(sheet);
                              onJoin();
                            },
                    ),
                    OutlinedButton.icon(
                      icon: Icon(favorite ? Icons.star : Icons.star_border),
                      label: Text(favorite ? 'Favorite' : 'Add to favorites'),
                      onPressed: () {
                        Navigator.pop(sheet);
                        onFavorite();
                      },
                    ),
                  ],
                ),
                if (onJoin == null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Connect to $networkLabel to join.',
                    style: TypeScale.meta.copyWith(color: tokens.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  },
);
