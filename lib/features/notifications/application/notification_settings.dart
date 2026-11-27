/// Notification settings: message notifications and, on Android, staying
/// connected in the background. Saved on the device.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/notifications/data/message_notifier.dart';

class NotificationSettings {
  const NotificationSettings({
    this.messages = true,
    this.stayConnected = false,
    this.askedPermission = false,
  });

  factory NotificationSettings.fromJson(Map<String, Object?> json) =>
      NotificationSettings(
        messages: json['messages'] as bool? ?? true,
        stayConnected: json['stayConnected'] as bool? ?? false,
        askedPermission: json['askedPermission'] as bool? ?? false,
      );

  /// Notify about private messages and mentions while the app is in the
  /// background.
  final bool messages;

  /// Android: keep the connection open in the background with a foreground
  /// service and its ongoing notification. Off unless the user turns it on.
  final bool stayConnected;

  /// The system's permission prompt was shown once already.
  final bool askedPermission;

  NotificationSettings copyWith({
    bool? messages,
    bool? stayConnected,
    bool? askedPermission,
  }) => NotificationSettings(
    messages: messages ?? this.messages,
    stayConnected: stayConnected ?? this.stayConnected,
    askedPermission: askedPermission ?? this.askedPermission,
  );

  Map<String, Object?> toJson() => {
    'messages': messages,
    'stayConnected': stayConnected,
    'askedPermission': askedPermission,
  };
}

final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsController, NotificationSettings>(
      NotificationSettingsController.new,
    );

class NotificationSettingsController extends Notifier<NotificationSettings> {
  static const _key = 'notifications';

  @override
  NotificationSettings build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const NotificationSettings();
    try {
      return NotificationSettings.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      return const NotificationSettings();
    }
  }

  MessageNotifier get _notifier => ref.read(messageNotifierProvider);

  Future<void> setMessages({required bool enabled}) async {
    _set(state.copyWith(messages: enabled));
    if (enabled) await _ask(force: true);
  }

  Future<void> setStayConnected({required bool enabled}) async {
    _set(state.copyWith(stayConnected: enabled));
    // Android 13+ hides the service's notification without permission.
    if (enabled) await _ask(force: true);
  }

  /// Asks for notification permission the first time it's useful (after
  /// logging in to a network), unless message notifications are off.
  Future<void> askOnce() async {
    if (!state.messages || state.askedPermission) return;
    await _ask();
  }

  Future<void> _ask({bool force = false}) async {
    if (!_notifier.supportsMessages) return;
    if (!force && state.askedPermission) return;
    _set(state.copyWith(askedPermission: true));
    await _notifier.requestPermission();
  }

  void _set(NotificationSettings next) {
    state = next;
    unawaited(
      ref
          .read(keyValueStoreProvider)
          .setString(_key, jsonEncode(next.toJson())),
    );
  }
}
