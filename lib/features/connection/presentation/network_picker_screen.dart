import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/adaptive.dart';
import 'package:irc_client/features/calls/application/call_controller.dart';
import 'package:irc_client/features/calls/presentation/call_widgets.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/connection/data/custom_networks.dart';
import 'package:irc_client/features/connection/data/saved_connection.dart';
import 'package:irc_client/features/connection/presentation/custom_network_sheet.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Welcome: three steps (pick a nickname, choose a network, then find a
/// first room in Discover), with everything else behind Advanced options.
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

  /// Every network in the list: the built-in ones, then the user's own.
  List<IrcNetwork> get _allNetworks => [
    ...builtInNetworks,
    for (final n in ref.read(customNetworksProvider)) n.network,
  ];

  IrcNetwork? _networkFor(String host) {
    for (final n in _allNetworks) {
      if (n.host.toLowerCase() == host.toLowerCase()) return n;
    }
    return null;
  }

  Future<void> _addOrEdit([CustomNetwork? editing]) async {
    final result = await showCustomNetworkSheet(context, editing: editing);
    if (!mounted || result == null) return;
    if (result.action == CustomNetworkAction.connect) {
      await _connect([result.network.network]);
    }
  }

  /// Networks that were open last time and aren't open now.
  List<IrcNetwork> _lastNetworks(ChatState chat) => [
    for (final host in _saved?.openNetworks ?? const <String>[])
      if (_networkFor(host) case final n?)
        if (!chat.networks.containsKey(n.host.toLowerCase())) n,
  ];

  Future<void> _confirmDeleteHistory() async {
    final ok = await confirmAction(
      context,
      title: 'Delete saved history?',
      message:
          'This deletes the saved messages of every room and private chat '
          'on this device. It cannot be undone.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok) return;
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
      final serverPassword = await ref
          .read(customNetworksProvider.notifier)
          .password(network.host);
      final config = IrcConnectionConfig(
        host: network.host,
        port: network.port,
        useTls: network.useTls,
        nick: nick,
        autoJoin: autoJoin,
        username: _username.text,
        realname: _realname.text,
        serverPassword: serverPassword,
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
    final tokens = AppTokens.of(context);
    final prefs = ref.watch(roomPrefsProvider);
    final chat = ref.watch(chatControllerProvider);
    final adding = chat.networks.isNotEmpty;
    final last = _lastNetworks(chat);
    final lastFavorites = [for (final n in last) ...prefs.favoritesFor(n.host)];
    final custom = ref.watch(customNetworksProvider);
    final notOpen = [
      for (final n in [...builtInNetworks, for (final c in custom) c.network])
        if (!chat.networks.containsKey(n.host.toLowerCase())) n,
    ];
    final muted = TypeScale.body.copyWith(color: tokens.textMuted);

    return Scaffold(
      appBar: AppBar(
        leading: adding
            ? IconButton(
                tooltip: 'Back to chat',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.go('/chat'),
              )
            : null,
        title: adding ? const Text('Add a network') : null,
        actions: [
          IconButton(
            tooltip: 'Appearance',
            icon: const Icon(Icons.palette_outlined),
            onPressed: () => context.push('/appearance'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            // A short page: built all at once so nothing below the fold
            // is missing for screen readers or tests.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!adding) ...[const _Hero(), const SizedBox(height: 24)],
                  if (last.isNotEmpty && _saved!.nick.isNotEmpty) ...[
                    Card(
                      color: Color.alphaBlend(
                        tokens.accentSoft,
                        tokens.surface,
                      ),
                      elevation: 0,
                      child: ListTile(
                        leading: Icon(Icons.bolt, color: tokens.onAccentSoft),
                        title: Text(
                          'Continue on '
                          '${last.map((n) => n.name).join(' and ')}',
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
                  _Step(
                    number: 1,
                    title: adding ? 'Your nickname' : 'Pick a nickname',
                    child: TextField(
                      controller: _nick,
                      autocorrect: false,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Nickname',
                        helperText:
                            'Letters, numbers and _-[]{}|^, starting with a '
                            'letter',
                        helperMaxLines: 2,
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  _Step(
                    number: 2,
                    title: 'Choose a network',
                    trailing: notOpen.length > 1
                        ? TextButton.icon(
                            icon: const Icon(Icons.hub_outlined),
                            label: const Text('Connect to all'),
                            onPressed: () => _connect(notOpen),
                          )
                        : null,
                    child: Column(
                      children: [
                        for (final network in builtInNetworks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _NetworkCard(
                              network: network,
                              session:
                                  chat.networks[network.host.toLowerCase()],
                              onTap: () => _connect([network]),
                            ),
                          ),
                        for (final c in custom)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _NetworkCard(
                              network: c.network,
                              custom: true,
                              session: chat.networks[c.host.toLowerCase()],
                              onTap: () => _connect([c.network]),
                              onEdit: () => _addOrEdit(c),
                            ),
                          ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            icon: const Icon(Icons.add),
                            label: const Text('Add your own network'),
                            onPressed: _addOrEdit,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!adding)
                    _Step(
                      number: 3,
                      title: 'Find your first room',
                      last: true,
                      child: Text(
                        "Once you're connected, Discover lists every room "
                        'on the network, by size and topic. Join one with a '
                        'tap, and star it to rejoin it next time.',
                        style: muted,
                      ),
                    ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: _useAccount,
                    title: const Text('Advanced options'),
                    subtitle: const Text(
                      'Rooms to join, account login, username, chat history '
                      'and calls',
                    ),
                    childrenPadding: const EdgeInsets.only(bottom: 12),
                    children: _advanced(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Everything behind Advanced options.
  List<Widget> _advanced() => [
    const SizedBox(height: 4),
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
      subtitle: const Text('Star rooms in a chat or in Discover'),
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
    const SizedBox(height: 8),
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
          ref.read(chatControllerProvider.notifier).setSaveHistory(enabled: v),
        );
      },
    ),
    const ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('Camera and microphone'),
      subtitle: Text('Allow them for voice and video calls'),
    ),
    const DeviceAccessHelp(),
    Consumer(
      builder: (context, ref, _) => SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Hide my IP address on calls'),
        subtitle: const Text(
          'Calls go through a relay, so the other person never '
          'sees your IP address',
        ),
        value: ref.watch(callControllerProvider).relayOnly,
        onChanged: (v) => unawaited(
          ref.read(callControllerProvider.notifier).setRelayOnly(enabled: v),
        ),
      ),
    ),
    Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.delete_outline),
        label: const Text('Delete saved history'),
        onPressed: _confirmDeleteHistory,
      ),
    ),
  ];
}

/// The app's name, mark and line at the top of the welcome screen.
class _Hero extends StatelessWidget {
  const _Hero();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.accent,
              borderRadius: BorderRadius.circular(tokens.radius(16)),
            ),
            child: Text(
              '#',
              style: TextStyle(
                color: tokens.onAccent,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(
            'Welcome to IRCage',
            style: const TextStyle(
              fontSize: 30,
              height: 36 / 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ).copyWith(color: tokens.textPrimary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Chat rooms, the way they used to be. Only better.',
          style: TypeScale.heading.copyWith(
            color: tokens.textMuted,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

/// A numbered step: a circle with the number, a title, and its content,
/// joined to the next step by a line.
class _Step extends StatelessWidget {
  const _Step({
    required this.number,
    required this.title,
    required this.child,
    this.trailing,
    this.last = false,
  });

  final int number;
  final String title;
  final Widget child;
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final badge = Semantics(
      label: 'Step $number',
      excludeSemantics: true,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: tokens.accent, shape: BoxShape.circle),
        child: Text(
          '$number',
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            color: tokens.onAccent,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
    return Stack(
      children: [
        // The line down to the next step.
        if (!last)
          Positioned(
            left: 13,
            top: 32,
            bottom: 4,
            child: Container(width: 2, color: tokens.line),
          ),
        Positioned(left: 0, top: 0, child: badge),
        Padding(
          padding: const EdgeInsets.only(left: 42, bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 28),
                // The button drops under the title when both don't fit
                // (large text).
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        style: TypeScale.heading.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
              ),
              const SizedBox(height: 10),
              child,
            ],
          ),
        ),
      ],
    );
  }
}

/// A network to connect to: initial tile, name, description, and either a
/// chevron or its status when it's already open.
class _NetworkCard extends StatelessWidget {
  const _NetworkCard({
    required this.network,
    required this.session,
    required this.onTap,
    this.onEdit,
    this.custom = false,
  });

  final IrcNetwork network;
  final NetworkSession? session;
  final VoidCallback onTap;

  /// Shows an Edit button (networks the user added).
  final VoidCallback? onEdit;
  final bool custom;

  static String _status(NetworkSession n) =>
      n.status == IrcConnectionStatus.disconnected
      ? 'Disconnected'
      : 'Connected';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final open = session;
    return Material(
      color: tokens.surfaceRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: tokens.line),
        borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Color.alphaBlend(tokens.accentSoft, tokens.surfaceRaised),
            borderRadius: BorderRadius.circular(tokens.radius(10)),
          ),
          child: Icon(
            custom ? Icons.dns_outlined : Icons.public,
            color: tokens.onAccentSoft,
          ),
        ),
        title: Text(
          network.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        // With an Edit button, the status goes in the subtitle so the name
        // keeps its room.
        subtitle: Text(
          onEdit != null && open != null
              ? '${_status(open)} · ${network.description}'
              : network.description,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onEdit != null)
              IconButton(
                tooltip: 'Edit ${network.name}',
                icon: const Icon(Icons.edit_outlined),
                onPressed: onEdit,
              ),
            switch (open) {
              null => const Icon(Icons.chevron_right),
              _ when onEdit != null => const SizedBox.shrink(),
              final n => Chip(label: Text(_status(n))),
            },
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}
