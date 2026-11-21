/// Certificates the user chose to trust, per server host.
///
/// Some networks (notably EFnet) use self-signed or mismatched certificates.
/// Instead of turning verification off, the app asks once and remembers the
/// exact certificate fingerprint, so a different certificate later is still
/// rejected.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';

class CertificateTrustStore {
  CertificateTrustStore(this._store);

  static const _key = 'trustedCertificates';

  final KeyValueStore _store;

  Map<String, List<String>> _load() {
    final raw = _store.getString(_key);
    if (raw == null) return {};
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      return {
        for (final e in json.entries)
          if (e.value is List) e.key: [for (final f in e.value! as List) '$f'],
      };
    } on Object {
      return {};
    }
  }

  /// Fingerprints trusted for [host].
  Set<String> fingerprintsFor(String host) => {...?_load()[host.toLowerCase()]};

  Future<void> trust(String host, String fingerprint) async {
    final all = _load();
    final list = all.putIfAbsent(host.toLowerCase(), () => []);
    if (!list.contains(fingerprint)) list.add(fingerprint);
    await _store.setString(_key, jsonEncode(all));
  }

  Future<void> forget(String host) async {
    final all = _load()..remove(host.toLowerCase());
    await _store.setString(_key, jsonEncode(all));
  }
}

final certificateTrustStoreProvider = Provider<CertificateTrustStore>(
  (ref) => CertificateTrustStore(ref.watch(keyValueStoreProvider)),
);
