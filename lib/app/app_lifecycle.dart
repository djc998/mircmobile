/// Tells the chat when the app goes to the background and comes back.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/notifications/application/keep_alive.dart';
import 'package:irc_client/features/notifications/data/message_notifier.dart';
import 'package:material_ui/material_ui.dart';

/// Watches the app's lifecycle for [ChatController]: when the app is hidden
/// it notes what was seen, and when it's shown again it checks every
/// connection (see [ChatController.appResumed]).
///
/// It also opens the chat a tapped notification is about, and keeps
/// Android's foreground service ([keepAliveProvider]) in step.
///
/// Only a real trip to the background counts: pulling down Control Center
/// or the notification shade makes the app inactive but not hidden, and
/// doesn't trigger a check.
class AppLifecycleWatcher extends ConsumerStatefulWidget {
  const AppLifecycleWatcher({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<AppLifecycleWatcher> createState() =>
      _AppLifecycleWatcherState();
}

class _AppLifecycleWatcherState extends ConsumerState<AppLifecycleWatcher> {
  late final AppLifecycleListener _listener;
  late final MessageNotifier _notifier;
  bool _wasHidden = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onHide: () {
        if (_wasHidden) return;
        _wasHidden = true;
        ref.read(chatControllerProvider.notifier).appPaused();
      },
      onShow: () {
        if (!_wasHidden) return;
        _wasHidden = false;
        ref.read(chatControllerProvider.notifier).appResumed();
      },
    );
    _notifier = ref.read(messageNotifierProvider)
      ..setOnTap(_openFromNotification);
  }

  /// A notification was tapped: show its conversation, if it's still open.
  void _openFromNotification(String key) {
    if (!mounted) return;
    if (!ref.read(chatControllerProvider).buffers.containsKey(key)) return;
    ref.read(chatControllerProvider.notifier).selectBuffer(key);
    ref.read(routerProvider).go('/chat');
  }

  @override
  void dispose() {
    _notifier.setOnTap(null);
    _listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(keepAliveProvider);
    return widget.child;
  }
}
