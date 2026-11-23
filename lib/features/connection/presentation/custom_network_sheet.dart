/// The form to add a network of your own, or edit or remove one.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/irc/networks.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/connection/data/custom_networks.dart';
import 'package:material_ui/material_ui.dart';

/// What the user did in the sheet.
enum CustomNetworkAction { connect, saved, removed }

/// Opens the form. With [editing], it edits that network and offers
/// Remove. Saves (or removes) before returning; returns the network and
/// what to do next, or null when cancelled.
Future<({CustomNetwork network, CustomNetworkAction action})?>
showCustomNetworkSheet(BuildContext context, {CustomNetwork? editing}) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CustomNetworkForm(editing: editing),
    );

class _CustomNetworkForm extends ConsumerStatefulWidget {
  const _CustomNetworkForm({this.editing});

  final CustomNetwork? editing;

  @override
  ConsumerState<_CustomNetworkForm> createState() => _CustomNetworkFormState();
}

class _CustomNetworkFormState extends ConsumerState<_CustomNetworkForm> {
  late final _server = TextEditingController(text: widget.editing?.host);
  late final _port = TextEditingController(
    text: '${widget.editing?.port ?? 6697}',
  );
  late final _name = TextEditingController(text: widget.editing?.name);
  final _password = TextEditingController();
  late bool _tls = widget.editing?.useTls ?? true;
  String? _serverError;
  String? _portError;

  @override
  void initState() {
    super.initState();
    final host = widget.editing?.host;
    if (host != null) {
      unawaited(
        ref.read(customNetworksProvider.notifier).password(host).then((pw) {
          if (mounted && pw != null && _password.text.isEmpty) {
            _password.text = pw;
          }
        }),
      );
    }
  }

  @override
  void dispose() {
    _server.dispose();
    _port.dispose();
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Switching encryption moves the port between the usual two, unless a
  /// different port was typed.
  void _setTls(bool v) => setState(() {
    if (_port.text.trim() == '${defaultPort(useTls: _tls)}') {
      _port.text = '${defaultPort(useTls: v)}';
    }
    _tls = v;
  });

  /// `host:port` typed into the server field fills in the port.
  void _serverChanged(String text) {
    final parsed = parseServer(text);
    if (_serverError != null) setState(() => _serverError = null);
    if (parsed == null || parsed.port == null || !text.contains(':')) return;
    setState(() {
      _port.text = '${parsed.port}';
      if (parsed.tls != null) _tls = parsed.tls!;
    });
  }

  Future<void> _save({required bool connect}) async {
    final parsed = parseServer(_server.text);
    final port = int.tryParse(_port.text.trim()) ?? parsed?.port;
    setState(() {
      _serverError = parsed == null
          ? 'Enter a server address, such as irc.example.net'
          : null;
      _portError = port == null || port < 1 || port > 65535
          ? 'A port from 1 to 65535'
          : null;
    });
    if (parsed == null || _portError != null) return;
    final controller = ref.read(customNetworksProvider.notifier);
    final editing = widget.editing;
    final clash = builtInNetworks.any(
      (n) => n.host.toLowerCase() == parsed.host.toLowerCase(),
    );
    if (clash) {
      setState(
        () => _serverError = 'That network is already in the list above',
      );
      return;
    }
    final network = CustomNetwork(
      host: parsed.host,
      name: _name.text.trim(),
      port: port!,
      useTls: _tls,
    );
    await controller.save(
      network,
      previousHost: editing?.host,
      password: _password.text,
    );
    if (!mounted) return;
    Navigator.pop(context, (
      network: network,
      action: connect ? CustomNetworkAction.connect : CustomNetworkAction.saved,
    ));
  }

  Future<void> _remove() async {
    final editing = widget.editing!;
    await ref.read(customNetworksProvider.notifier).remove(editing.host);
    if (!mounted) return;
    Navigator.pop(context, (
      network: editing,
      action: CustomNetworkAction.removed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final editing = widget.editing != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    editing ? 'Edit network' : 'Add your own network',
                    style: TypeScale.title.copyWith(color: tokens.textPrimary),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Any IRC server or bouncer. The network or its website '
                  'lists the address and port.',
                  style: TypeScale.body.copyWith(color: tokens.textMuted),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _server,
                  autofocus: !editing,
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                  onChanged: _serverChanged,
                  decoration: InputDecoration(
                    labelText: 'Server address',
                    hintText: 'irc.example.net',
                    errorText: _serverError,
                    prefixIcon: const Icon(Icons.dns_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _port,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_portError != null) setState(() => _portError = null);
                  },
                  decoration: InputDecoration(
                    labelText: 'Port',
                    errorText: _portError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Secure connection (TLS)'),
                  subtitle: Text(
                    _tls
                        ? 'Usually port 6697'
                        : 'Usually port 6667. Messages and passwords are '
                              'sent unencrypted.',
                  ),
                  value: _tls,
                  onChanged: _setTls,
                ),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Shown in the network list',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server password (optional)',
                    helperText:
                        'Only if the server or bouncer asks for one. Kept '
                        'in the device keychain.',
                    helperMaxLines: 2,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                OverflowBar(
                  alignment: MainAxisAlignment.end,
                  overflowAlignment: OverflowBarAlignment.end,
                  spacing: 8,
                  overflowSpacing: 8,
                  children: [
                    if (editing)
                      TextButton.icon(
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Remove'),
                        onPressed: _remove,
                      ),
                    if (editing)
                      OutlinedButton(
                        onPressed: () => _save(connect: false),
                        child: const Text('Save'),
                      )
                    else
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    FilledButton(
                      onPressed: () => _save(connect: true),
                      child: Text(editing ? 'Save and connect' : 'Connect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
