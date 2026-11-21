/// Remembers the last nickname, network and account between launches.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';

class SavedConnection {
  const SavedConnection({
    required this.nick,
    required this.networkHost,
    this.account,
    this.rememberPassword = true,
    this.rejoinFavorites = true,
  });

  factory SavedConnection.fromJson(Map<String, Object?> json) =>
      SavedConnection(
        nick: json['nick'] as String? ?? '',
        networkHost: json['networkHost'] as String? ?? '',
        account: json['account'] as String?,
        rememberPassword: json['rememberPassword'] as bool? ?? true,
        rejoinFavorites: json['rejoinFavorites'] as bool? ?? true,
      );

  final String nick;

  /// Host of the network last connected to, e.g. `irc.libera.chat`.
  final String networkHost;

  /// SASL account name, or null when not logging in.
  final String? account;
  final bool rememberPassword;

  /// Join this network's favorite rooms automatically on connect.
  final bool rejoinFavorites;

  Map<String, Object?> toJson() => {
    'nick': nick,
    'networkHost': networkHost,
    'account': account,
    'rememberPassword': rememberPassword,
    'rejoinFavorites': rejoinFavorites,
  };
}

/// Reads and writes [SavedConnection]; passwords go to the [SecretStore].
class SavedConnectionRepository {
  SavedConnectionRepository(this._store, this._secrets);

  static const _key = 'savedConnection';

  final KeyValueStore _store;
  final SecretStore _secrets;

  static String _passwordKey(String host, String account) =>
      'sasl:${host.toLowerCase()}:$account';

  SavedConnection? load() {
    final raw = _store.getString(_key);
    if (raw == null) return null;
    try {
      return SavedConnection.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return null; // Corrupt or old format: start fresh.
    }
  }

  Future<String?> loadPassword(String host, String account) =>
      _secrets.read(_passwordKey(host, account));

  /// Saves settings. The password is stored only when
  /// [SavedConnection.rememberPassword] is on, and deleted otherwise.
  Future<void> save(SavedConnection connection, {String? password}) async {
    await _store.setString(_key, jsonEncode(connection.toJson()));
    final account = connection.account;
    if (account == null || account.isEmpty) return;
    final key = _passwordKey(connection.networkHost, account);
    if (connection.rememberPassword &&
        password != null &&
        password.isNotEmpty) {
      await _secrets.write(key, password);
    } else {
      await _secrets.delete(key);
    }
  }
}

final savedConnectionRepositoryProvider = Provider<SavedConnectionRepository>(
  (ref) => SavedConnectionRepository(
    ref.watch(keyValueStoreProvider),
    ref.watch(secretStoreProvider),
  ),
);
