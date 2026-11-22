/// A room in Discover: avatar, name, people, category, "Busy now", topic,
/// and Join (or Open when you're already in it).
library;

import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/conversation_row.dart';
import 'package:material_ui/material_ui.dart';

/// `142`, `4,812`, `21,050`.
String groupedCount(int n) {
  final s = '$n';
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class RoomCard extends StatelessWidget {
  const RoomCard({
    required this.name,
    required this.people,
    required this.topic,
    required this.onJoin,
    this.category,
    this.busy = false,
    this.network,
    this.joined = false,
    this.favorite = false,
    this.onFavorite,
    this.onTap,
    super.key,
  });

  final String name;
  final int people;

  /// Already stripped of mIRC colour and style codes.
  final String topic;

  /// `Tech`, `Gaming`… or null when unknown.
  final String? category;
  final bool busy;

  /// Short network name for the chip, with more than one network.
  final String? network;

  /// You're in it: the button reads Open.
  final bool joined;
  final bool favorite;

  /// Join or open; null when the network isn't connected.
  final VoidCallback? onJoin;
  final VoidCallback? onFavorite;

  /// Opens the preview sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final muted = TypeScale.meta.copyWith(color: tokens.textMuted);
    final peopleLabel =
        '${groupedCount(people)} '
        '${people == 1 ? 'person' : 'people'}';

    final button = joined
        ? OutlinedButton(
            onPressed: onJoin,
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.readable(
                tokens.accent,
                tokens.surfaceRaised,
              ),
              side: BorderSide(color: tokens.accent),
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
            ),
            child: Text('Open', semanticsLabel: 'Open $name'),
          )
        : FilledButton(
            onPressed: onJoin,
            style: FilledButton.styleFrom(
              backgroundColor: tokens.accent,
              foregroundColor: tokens.onAccent,
              shape: const StadiumBorder(),
              visualDensity: VisualDensity.compact,
            ),
            child: Text('Join', semanticsLabel: 'Join $name'),
          );

    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.line),
        borderRadius: BorderRadius.circular(tokens.radius(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  RoomAvatar(name: name, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              flex: 3,
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 22 / 16,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary,
                                ),
                              ),
                            ),
                            if (network != null) ...[
                              const SizedBox(width: 6),
                              Flexible(child: NetworkChip(network!)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.people_outline,
                                size: 14,
                                color: tokens.textMuted,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(text: peopleLabel),
                                    if (category != null)
                                      TextSpan(text: ' · $category'),
                                    if (busy) ...[
                                      const TextSpan(text: ' · '),
                                      TextSpan(
                                        text: 'Busy now',
                                        style: TextStyle(
                                          color: tokens.readable(
                                            tokens.success,
                                            tokens.surfaceRaised,
                                          ),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                style: muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (onFavorite != null)
                    IconButton(
                      tooltip: favorite
                          ? 'Remove $name from favorites'
                          : 'Add $name to favorites',
                      icon: Icon(
                        favorite ? Icons.star : Icons.star_border,
                        color: favorite ? tokens.accent : tokens.textMuted,
                      ),
                      onPressed: onFavorite,
                    ),
                  button,
                ],
              ),
              if (topic.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  topic,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 20 / 14,
                  ).copyWith(color: tokens.textMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
