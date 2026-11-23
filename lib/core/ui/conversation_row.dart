/// Rows and tiles for the conversation lists: Rooms home, the sidebar and
/// the quick switcher.
library;

import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:material_ui/material_ui.dart';

/// The small outlined network name on a row, e.g. `Libera`.
class NetworkChip extends StatelessWidget {
  const NetworkChip(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.line),
        borderRadius: BorderRadius.circular(tokens.radius(4)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          height: 14 / 10,
          fontWeight: FontWeight.w600,
          color: tokens.textMuted,
        ),
      ),
    );
  }
}

/// A room or private chat in a list: avatar, name, network chip, time,
/// a one-line preview and the unread badge.
///
/// [dense] is the sidebar's version: smaller avatar, no time or preview.
class ConversationRow extends StatelessWidget {
  const ConversationRow({
    required this.name,
    required this.isRoom,
    required this.onTap,
    this.network,
    this.time,
    this.preview = '',
    this.unread = 0,
    this.mention = false,
    this.selected = false,
    this.favorite = false,
    this.muted = false,
    this.dense = false,
    this.avatars = true,
    super.key,
  });

  final String name;
  final bool isRoom;

  /// Compact density: a `#` or person icon instead of an avatar.
  final bool avatars;

  /// Short network name for the chip; none when null.
  final String? network;

  /// When it was last active, already formatted (`10:15`, `Yesterday`).
  final String? time;
  final String preview;
  final int unread;
  final bool mention;
  final bool selected;

  /// Shows a small star (sidebar rows in other sections don't need it).
  final bool favorite;

  /// Muted: a bell-off icon and a grey badge.
  final bool muted;
  final bool dense;
  final VoidCallback onTap;

  /// What a screen reader says for the row.
  String get semanticLabel => [
    if (isRoom) 'Room $name' else name,
    if (network != null) 'on $network',
    if (favorite) 'favorite',
    if (muted) 'muted',
    if (unread > 0) '$unread unread ${unread == 1 ? 'message' : 'messages'}',
    if (unread > 0 && mention) 'mentions you',
    if (time != null) 'last active $time',
    if (preview.isNotEmpty) preview,
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final size = dense ? 32.0 : 48.0;
    final avatar = !avatars
        ? SizedBox(
            width: dense ? 24 : 32,
            child: Icon(
              isRoom ? Icons.tag : Icons.person_outline,
              color: tokens.textMuted,
            ),
          )
        : isRoom
        ? RoomAvatar(name: name, size: size)
        : NickAvatar(nick: name, size: size);
    final bold = unread > 0;
    final nameText = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: dense ? 14 : 16,
        height: dense ? 20 / 14 : 22 / 16,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
        color: selected && dense ? tokens.onAccentSoft : tokens.textPrimary,
      ),
    );
    final timeColor = mention
        ? tokens.readable(tokens.mention)
        : unread > 0
        ? tokens.readable(tokens.accent)
        : tokens.textMuted;

    // Name, star and network chip; the name gives way first.
    final titleLine = Row(
      children: [
        Flexible(flex: 3, child: nameText),
        if (favorite) ...[
          const SizedBox(width: 4),
          Icon(Icons.star, size: 14, color: tokens.textMuted),
        ],
        if (muted) ...[
          const SizedBox(width: 4),
          Icon(
            Icons.notifications_off_outlined,
            size: 14,
            color: tokens.textMuted,
          ),
        ],
        if (network != null) ...[
          const SizedBox(width: 6),
          Flexible(child: NetworkChip(network!)),
        ],
      ],
    );

    final Widget body;
    if (dense) {
      body = Row(
        children: [
          avatar,
          const SizedBox(width: 10),
          Expanded(child: titleLine),
          const SizedBox(width: 6),
          UnreadBadge(count: unread, mention: mention, muted: muted),
        ],
      );
    } else {
      body = Row(
        children: [
          avatar,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: titleLine),
                    if (time != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        time!,
                        style: TypeScale.meta.copyWith(
                          color: timeColor,
                          fontWeight: unread > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 20 / 14,
                        ).copyWith(color: tokens.textMuted),
                      ),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 8),
                      UnreadBadge(
                        count: unread,
                        mention: mention,
                        muted: muted,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: selected
            ? Color.alphaBlend(tokens.accentSoft, tokens.surfaceRaised)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(tokens.radius(dense ? 8 : 0)),
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radius(dense ? 8 : 0)),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: dense ? 44 : 68),
            child: Padding(
              padding: dense
                  ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                  : const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// A big square favorite on Rooms home: 60-pt avatar with its unread badge
/// on the corner and the name under it.
class FavoriteTile extends StatelessWidget {
  const FavoriteTile({
    required this.name,
    required this.isRoom,
    required this.onTap,
    this.unread = 0,
    this.mention = false,
    this.joined = true,
    super.key,
  });

  final String name;
  final bool isRoom;
  final int unread;
  final bool mention;

  /// Not joined yet: dimmed; tapping joins it.
  final bool joined;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      button: true,
      label: [
        if (isRoom) 'Room $name' else name,
        'favorite',
        if (!joined) 'not joined, tap to join',
        if (unread > 0) '$unread unread${mention ? ', mentions you' : ''}',
      ].join(', '),
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius(16)),
        onTap: onTap,
        child: SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Opacity(
                  opacity: joined ? 1 : 0.5,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (isRoom)
                        RoomAvatar(name: name, size: 60)
                      else
                        NickAvatar(nick: name, size: 60),
                      if (unread > 0)
                        Positioned(
                          top: -5,
                          right: -5,
                          child: UnreadBadge(count: unread, mention: mention),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.meta.copyWith(
                    color: joined ? tokens.textPrimary : tokens.textMuted,
                    fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
