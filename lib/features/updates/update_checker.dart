/// Update checks for the desktop apps downloaded from ircage.com.
///
/// Only builds made by `.github/workflows/release.yml` check: they're built
/// with `--dart-define=DISTRIBUTION=direct` and `APP_VERSION=<version>`.
/// App Store, Google Play and local builds never do (the stores update apps
/// themselves, and Apple doesn't allow pointing to other downloads).
library;

import 'dart:async';
import 'dart:convert';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:irc_client/core/storage/app_storage.dart';

/// This build's version, set by the release workflow.
const String appVersion = String.fromEnvironment('APP_VERSION');

/// `direct` for builds people download from the website.
const String distribution = String.fromEnvironment('DISTRIBUTION');

/// Where releases are published.
final Uri latestReleaseApi = Uri.parse(
  'https://api.github.com/repos/djc998/mircmobile/releases/latest',
);

/// How often to look again while the app stays open.
const Duration updateCheckInterval = Duration(hours: 24);

/// Whether this build looks for updates: a website download, with its
/// version known, on a computer.
bool updatesSupported({
  String version = appVersion,
  String channel = distribution,
  TargetPlatform? platform,
}) {
  final p = platform ?? defaultTargetPlatform;
  final desktop = switch (p) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };
  return desktop && channel == 'direct' && version.isNotEmpty;
}

/// Compares `1.2.3`-style versions (a leading `v` and anything after `-`
/// or `+` are ignored). Negative when [a] is older than [b].
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp('^v'), '')
      .split(RegExp('[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d;
  }
  return 0;
}

/// A newer release: its version and where to get it.
@immutable
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.page});

  final String version;

  /// The release's page, with the download files and notes.
  final Uri page;
}

class UpdateState {
  const UpdateState({
    this.enabled = true,
    this.available,
    this.dismissed,
    this.lastChecked,
    this.checking = false,
  });

  /// Settings → About → Check for updates.
  final bool enabled;

  /// A newer version, once found.
  final AvailableUpdate? available;

  /// The version whose banner was closed with Later (asked again for the
  /// next one).
  final String? dismissed;
  final DateTime? lastChecked;
  final bool checking;

  /// Show the banner: a newer version that wasn't put off.
  bool get showBanner => available != null && available!.version != dismissed;

  UpdateState copyWith({
    bool? enabled,
    AvailableUpdate? available,
    bool clearAvailable = false,
    String? dismissed,
    DateTime? lastChecked,
    bool? checking,
  }) => UpdateState(
    enabled: enabled ?? this.enabled,
    available: clearAvailable ? null : available ?? this.available,
    dismissed: dismissed ?? this.dismissed,
    lastChecked: lastChecked ?? this.lastChecked,
    checking: checking ?? this.checking,
  );
}

/// The HTTP client update checks use; tests replace it.
final updateHttpClientProvider = Provider<http.Client>((ref) => http.Client());

/// Whether this build checks at all; tests replace it.
final updatesSupportedProvider = Provider<bool>((ref) => updatesSupported());

/// This build's version; tests replace it.
final appVersionProvider = Provider<String>((ref) => appVersion);

final updateProvider = NotifierProvider<UpdateController, UpdateState>(
  UpdateController.new,
);

class UpdateController extends Notifier<UpdateState> {
  static const _key = 'updates';
  Timer? _timer;

  @override
  UpdateState build() {
    ref.onDispose(() => _timer?.cancel());
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    var saved = const UpdateState();
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        saved = UpdateState(
          enabled: json['enabled'] as bool? ?? true,
          dismissed: json['dismissed'] as String?,
        );
      } on Object {
        // Start fresh.
      }
    }
    return saved;
  }

  /// Checks now, then every [updateCheckInterval] while the app runs.
  void start() {
    if (!ref.read(updatesSupportedProvider)) return;
    unawaited(check());
    _timer?.cancel();
    _timer = Timer.periodic(updateCheckInterval, (_) => unawaited(check()));
  }

  /// Asks GitHub for the latest release. Quiet on errors: offline, rate
  /// limited or no release yet all just mean "nothing new".
  Future<void> check() async {
    if (!ref.read(updatesSupportedProvider) || !state.enabled) return;
    state = state.copyWith(checking: true);
    AvailableUpdate? found;
    try {
      final res = await ref
          .read(updateHttpClientProvider)
          .get(
            latestReleaseApi,
            headers: {'accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, Object?>;
        final tag = json['tag_name'] as String? ?? '';
        final page = Uri.tryParse(json['html_url'] as String? ?? '');
        final current = ref.read(appVersionProvider);
        if (tag.isNotEmpty &&
            page != null &&
            page.scheme == 'https' &&
            compareVersions(tag, current) > 0) {
          found = AvailableUpdate(
            version: tag.replaceFirst(RegExp('^v'), ''),
            page: page,
          );
        }
      }
    } on Object {
      // Nothing new this time.
    }
    if (!ref.mounted) return;
    state = UpdateState(
      enabled: state.enabled,
      available: found,
      dismissed: state.dismissed,
      lastChecked: clock.now(),
    );
  }

  /// Hides the banner until a newer version than this one comes out.
  void later() {
    final v = state.available?.version;
    if (v == null) return;
    state = state.copyWith(dismissed: v);
    _save();
  }

  void setEnabled({required bool enabled}) {
    state = UpdateState(
      enabled: enabled,
      available: enabled ? state.available : null,
      dismissed: state.dismissed,
      lastChecked: state.lastChecked,
    );
    _save();
    if (enabled) unawaited(check());
  }

  void _save() => unawaited(
    ref
        .read(keyValueStoreProvider)
        .setString(
          _key,
          jsonEncode({'enabled': state.enabled, 'dismissed': state.dismissed}),
        ),
  );
}
