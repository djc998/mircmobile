/// Menus and confirmations that feel native on each platform:
///
/// - iPhone and iPad: an iOS action sheet and iOS alerts.
/// - Mac: a context menu at the pointer for right-clicks, and Mac-style
///   alerts.
/// - Android (and everywhere else): Material bottom sheets and dialogs.
library;

import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart'
    show
        CupertinoActionSheet,
        CupertinoActionSheetAction,
        CupertinoDialogAction,
        showCupertinoModalPopup;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Whether this is an Apple platform (iOS or macOS).
bool isApple(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => true,
  _ => false,
};

/// One choice in [showActionMenu].
class MenuAction {
  const MenuAction({
    required this.label,
    required this.onSelected,
    this.icon,
    this.subtitle,
    this.destructive = false,
    this.enabled = true,
  });

  final String label;
  final VoidCallback onSelected;
  final IconData? icon;

  /// A second line (Material sheets only).
  final String? subtitle;

  /// Shown in red on Apple platforms (leave, delete, report).
  final bool destructive;
  final bool enabled;
}

/// Shows [actions] the platform's way, then runs the one picked (after the
/// menu has closed). [position] is the pointer for a right-click: on a Mac
/// that opens a context menu there.
Future<void> showActionMenu(
  BuildContext context, {
  required List<MenuAction> actions,
  String? title,
  Offset? position,
}) async {
  final platform = Theme.of(context).platform;
  MenuAction? picked;
  if (platform == TargetPlatform.macOS && position != null) {
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    picked = await showMenu<MenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final a in actions)
          PopupMenuItem(
            value: a,
            enabled: a.enabled,
            height: 36,
            child: Text(
              a.label,
              style: a.destructive
                  ? TextStyle(color: Theme.of(context).colorScheme.error)
                  : null,
            ),
          ),
      ],
    );
  } else if (platform == TargetPlatform.iOS) {
    unawaited(HapticFeedback.mediumImpact());
    picked = await showCupertinoModalPopup<MenuAction>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        actions: [
          for (final a in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: a.destructive,
              onPressed: a.enabled ? () => Navigator.pop(sheet, a) : () {},
              child: Text(a.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(sheet),
          child: const Text('Cancel'),
        ),
      ),
    );
  } else {
    picked = await showModalBottomSheet<MenuAction>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    title,
                    style: Theme.of(sheet).textTheme.titleMedium,
                  ),
                ),
              for (final a in actions)
                ListTile(
                  leading: a.icon == null ? null : Icon(a.icon),
                  title: Text(a.label),
                  subtitle: a.subtitle == null ? null : Text(a.subtitle!),
                  enabled: a.enabled,
                  onTap: () => Navigator.pop(sheet, a),
                ),
            ],
          ),
        ),
      ),
    );
  }
  picked?.onSelected();
}

/// Asks to confirm something; true when confirmed. iOS and Mac get the
/// system alert style, with [confirmLabel] in red when [destructive].
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final apple = isApple(context);
  Widget action(
    BuildContext dialog,
    String label, {
    required bool result,
    bool primary = false,
  }) => apple
      ? CupertinoDialogAction(
          isDestructiveAction: primary && destructive,
          isDefaultAction: primary && !destructive,
          onPressed: () => Navigator.pop(dialog, result),
          child: Text(label),
        )
      : primary
      ? FilledButton(
          onPressed: () => Navigator.pop(dialog, result),
          child: Text(label),
        )
      : TextButton(
          onPressed: () => Navigator.pop(dialog, result),
          child: Text(label),
        );
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog.adaptive(
      title: Text(title),
      content: Text(message),
      actions: [
        action(dialog, 'Cancel', result: false),
        action(dialog, confirmLabel, result: true, primary: true),
      ],
    ),
  );
  return ok ?? false;
}
