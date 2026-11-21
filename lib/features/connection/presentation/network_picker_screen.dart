import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/connection/data/saved_connection.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:material_ui/material_ui.dart';

/// First screen: pick a nickname and one or more networks, then connect.
///
/// Remembers the nickname, open networks and account, and offers a one-tap
/// "Continue" card that reconnects every network that was open. Opened
/// again from the chat screen, it adds another network; networks that are
/// already connected stay connected.
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
  final _username = TextEditingController();
  final _realname = TextEditingController();
  bool _useAccount = false;
  bool _rememberPassword = true;
  bool _rejoinFavorites = true;
  late bool _saveHistory = ref
      .read(chatControllerProvider.notifier)
      .saveHistory;
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
    _username.text = saved.username ?? '';
    _realname.text = saved.realname ?? '';
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
    _username.dispose();
    _realname.dispose();
    super.dispose();
  }

  static IrcNetwork? _networkFor(String host) {
    for (final n in builtInNetworks) {
      if (n.host.toLowerCase() == host.toLowerCase()) return n;
    }
    return null;
  }

  /// Networks that were open last time and aren't open now.
  List<IrcNetwork> _lastNetworks(ChatState chat) => [
    for (final host in _saved?.openNetworks ?? const <String>[])
      if (_networkFor(host) case final n?)
        if (!chat.networks.containsKey(n.host.toLowerCase())) n,
  ];

  Future<void> _confirmDeleteHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete saved history?'),
        content: const Text(
          'This deletes the saved messages of every room and private chat '
          'on this device. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(chatControllerProvider.notifier).clearAllHistory();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved history deleted.')));
    }
  }

  bool _checkNick() {
    if (isValidNick(_nick.text.trim())) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Pick a nickname: letters, numbers and _-[]{}|^ only, '
          'starting with a letter.',
        ),
      ),
    );
    return false;
  }

  /// Connects to [networks], keeping any network that is already open.
  ///
  /// Rooms typed in the form only apply when connecting to one network.
  /// The account login is used for the one network picked, or for any
  /// network that has a saved password for that account.
  Future<void> _connect(List<IrcNetwork> networks) async {
    if (networks.isEmpty || !_checkNick()) return;
    final nick = _nick.text.trim();
    final single = networks.length == 1;
    final typed = single
        ? _channels.text
              .split(RegExp(r'[\s,]+'))
              .where((c) => c.isNotEmpty)
              .map((c) => c.startsWith('#') ? c : '#$c')
              .toList()
        : const <String>[];
    final repo = ref.read(savedConnectionRepositoryProvider);
    final chat = ref.read(chatControllerProvider);
    final account = _useAccount ? _account.text.trim() : '';

    // Every network open after this, so the next launch can reopen them.
    final open = <String>[
      for (final n in chat.networks.values) n.config.host,
      for (final n in networks)
        if (!chat.networks.containsKey(n.host.toLowerCase())) n.host,
    ];
    unawaited(
      repo.save(
        SavedConnection(
          nick: nick,
          networkHost: networks.first.host,
          account: account.isEmpty ? null : account,
          rememberPassword: _rememberPassword,
          rejoinFavorites: _rejoinFavorites,
          username: _username.text.trim().isEmpty ? null : _username.text,
          realname: _realname.text.trim().isEmpty ? null : _realname.text,
          networkHosts: open,
        ),
        password: single ? _password.text : null,
      ),
    );

    final controller = ref.read(chatControllerProvider.notifier);
    for (final network in networks) {
      final id = network.host.toLowerCase();
      final existing = chat.networks[id];
      if (existing != null &&
          existing.status != IrcConnectionStatus.disconnected) {
        // Already open: just switch to it.
        controller.selectBuffer(ChatState.bufferKey(id, statusBuffer));
        continue;
      }
      final favorites = _rejoinFavorites
          ? ref.read(roomPrefsProvider).favoritesFor(network.host)
          : const <String>[];
      final autoJoin = <String>[];
      for (final room in [...favorites, ...typed]) {
        if (!autoJoin.any((r) => r.toLowerCase() == room.toLowerCase())) {
          autoJoin.add(room);
        }
      }
      var password = '';
      if (account.isNotEmpty) {
        password = single && _password.text.isNotEmpty
            ? _password.text
            : await repo.loadPassword(network.host, account) ?? '';
      }
      final useSasl = account.isNotEmpty && (single || password.isNotEmpty);
      final config = IrcConnectionConfig(
        host: network.host,
        port: network.port,
        useTls: network.useTls,
        nick: nick,
        autoJoin: autoJoin,
        username: _username.text,
        realname: _realname.text,
        sasl: useSasl
            ? SaslCredentials(account: account, password: password)
            : null,
      );
      unawaited(controller.connect(config));
    }
    if (mounted) context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prefs = ref.watch(roomPrefsProvider);
    final chat = ref.watch(chatControllerProvider);
    final adding = chat.networks.isNotEmpty;
    final last = _lastNetworks(chat);
    final lastFavorites = [for (final n in last) ...prefs.favoritesFor(n.host)];
    final notOpen = [
      for (final n in builtInNetworks)
        if (!chat.networks.containsKey(n.host.toLowerCase())) n,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: adding
            ? IconButton(
                tooltip: 'Back to chat',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/chat'),
              )
            : null,
        title: Text(adding ? 'Add a network' : 'Choose a network'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (last.isNotEmpty && _saved!.nick.isNotEmpty) ...[
              Card(
                color: theme.colorScheme.primaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.bolt),
                  title: Text(
                    'Continue on ${last.map((n) => n.name).join(' and ')}',
                  ),
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
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('More options'),
              subtitle: const Text('Username, real name and chat history'),
              children: [
                TextField(
                  controller: _username,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Username (optional)',
                    hintText: IrcClient.defaultUsername,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _realname,
                  decoration: const InputDecoration(
                    labelText: 'Real name (optional, shown to others)',
                    hintText: IrcClient.defaultRealname,
                    border: OutlineInputBorder(),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Save chat history on this device'),
                  subtitle: const Text(
                    'Rooms and private chats keep their messages after you '
                    'disconnect or close the app',
                  ),
                  value: _saveHistory,
                  onChanged: (v) {
                    setState(() => _saveHistory = v);
                    unawaited(
                      ref
                          .read(chatControllerProvider.notifier)
                          .setSaveHistory(enabled: v),
                    );
                  },
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete saved history'),
                    onPressed: _confirmDeleteHistory,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Networks', style: theme.textTheme.titleMedium),
                ),
                if (notOpen.length > 1)
                  TextButton.icon(
                    icon: const Icon(Icons.hub_outlined),
                    label: const Text('Connect to all'),
                    onPressed: () => _connect(notOpen),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (final network in builtInNetworks)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.public),
                  title: Text(network.name),
                  subtitle: Text(network.description),
                  trailing: switch (chat.networks[network.host.toLowerCase()]) {
                    null => const Icon(Icons.chevron_right),
                    final n => Chip(
                      label: Text(
                        n.status == IrcConnectionStatus.disconnected
                            ? 'Disconnected'
                            : 'Connected',
                      ),
                    ),
                  },
                  onTap: () => _connect([network]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
