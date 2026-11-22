/// Lines across the chat: the day, where new messages start, and events.
library;

import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// A centred label between two hairlines.
class _LabelledRule extends StatelessWidget {
  const _LabelledRule({required this.label, required this.color, this.rule});

  final String label;
  final Color color;

  /// Hairline colour; [color] when null.
  final Color? rule;

  @override
  Widget build(BuildContext context) {
    final line = Expanded(child: Container(height: 1, color: rule ?? color));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            line,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                label,
                style: TypeScale.meta.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            line,
          ],
        ),
      ),
    );
  }
}

/// "Today", "Yesterday" or the date, before each day's first line.
class DayDivider extends StatelessWidget {
  const DayDivider({required this.day, this.now, super.key});

  /// Local midnight of the day.
  final DateTime day;

  /// For tests; the current time otherwise.
  final DateTime? now;

  /// `Today`, `Yesterday`, else the medium date (`Mon, Nov 18` style).
  static String label(BuildContext context, DateTime day, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d == today) return 'Today';
    if (d == DateTime(today.year, today.month, today.day - 1)) {
      return 'Yesterday';
    }
    final loc = MaterialLocalizations.of(context);
    return d.year == today.year
        ? loc.formatMediumDate(d)
        : loc.formatFullDate(d);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _LabelledRule(
      label: label(context, day, now: now),
      color: tokens.textMuted,
      rule: tokens.line,
    );
  }
}

/// The coral "New messages" line before the first unread message.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return _LabelledRule(
      label: 'New messages',
      color: tokens.readable(tokens.mention),
      rule: tokens.mentionBar,
    );
  }
}

/// A centred muted line for joins, leaves and other events. With
/// [details], tapping it shows each event on its own line.
class SystemEventLine extends StatefulWidget {
  const SystemEventLine({
    required this.text,
    this.details = const [],
    this.error = false,
    super.key,
  });

  final String text;

  /// The events [text] sums up; shown when expanded.
  final List<String> details;

  /// Drawn in the error colour with a warning sign.
  final bool error;

  @override
  State<SystemEventLine> createState() => _SystemEventLineState();
}

class _SystemEventLineState extends State<SystemEventLine> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final color = widget.error
        ? Theme.of(context).colorScheme.error
        : tokens.textMuted;
    final style = TypeScale.meta.copyWith(color: color);
    final canExpand = widget.details.length > 1;
    final text = Text(
      widget.error ? '⚠ ${widget.text}' : widget.text,
      textAlign: TextAlign.center,
      style: style,
    );
    if (!canExpand) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Center(child: text),
      );
    }
    return Semantics(
      button: true,
      expanded: _expanded,
      onTapHint: _expanded ? 'hide details' : 'show each one',
      child: InkWell(
        borderRadius: BorderRadius.circular(tokens.radius(Radii.chip)),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(child: text),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: color,
                  ),
                ],
              ),
              if (_expanded)
                for (final d in widget.details)
                  Text(d, textAlign: TextAlign.center, style: style),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating "3 new" button that scrolls back to the latest message.
/// Coral `@ New mention` when one of them mentions you.
class JumpPill extends StatelessWidget {
  const JumpPill({
    required this.count,
    required this.onTap,
    this.mention = false,
    super.key,
  });

  final int count;
  final bool mention;
  final VoidCallback onTap;

  /// `3 new`, `99+ new`, or `@ 2 new` with a mention.
  static String text(int count, {bool mention = false}) {
    final n = count > 99 ? '99+' : '$count';
    return mention ? '@ $n new' : '$n new';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final bg = mention ? tokens.mention : tokens.accent;
    final fg = mention ? tokens.onMention : tokens.onAccent;
    return Semantics(
      button: true,
      label:
          '$count new ${count == 1 ? 'message' : 'messages'}'
          '${mention ? ', mentions you' : ''}. Jump to latest',
      excludeSemantics: true,
      child: Material(
        color: bg,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(tokens.radius(18)),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.radius(18)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_downward, size: 16, color: fg),
                  const SizedBox(width: 6),
                  Text(
                    text(count, mention: mention),
                    style: TypeScale.meta.copyWith(
                      color: fg,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
