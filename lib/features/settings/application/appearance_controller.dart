/// The user's appearance choices: light/dark, colour theme and text size.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/theme/app_theme.dart';

/// Text size choices, as a scale factor.
const Map<String, double> textSizes = {
  'Small': 0.9,
  'Normal': 1,
  'Large': 1.15,
  'Larger': 1.3,
};

class Appearance {
  const Appearance({
    this.mode = AppearanceMode.system,
    this.preset = ThemePreset.classic,
    this.textScale = 1,
  });

  factory Appearance.fromJson(Map<String, Object?> json) => Appearance(
    mode:
        AppearanceMode.values.asNameMap()[json['mode']] ??
        AppearanceMode.system,
    preset:
        ThemePreset.values.asNameMap()[json['preset']] ?? ThemePreset.classic,
    textScale: (json['textScale'] as num?)?.toDouble() ?? 1,
  );

  final AppearanceMode mode;
  final ThemePreset preset;
  final double textScale;

  Appearance copyWith({
    AppearanceMode? mode,
    ThemePreset? preset,
    double? textScale,
  }) => Appearance(
    mode: mode ?? this.mode,
    preset: preset ?? this.preset,
    textScale: textScale ?? this.textScale,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'preset': preset.name,
    'textScale': textScale,
  };
}

/// Loads and saves [Appearance] (key `appearance`).
class AppearanceController extends Notifier<Appearance> {
  static const _key = 'appearance';

  @override
  Appearance build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const Appearance();
    try {
      return Appearance.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return const Appearance();
    }
  }

  void _set(Appearance value) {
    state = value;
    unawaited(
      ref
          .read(keyValueStoreProvider)
          .setString(_key, jsonEncode(value.toJson())),
    );
  }

  void setMode(AppearanceMode mode) => _set(state.copyWith(mode: mode));

  void setPreset(ThemePreset preset) => _set(state.copyWith(preset: preset));

  void setTextScale(double scale) => _set(state.copyWith(textScale: scale));
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);
