/// Networks the user added themselves: name, server address, port and
/// TLS, kept on the device. A server password goes to the [SecretStore].
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/core/storage/app_storage.dart';

/// A network the user added.
class CustomNetwork {
  const CustomNetwork({
    required this.host,
    this.name = '',
    this.port = 6697,
    this.useTls = true,
  });

  factory CustomNetwork.fromJson(Map<String, Object?> json) => CustomNetwork(
    host: json['host'] as String? ?? '',
    name: json['name'] as String? ?? '',
    port: json['port'] as int? ?? 6697,
    useTls: json['useTls'] as bool? ?? true,
  );

  final String host;

  /// What the user called it; empty shows the server address.
  final String name;
  final int port;
  final bool useTls;

  String get displayName => name.trim().isEmpty ? host : name.trim();

  /// As an [IrcNetwork] for the picker and connecting.
  IrcNetwork get network => IrcNetwork(
    name: displayName,
    host: host,
    port: port,
    useTls: useTls,
    description: [
      if (name.trim().isNotEmpty) host,
      'port $port',
      if (!useTls) 'not encrypted',
    ].join(' · '),
  );

  Map<String, Object?> toJson() => {
    'host': host,
    'name': name,
    'port': port,
    'useTls': useTls,
  };
}

/// The port to suggest for an encrypted or plain connection.
int defaultPort({required bool useTls}) => useTls ? 6697 : 6667;

/// Splits what was typed in the server field into a host and, when it
/// ends in `:port` (or `:+port` for TLS, as some sites write it), a port.
/// Returns null when it isn't a usable server address.
({String host, int? port, bool? tls})? parseServer(String text) {
  var s = text.trim();
  s = s.replaceFirst(RegExp('^ircs?://', caseSensitive: false), '');
  final tlsScheme = text.trim().toLowerCase().startsWith('ircs://');
  s = s.replaceFirst(RegExp(r'/.*$'), '');
  int? port;
  var tls = tlsScheme ? true : null;
  final m = RegExp(r'^(.+):(\+?)(\d{1,5})$').firstMatch(s);
  if (m != null) {
    s = m[1]!;
    port = int.parse(m[3]!);
    if (m[2] == '+') tls = true;
    if (port < 1 || port > 65535) return null;
  }
  if (s.isEmpty || !RegExp(r'^[A-Za-z0-9.\-\[\]:]+$').hasMatch(s)) {
    return null;
  }
  return (host: s, port: port, tls: tls);
}

final customNetworksProvider =
    NotifierProvider<CustomNetworksController, List<CustomNetwork>>(
      CustomNetworksController.new,
    );

class CustomNetworksController extends Notifier<List<CustomNetwork>> {
  static const _key = 'customNetworks';

  static String _passwordKey(String host) => 'pass:${host.toLowerCase()}';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);
  SecretStore get _secrets => ref.read(secretStoreProvider);

  @override
  List<CustomNetwork> build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const [];
    try {
      return [
        for (final n in jsonDecode(raw) as List)
          CustomNetwork.fromJson((n as Map).cast<String, Object?>()),
      ].where((n) => n.host.isNotEmpty).toList();
    } on Object {
      return const [];
    }
  }

  /// The added network for [host], if there is one.
  CustomNetwork? find(String host) {
    final key = host.toLowerCase();
    for (final n in state) {
      if (n.host.toLowerCase() == key) return n;
    }
    return null;
  }

  /// Adds [network], or replaces the one it was edited from ([previousHost],
  /// else the one with the same server). A non-null [password] replaces the
  /// saved server password; an empty one removes it.
  Future<void> save(
    CustomNetwork network, {
    String? previousHost,
    String? password,
  }) async {
    final replace = (previousHost ?? network.host).toLowerCase();
    final index = state.indexWhere(
      (n) =>
          n.host.toLowerCase() == replace ||
          n.host.toLowerCase() == network.host.toLowerCase(),
    );
    final next = [...state];
    if (index == -1) {
      next.add(network);
    } else {
      next[index] = network;
    }
    _set(next);
    if (previousHost != null &&
        previousHost.toLowerCase() != network.host.toLowerCase()) {
      final old = await _secrets.read(_passwordKey(previousHost));
      await _secrets.delete(_passwordKey(previousHost));
      password ??= old;
    }
    if (password != null) {
      if (password.isEmpty) {
        await _secrets.delete(_passwordKey(network.host));
      } else {
        await _secrets.write(_passwordKey(network.host), password);
      }
    }
  }

  Future<void> remove(String host) async {
    final key = host.toLowerCase();
    _set([
      for (final n in state)
        if (n.host.toLowerCase() != key) n,
    ]);
    await _secrets.delete(_passwordKey(host));
  }

  Future<String?> password(String host) => _secrets.read(_passwordKey(host));

  void _set(List<CustomNetwork> next) {
    state = next;
    unawaited(
      _store.setString(_key, jsonEncode([for (final n in next) n.toJson()])),
    );
  }
}
