/// Android: runs the foreground service while "Stay connected in the
/// background" is on and a network is open.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/notifications/application/notification_settings.dart';
import 'package:irc_client/features/notifications/data/message_notifier.dart';

/// Whether the foreground service should run: the setting is on, the
/// platform has one (Android) and at least one network isn't disconnected.
///
/// Watched by `AppLifecycleWatcher`, which keeps it alive for the app's
/// lifetime. It only changes in the foreground in practice (a network
/// stays "reconnecting" in the background, never "disconnected" on its
/// own), which matters because Android 12+ doesn't let apps start a
/// foreground service from the background.
final keepAliveProvider = Provider<bool>((ref) {
  final notifier = ref.watch(messageNotifierProvider);
  final wanted = ref.watch(
    notificationSettingsProvider.select((s) => s.stayConnected),
  );
  final anyOpen = ref.watch(
    chatControllerProvider.select(
      (s) => s.networks.values.any(
        (n) => n.status != IrcConnectionStatus.disconnected,
      ),
    ),
  );
  final on = wanted && notifier.supportsKeepAlive && anyOpen;
  unawaited(on ? notifier.startKeepAlive() : notifier.stopKeepAlive());
  return on;
});
