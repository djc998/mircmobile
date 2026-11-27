/// System notifications: private messages and mentions while the app is in
/// the background, and Android's "staying connected" notification.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the app needs from the system's notifications. Tests use a fake;
/// `main.dart` overrides [messageNotifierProvider] with
/// [LocalMessageNotifier].
abstract class MessageNotifier {
  /// Whether this platform shows message notifications at all.
  bool get supportsMessages;

  /// Whether this platform can keep the app running in the background with
  /// a foreground service (Android only).
  bool get supportsKeepAlive;

  /// Called with a notification's payload when the user taps it.
  void setOnTap(void Function(String payload)? callback);

  /// Asks for permission to show notifications (iOS, macOS, Android 13+).
  Future<bool> requestPermission();

  /// Shows a notification; one per [id], so a newer one replaces it.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  /// Removes notification [id], e.g. when its chat is opened.
  Future<void> cancel(int id);

  /// Starts the foreground service with its ongoing notification.
  Future<void> startKeepAlive();

  /// Stops the foreground service.
  Future<void> stopKeepAlive();
}

/// No notifications (tests, Windows and Linux).
class NoMessageNotifier implements MessageNotifier {
  @override
  bool get supportsMessages => false;
  @override
  bool get supportsKeepAlive => false;
  @override
  void setOnTap(void Function(String payload)? callback) {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {}
  @override
  Future<void> cancel(int id) async {}
  @override
  Future<void> startKeepAlive() async {}
  @override
  Future<void> stopKeepAlive() async {}
}

final messageNotifierProvider = Provider<MessageNotifier>(
  (ref) => NoMessageNotifier(),
);

/// Notifications through flutter_local_notifications on iOS, Android and
/// macOS.
class LocalMessageNotifier implements MessageNotifier {
  LocalMessageNotifier._(this._plugin);

  /// Sets up the plugin; on other platforms returns [NoMessageNotifier].
  static Future<MessageNotifier> create() async {
    if (kIsWeb || !(Platform.isIOS || Platform.isAndroid || Platform.isMacOS)) {
      return NoMessageNotifier();
    }
    final plugin = FlutterLocalNotificationsPlugin();
    final notifier = LocalMessageNotifier._(plugin);
    // Permission is asked later, when it's needed, not at launch.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_notify'),
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (r) => notifier._tapped(r.payload),
      );
      // Opened by tapping a notification while the app wasn't running.
      final launch = await plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        notifier._pending = launch!.notificationResponse?.payload;
      }
    } on Object catch (e) {
      debugPrint('Notifications unavailable: $e');
      return NoMessageNotifier();
    }
    return notifier;
  }

  final FlutterLocalNotificationsPlugin _plugin;
  void Function(String payload)? _onTap;
  String? _pending;
  bool _keepingAlive = false;

  /// Notification id of the foreground service (must not be 0).
  static const _keepAliveId = 1;

  static const _messages = AndroidNotificationDetails(
    'messages',
    'Messages',
    channelDescription: 'Private messages and mentions of your nickname',
    importance: Importance.high,
    priority: Priority.high,
    category: AndroidNotificationCategory.message,
  );

  static const _connection = AndroidNotificationDetails(
    'connection',
    'Staying connected',
    channelDescription: 'Shown while IRCage stays connected in the background',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    showWhen: false,
    category: AndroidNotificationCategory.service,
  );

  void _tapped(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final callback = _onTap;
    if (callback == null) {
      _pending = payload;
    } else {
      callback(payload);
    }
  }

  @override
  bool get supportsMessages => true;

  @override
  bool get supportsKeepAlive => Platform.isAndroid;

  @override
  void setOnTap(void Function(String payload)? callback) {
    _onTap = callback;
    final pending = _pending;
    if (callback != null && pending != null) {
      _pending = null;
      callback(pending);
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      if (Platform.isAndroid) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.requestNotificationsPermission() ??
            false;
      }
      if (Platform.isIOS) {
        return await _plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      }
      return await _plugin
              .resolvePlatformSpecificImplementation<
                MacOSFlutterLocalNotificationsPlugin
              >()
              ?.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    } on Object catch (e) {
      debugPrint('Notification permission failed: $e');
      return false;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: _messages,
          iOS: DarwinNotificationDetails(threadIdentifier: payload),
          macOS: DarwinNotificationDetails(threadIdentifier: payload),
        ),
      );
    } on Object catch (e) {
      debugPrint('Notification failed: $e');
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await _plugin.cancel(id: id);
    } on Object catch (e) {
      debugPrint('Cancelling a notification failed: $e');
    }
  }

  @override
  Future<void> startKeepAlive() async {
    if (!Platform.isAndroid || _keepingAlive) return;
    _keepingAlive = true;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.startForegroundService(
            id: _keepAliveId,
            title: 'IRCage is staying connected',
            body:
                'You get messages while the app is in the background. '
                'Turn this off in Settings → Notifications.',
            notificationDetails: _connection,
            startType: AndroidServiceStartType.startNotSticky,
            foregroundServiceTypes: {
              AndroidServiceForegroundType.foregroundServiceTypeSpecialUse,
            },
          );
    } on Object catch (e) {
      _keepingAlive = false;
      debugPrint('Foreground service failed: $e');
    }
  }

  @override
  Future<void> stopKeepAlive() async {
    if (!Platform.isAndroid || !_keepingAlive) return;
    _keepingAlive = false;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.stopForegroundService();
    } on Object catch (e) {
      debugPrint('Stopping the foreground service failed: $e');
    }
  }
}
