import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/cap_negotiator.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:material_ui/material_ui.dart';

/// First screen: pick a nickname and a network, then connect.
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

  @override
  void dispose() {
    _nick.dispose();
    _channels.dispose();
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  void _connect(IrcNetwork network) {
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
    final channels = _channels.text
        .split(RegExp(r'[\s,]+'))
        .where((c) => c.isNotEmpty)
        .map((c) => c.startsWith('#') ? c : '#$c')
        .toList();
    final config = IrcConnectionConfig(
      host: network.host,
      port: network.port,
      useTls: network.useTls,
      nick: nick,
      autoJoin: channels,
      sasl: _useAccount && _account.text.isNotEmpty
          ? SaslCredentials(account: _account.text, password: _password.text)
          : null,
    );
    unawaited(ref.read(chatControllerProvider.notifier).connect(config));
    context.go('/chat');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a network')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
