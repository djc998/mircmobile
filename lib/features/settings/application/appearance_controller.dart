/// The user's appearance choices: light/dark, theme, accent, density and
/// text size.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';

/// Text size choices, as a scale factor.
const Map<String, double> textSizes = {
  'Small': 0.9,
  'Normal': 1,
  'Large': 1.15,
  'Larger': 1.3,
};

/// How roomy chat lists and messages are.
enum ChatDensity {
  comfortable('Comfortable', 'Avatars next to rooms, people and messages'),
  compact('Compact', 'No avatars: classic HH:MM <nick> lines');

  ChatDensity(this.label, this.description);

  final String label;
  final String description;
}

class Appearance {
  const Appearance({
    this.mode = AppearanceMode.system,
    this.preset = ThemePreset.indigo,
    this.accent = AccentColor.indigo,
    this.density = ChatDensity.comfortable,
    this.textScale = 1,
  });

  /// Reads saved settings. Settings saved before the redesign have no
  /// `version`; their "classic" was simply the old default, so they move to
  /// the new Default theme.
  factory Appearance.fromJson(Map<String, Object?> json) {
    final legacy = json['version'] == null;
    var preset =
        ThemePreset.values.asNameMap()[json['preset']] ?? ThemePreset.indigo;
    if (legacy && preset == ThemePreset.classic) preset = ThemePreset.indigo;
    return Appearance(
      mode:
          AppearanceMode.values.asNameMap()[json['mode']] ??
          AppearanceMode.system,
      preset: preset,
      accent:
          AccentColor.values.asNameMap()[json['accent']] ?? AccentColor.indigo,
      density:
          ChatDensity.values.asNameMap()[json['density']] ??
          ChatDensity.comfortable,
      textScale: (json['textScale'] as num?)?.toDouble() ?? 1,
    );
  }

  /// Bumped when saved settings need moving to new defaults.
  static const version = 2;

  final AppearanceMode mode;
  final ThemePreset preset;

  /// Accent for the Default theme.
  final AccentColor accent;
  final ChatDensity density;
  final double textScale;

  /// Whether [accent] changes [preset]'s colours.
  bool get accentApplies => preset == ThemePreset.indigo;

  Appearance copyWith({
    AppearanceMode? mode,
    ThemePreset? preset,
    AccentColor? accent,
    ChatDensity? density,
    double? textScale,
  }) => Appearance(
    mode: mode ?? this.mode,
    preset: preset ?? this.preset,
    accent: accent ?? this.accent,
    density: density ?? this.density,
    textScale: textScale ?? this.textScale,
  );

  Map<String, Object?> toJson() => {
    'version': version,
    'mode': mode.name,
    'preset': preset.name,
    'accent': accent.name,
    'density': density.name,
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

  /// Picking Classic mIRC also switches to Compact lines, its classic look;
  /// density can still be changed afterwards.
  void setPreset(ThemePreset preset) => _set(
    state.copyWith(
      preset: preset,
      density: preset == ThemePreset.classic && state.preset != preset
          ? ChatDensity.compact
          : null,
    ),
  );

  void setAccent(AccentColor accent) => _set(state.copyWith(accent: accent));

  void setDensity(ChatDensity density) =>
      _set(state.copyWith(density: density));

  void setTextScale(double scale) => _set(state.copyWith(textScale: scale));
}

final appearanceProvider = NotifierProvider<AppearanceController, Appearance>(
  AppearanceController.new,
);
