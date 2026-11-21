import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/connection/data/saved_connection.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:material_ui/material_ui.dart';

/// First screen: pick a nickname and a network, then connect.
///
/// Remembers the nickname, last network and account, and offers a one-tap
/// "Continue" card for the last network.
class NetworkPickerScreen extends ConsumerStatefulWidget {
  const NetworkPickerScreen({super.key});

  @override
  ConsumerState<NetworkPickerScreen> createState() =>
      _NetworkPickerScreenState();
}

class _NetworkPickerScreenState extends ConsumerState<NetworkPickerScreen> {
  final _nick = TextEditingController();
  final _channels = TextEditingController();
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _useAccount = false;
  bool _rememberPassword = true;
  bool _rejoinFavorites = true;
  SavedConnection? _saved;

  @override
  void initState() {
    super.initState();
    final repo = ref.read(savedConnectionRepositoryProvider);
    final saved = repo.load();
    if (saved == null) return;
    _saved = saved;
    _nick.text = saved.nick;
    _rememberPassword = saved.rememberPassword;
    _rejoinFavorites = saved.rejoinFavorites;
    final account = saved.account;
    if (account != null && account.isNotEmpty) {
      _useAccount = true;
      _account.text = account;
      unawaited(
        repo.loadPassword(saved.networkHost, account).then((pw) {
          if (mounted && pw != null && _password.text.isEmpty) {
            _password.text = pw;
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _nick.dispose();
    _channels.dispose();
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  IrcNetwork? get _lastNetwork {
    final host = _saved?.networkHost;
    if (host == null) return null;
    for (final n in builtInNetworks) {
      if (n.host == host) return n;
    }
    return null;
  }

  Future<void> _connect(IrcNetwork network) async {
    final nick = _nick.text.trim();
    if (!isValidNick(nick)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pick a nickname: letters, numbers and _-[]{}|^ only, '
            'starting with a letter.',
          ),
        ),
      );
      return;
    }
    final typed = _channels.text
        .split(RegExp(r'[\s,]+'))
        .where((c) => c.isNotEmpty)
        .map((c) => c.startsWith('#') ? c : '#$c');
    final favorites = _rejoinFavorites
        ? ref.read(roomPrefsProvider).favoritesFor(network.host)
        : const <String>[];
    final autoJoin = <String>[];
    for (final room in [...favorites, ...typed]) {
      if (!autoJoin.any((r) => r.toLowerCase() == room.toLowerCase())) {
        autoJoin.add(room);
      }
    }

    final repo = ref.read(savedConnectionRepositoryProvider);
    final account = _useAccount ? _account.text.trim() : '';
    var password = _password.text;
    if (account.isNotEmpty && password.isEmpty) {
      password = await repo.loadPassword(network.host, account) ?? '';
    }
    unawaited(
      repo.save(
        SavedConnection(
          nick: nick,
          networkHost: network.host,
          account: account.isEmpty ? null : account,
          rememberPassword: _rememberPassword,
          rejoinFavorites: _rejoinFavorites,
        ),
        password: password,
      ),
    );

    final config = IrcConnectionConfig(
      host: network.host,
      port: network.port,
      useTls: network.useTls,
      nick: nick,
      autoJoin: autoJoin,
      sasl: account.isNotEmpty
          ? SaslCredentials(account: account, password: password)
          : null,
    );
    unawaited(ref.read(chatControllerProvider.notifier).connect(config));
    if (mounted) context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = ref.watch(roomPrefsProvider);
    final last = _lastNetwork;
    final lastFavorites = last == null
        ? const <String>[]
        : prefs.favoritesFor(last.host);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose a network')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (last != null && _saved!.nick.isNotEmpty) ...[
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text('Continue on ${last.name}'),
                  subtitle: Text(
                    lastFavorites.isEmpty || !_rejoinFavorites
                        ? 'as ${_saved!.nick}'
                        : 'as ${_saved!.nick} · rejoins '
                              '${lastFavorites.take(3).join(', ')}'
                              '${lastFavorites.length > 3 ? '…' : ''}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _connect(last),
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _nick,
              autocorrect: false,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Nickname',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _channels,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'Rooms to join (optional)',
                hintText: '#linux, #chat',
                prefixIcon: Icon(Icons.tag),
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Rejoin my favorite rooms'),
              subtitle: const Text('Star rooms in a chat or the room browser'),
              value: _rejoinFavorites,
              onChanged: (v) => setState(() => _rejoinFavorites = v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Log in with a registered account'),
              value: _useAccount,
              onChanged: (v) => setState(() => _useAccount = v),
            ),
            if (_useAccount) ...[
              TextField(
                controller: _account,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Account name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember password'),
                subtitle: const Text('Kept in the device keychain'),
                value: _rememberPassword,
                onChanged: (v) => setState(() => _rememberPassword = v),
              ),
            ],
            const SizedBox(height: 24),
            Text('Networks', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final network in builtInNetworks)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(network.name),
                  subtitle: Text(network.description),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _connect(network),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
