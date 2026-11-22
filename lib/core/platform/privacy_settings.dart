/// Opens the system settings page where people allow the camera and
/// microphone, so they don't have to hunt for it.
library;

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

enum PrivacyPage { camera, microphone }

abstract interface class PrivacySettings {
  /// Whether this platform has separate Camera and Microphone pages
  /// (macOS, Windows). On phones there is one page for the app.
  bool get separatePages;

  /// Opens the settings page. Returns false if it couldn't.
  Future<bool> open(PrivacyPage page);
}

class SystemPrivacySettings implements PrivacySettings {
  const SystemPrivacySettings();

  static const _android = MethodChannel('irc_client/settings');

  @override
  bool get separatePages => Platform.isMacOS || Platform.isWindows;

  @override
  Future<bool> open(PrivacyPage page) async {
    try {
      if (Platform.isMacOS) {
        final pane = page == PrivacyPage.camera
            ? 'Privacy_Camera'
            : 'Privacy_Microphone';
        return await launchUrl(
          Uri.parse(
            'x-apple.systempreferences:com.apple.preference.security?$pane',
          ),
        );
      }
      if (Platform.isWindows) {
        return await launchUrl(
          Uri.parse(
            page == PrivacyPage.camera
                ? 'ms-settings:privacy-webcam'
                : 'ms-settings:privacy-microphone',
          ),
        );
      }
      if (Platform.isIOS) {
        // The app's own page in Settings, with its Camera and Microphone
        // switches.
        return await launchUrl(Uri.parse('app-settings:'));
      }
      if (Platform.isAndroid) {
        return await _android.invokeMethod<bool>('openAppSettings') ?? false;
      }
    } on Object {
      return false;
    }
    return false;
  }
}

final privacySettingsProvider = Provider<PrivacySettings>(
  (ref) => const SystemPrivacySettings(),
);
