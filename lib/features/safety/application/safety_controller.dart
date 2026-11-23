/// Safety settings: which terms were agreed to, the word filter and hiding
/// adult rooms. Saved on the device.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/app/legal.dart';
import 'package:irc_client/core/storage/app_storage.dart';

/// Tests start with the terms agreed (set in `flutter_test_config.dart`)
/// so they open on the welcome screen; terms tests turn it off.
@visibleForTesting
bool debugTermsAgreedByDefault = false;

class SafetySettings {
  const SafetySettings({
    this.termsAgreed = 0,
    this.filterWords = true,
    this.hideAdultRooms = true,
    this.sendTyping = true,
  });

  factory SafetySettings.fromJson(Map<String, Object?> json) => SafetySettings(
    termsAgreed: json['termsAgreed'] as int? ?? 0,
    filterWords: json['filterWords'] as bool? ?? true,
    hideAdultRooms: json['hideAdultRooms'] as bool? ?? true,
    sendTyping: json['sendTyping'] as bool? ?? true,
  );

  /// The [termsVersion] last agreed to; 0 for never.
  final int termsAgreed;

  /// Mask offensive words in messages, topics and previews.
  final bool filterWords;

  /// Leave adult rooms out of Discover.
  final bool hideAdultRooms;

  /// Let others see when you're typing (IRCv3 typing notifications).
  final bool sendTyping;

  bool get agreedToTerms => termsAgreed >= termsVersion;

  SafetySettings copyWith({
    int? termsAgreed,
    bool? filterWords,
    bool? hideAdultRooms,
    bool? sendTyping,
  }) => SafetySettings(
    termsAgreed: termsAgreed ?? this.termsAgreed,
    filterWords: filterWords ?? this.filterWords,
    hideAdultRooms: hideAdultRooms ?? this.hideAdultRooms,
    sendTyping: sendTyping ?? this.sendTyping,
  );

  Map<String, Object?> toJson() => {
    'termsAgreed': termsAgreed,
    'filterWords': filterWords,
    'hideAdultRooms': hideAdultRooms,
    'sendTyping': sendTyping,
  };
}

final safetyProvider = NotifierProvider<SafetyController, SafetySettings>(
  SafetyController.new,
);

class SafetyController extends Notifier<SafetySettings> {
  static const _key = 'safety';

  @override
  SafetySettings build() {
    final fallback = SafetySettings(
      termsAgreed: debugTermsAgreedByDefault ? termsVersion : 0,
    );
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return fallback;
    try {
      return SafetySettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return fallback;
    }
  }

  void agreeToTerms() => _set(state.copyWith(termsAgreed: termsVersion));

  void setFilterWords({required bool enabled}) =>
      _set(state.copyWith(filterWords: enabled));

  void setHideAdultRooms({required bool enabled}) =>
      _set(state.copyWith(hideAdultRooms: enabled));

  void setSendTyping({required bool enabled}) =>
      _set(state.copyWith(sendTyping: enabled));

  void _set(SafetySettings next) {
    state = next;
    unawaited(
      ref
          .read(keyValueStoreProvider)
          .setString(_key, jsonEncode(next.toJson())),
    );
  }
}
