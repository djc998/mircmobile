/// Remembers the nickname, open networks and account between launches.
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
    this.username,
    this.realname,
    this.networkHosts = const [],
  });

  factory SavedConnection.fromJson(Map<String, Object?> json) =>
      SavedConnection(
        nick: json['nick'] as String? ?? '',
        networkHost: json['networkHost'] as String? ?? '',
        account: json['account'] as String?,
        rememberPassword: json['rememberPassword'] as bool? ?? true,
        rejoinFavorites: json['rejoinFavorites'] as bool? ?? true,
        username: json['username'] as String?,
        realname: json['realname'] as String?,
        networkHosts: [
          for (final h in json['networkHosts'] as List? ?? const []) '$h',
        ],
      );

  final String nick;

  /// Host of the network last connected to, e.g. `irc.libera.chat`.
  final String networkHost;

  /// SASL account name, or null when not logging in.
  final String? account;
  final bool rememberPassword;

  /// Join this network's favorite rooms automatically on connect.
  final bool rejoinFavorites;

  /// Optional IRC username and real name; defaults are used when empty.
  final String? username;
  final String? realname;

  /// Every network that was open, so "Continue" can reconnect them all.
  /// Older saves only have [networkHost].
  final List<String> networkHosts;

  /// [networkHosts], or just [networkHost] for older saves.
  List<String> get openNetworks => networkHosts.isNotEmpty
      ? networkHosts
      : [if (networkHost.isNotEmpty) networkHost];

  SavedConnection copyWith({List<String>? networkHosts}) => SavedConnection(
    nick: nick,
    networkHost: networkHost,
    account: account,
    rememberPassword: rememberPassword,
    rejoinFavorites: rejoinFavorites,
    username: username,
    realname: realname,
    networkHosts: networkHosts ?? this.networkHosts,
  );

  Map<String, Object?> toJson() => {
    'nick': nick,
    'networkHost': networkHost,
    'account': account,
    'rememberPassword': rememberPassword,
    'rejoinFavorites': rejoinFavorites,
    'username': username,
    'realname': realname,
    'networkHosts': networkHosts,
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

  /// Saves a new nickname, keeping the other settings.
  Future<void> rememberNick(String nick) async {
    final saved = load();
    final json = saved?.toJson() ?? {'networkHost': ''};
    await _store.setString(_key, jsonEncode({...json, 'nick': nick}));
  }

  /// Forgets [host] as an open network, after the user closed it.
  Future<void> removeNetwork(String host) async {
    final saved = load();
    if (saved == null) return;
    final key = host.toLowerCase();
    await _store.setString(
      _key,
      jsonEncode(
        saved
            .copyWith(
              networkHosts: [
                for (final h in saved.openNetworks)
                  if (h.toLowerCase() != key) h,
              ],
            )
            .toJson(),
      ),
    );
  }

  /// Saves [password] for [account] on [host] (after registering a
  /// nickname) and makes it the account to log in with when none is set.
  Future<void> rememberAccount(
    String host,
    String account,
    String password,
  ) async {
    await _secrets.write(_passwordKey(host, account), password);
    final saved = load();
    if (saved != null && (saved.account == null || saved.account!.isEmpty)) {
      await _store.setString(
        _key,
        jsonEncode({...saved.toJson(), 'account': account}),
      );
    }
  }

  Future<String?> loadPassword(String host, String account) =>
      _secrets.read(_passwordKey(host, account));

  /// Saves settings. A non-empty password is stored when
  /// [SavedConnection.rememberPassword] is on (an empty one keeps the saved
  /// password); with it off, the saved password is deleted.
  Future<void> save(SavedConnection connection, {String? password}) async {
    await _store.setString(_key, jsonEncode(connection.toJson()));
    final account = connection.account;
    if (account == null || account.isEmpty) return;
    final key = _passwordKey(connection.networkHost, account);
    if (!connection.rememberPassword) {
      await _secrets.delete(key);
    } else if (password != null && password.isNotEmpty) {
      await _secrets.write(key, password);
    }
  }
}

final savedConnectionRepositoryProvider = Provider<SavedConnectionRepository>(
  (ref) => SavedConnectionRepository(
    ref.watch(keyValueStoreProvider),
    ref.watch(secretStoreProvider),
  ),
);
