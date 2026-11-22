/// What a list shows when there's nothing in it yet, and grey placeholder
/// rows while it loads.
library;

import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// An icon on a soft accent circle, a title, a line of help and an
/// optional button.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.onAction,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Button label; shown when [onAction] is set too.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(tokens.accentSoft, tokens.surface),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: tokens.onAccentSoft),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TypeScale.heading.copyWith(color: tokens.textPrimary),
              ),
              if (message != null) ...[
                const SizedBox(height: 6),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: TypeScale.body.copyWith(color: tokens.textMuted),
                ),
              ],
              if (action != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton(onPressed: onAction, child: Text(action!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Grey placeholder cards while a list loads. Still with Reduce Motion
/// (there's no shimmer either way, so nothing moves).
class SkeletonList extends StatelessWidget {
  const SkeletonList({this.count = 5, this.label = 'Loading', super.key});

  final int count;

  /// What screen readers hear.
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(tokens.radius(6)),
      ),
    );
    return Semantics(
      label: label,
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border.all(color: tokens.line),
                borderRadius: BorderRadius.circular(tokens.radius(16)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: tokens.surfaceOverlay,
                      borderRadius: BorderRadius.circular(tokens.radius(12)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(120.0 + (i % 3) * 30, 14),
                        const SizedBox(height: 8),
                        bar(80, 10),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
