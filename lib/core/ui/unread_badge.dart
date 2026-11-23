/// The unread count on a room or chat.
library;

import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A pill with the number of unread messages: accent, or coral `@ n` when
/// one of them mentions you. Nothing is drawn when there's nothing unread.
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({
    required this.count,
    this.mention = false,
    this.muted = false,
    super.key,
  });

  final int count;

  /// Whether an unread message mentions you.
  final bool mention;

  /// A muted chat: grey unless it mentions you.
  final bool muted;

  /// `7`, `99+`, or `@ 3` for mentions.
  static String text(int count, {bool mention = false}) {
    final n = count > 99 ? '99+' : '$count';
    return mention ? '@ $n' : n;
  }

  /// What a screen reader says: `3 unread messages, mentions you`.
  static String semanticLabel(int count, {bool mention = false}) =>
      '$count unread ${count == 1 ? 'message' : 'messages'}'
      '${mention ? ', mentions you' : ''}';

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final tokens = AppTokens.of(context);
    final grey = muted && !mention;
    final bg = mention
        ? tokens.mention
        : grey
        ? tokens.surfaceOverlay
        : tokens.accent;
    final fg = mention
        ? tokens.onMention
        : grey
        ? tokens.readable(tokens.textMuted, tokens.surfaceOverlay)
        : tokens.onAccent;
    return Semantics(
      label:
          '${semanticLabel(count, mention: mention)}${muted ? ', muted' : ''}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        // No alignment: the pill hugs its text instead of filling the row.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(tokens.radius(10)),
        ),
        child: Text(
          text(count, mention: mention),
          textAlign: TextAlign.center,
          style: TypeScale.meta.copyWith(
            color: fg,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
