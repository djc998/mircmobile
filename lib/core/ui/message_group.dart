/// Messages in Comfortable style: grouped under one avatar in rooms, as
/// bubbles in private chats.
library;

import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:material_ui/material_ui.dart';

/// Messages in a row from one person: avatar, coloured name, OP badge and
/// time once, then each message.
///
/// Mentions of you get a coral bar and tint; your own messages an accent
/// bar.
class MessageGroup extends StatelessWidget {
  const MessageGroup({
    required this.nick,
    required this.time,
    required this.children,
    this.role = NickRole.member,
    this.own = false,
    this.mentioned = false,
    this.onNickTap,
    super.key,
  });

  final String nick;

  /// When the first message was sent, already formatted (`10:42`).
  final String time;

  /// One widget per message.
  final List<Widget> children;
  final NickRole role;
  final bool own;
  final bool mentioned;

  /// Opens the person's actions (avatar or name).
  final VoidCallback? onNickTap;

  /// Width of the coloured bar on mentions and your own messages.
  static const double barWidth = 3;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final tint = mentioned ? tokens.mentionSoft : null;
    final bar = mentioned
        ? tokens.mentionBar
        : own
        ? tokens.accent
        : null;
    final nickColor = tokens.readable(
      ChatColors.of(context).nickColor(nick),
      tint,
    );
    Widget tappable(Widget child, {required String label}) => onNickTap == null
        ? child
        : Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onNickTap,
              child: child,
            ),
          );

    final header = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        tappable(
          Text(
            nick,
            style: const TextStyle(
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
            ).copyWith(color: nickColor),
          ),
          label: '$nick, actions',
        ),
        if (role == NickRole.op) const OpBadge(),
        Text(time, style: TypeScale.meta.copyWith(color: tokens.textMuted)),
      ],
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
      child: Container(
        decoration: BoxDecoration(
          color: tint,
          border: bar == null
              ? null
              : Border(
                  left: BorderSide(color: bar, width: barWidth),
                ),
        ),
        padding: EdgeInsets.fromLTRB(bar == null ? 10 : 10 - barWidth, 6, 4, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: tappable(
                NickAvatar(nick: nick, role: role),
                label: '$nick, actions',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, ...children],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The small gold "OP" tag next to an operator's name.
class OpBadge extends StatelessWidget {
  const OpBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Semantics(
      label: 'operator',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          border: Border.all(color: tokens.op),
          borderRadius: BorderRadius.circular(tokens.radius(4)),
        ),
        child: Text(
          'OP',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: 10,
            height: 14 / 10,
            fontWeight: FontWeight.w700,
            color: tokens.opText,
          ),
        ),
      ),
    );
  }
}

/// One message in a private chat: yours on the right in the accent colour,
/// theirs on the left. The corner nearest the sender is tucked in, and
/// also the top one when it follows another bubble from the same person.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    required this.child,
    this.own = false,
    this.continued = false,
    super.key,
  });

  final Widget child;
  final bool own;

  /// Follows a bubble from the same person.
  final bool continued;

  /// Bubbles take at most this share of the width.
  static const double maxWidthFactor = 0.76;

  /// The bubble's corners; see the class comment.
  static BorderRadius shape(
    AppTokens tokens, {
    required bool own,
    required bool continued,
  }) {
    final round = Radius.circular(tokens.radius(Radii.bubble));
    final tail = Radius.circular(tokens.radius(Radii.bubbleTail));
    return own
        ? BorderRadius.only(
            topLeft: round,
            topRight: continued ? tail : round,
            bottomLeft: round,
            bottomRight: tail,
          )
        : BorderRadius.only(
            topLeft: continued ? tail : round,
            topRight: round,
            bottomLeft: tail,
            bottomRight: round,
          );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bg = own ? tokens.accent : tokens.surfaceOverlay;
    final fg = own ? tokens.onAccent : tokens.textPrimary;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: own
            ? AlignmentDirectional.centerEnd
            : AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * maxWidthFactor,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: shape(tokens, own: own, continued: continued),
            ),
            child: DefaultTextStyle.merge(
              style: TypeScale.body.copyWith(color: fg),
              child: IconTheme.merge(
                data: IconThemeData(color: fg),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
