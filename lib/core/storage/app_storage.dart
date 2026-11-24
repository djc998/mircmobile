/// Small storage abstractions so features don't depend on plugins directly.
///
/// `main.dart` overrides the providers with real storage (shared_preferences
/// and the platform keychain/keystore). The in-memory defaults keep tests
/// and previews free of platform channels.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Non-secret settings (nickname, favorites, ...).
abstract interface class KeyValueStore {
  String? getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

/// Secrets such as account passwords. Backed by the iOS/macOS Keychain,
/// Android Keystore-encrypted storage, the Windows Credential Manager and,
/// on Linux, the Secret Service (GNOME Keyring, KWallet) through libsecret.
abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

class MemoryKeyValueStore implements KeyValueStore {
  MemoryKeyValueStore([Map<String, String>? initial]) : values = {...?initial};

  final Map<String, String> values;

  @override
  String? getString(String key) => values[key];

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Uses [primary] while it works and falls back to memory when it can't be
/// reached: a Linux desktop with no keyring running, say. Passwords then
/// last until the app quits instead of failing to save.
class FallbackSecretStore implements SecretStore {
  FallbackSecretStore(this.primary);

  final SecretStore primary;
  final _memory = MemorySecretStore();
  bool _failed = false;

  /// Whether the system store failed and secrets are only kept in memory.
  bool get usingMemory => _failed;

  Future<T> _try<T>(Future<T> Function(SecretStore store) run) async {
    if (!_failed) {
      try {
        return await run(primary);
      } on Object {
        _failed = true;
      }
    }
    return await run(_memory);
  }

  @override
  Future<String?> read(String key) => _try((s) => s.read(key));

  @override
  Future<void> write(String key, String value) =>
      _try((s) => s.write(key, value));

  @override
  Future<void> delete(String key) => _try((s) => s.delete(key));
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Overridden in `main.dart` with [PrefsKeyValueStore].
final keyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => MemoryKeyValueStore(),
);

/// Overridden in `main.dart` with [SecureSecretStore].
final secretStoreProvider = Provider<SecretStore>((ref) => MemorySecretStore());
