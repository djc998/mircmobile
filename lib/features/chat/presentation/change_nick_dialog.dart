import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a new nickname and changes it on [networkId] (or the open
/// network), optionally on every open network.
Future<void> showChangeNickDialog(
  BuildContext context,
  WidgetRef ref, {
  String? networkId,
}) async {
  final state = ref.read(chatControllerProvider);
  final net = networkId == null
      ? state.activeNetwork
      : state.networks[networkId];
  if (net == null) return;
  await showDialog<void>(
    context: context,
    builder: (_) => _ChangeNickDialog(
      network: net,
      showEverywhere: state.networks.length > 1,
      onChange: (nick, {required everywhere}) => ref
          .read(chatControllerProvider.notifier)
          .changeNick(nick, networkId: net.id, everywhere: everywhere),
    ),
  );
}

class _ChangeNickDialog extends StatefulWidget {
  const _ChangeNickDialog({
    required this.network,
    required this.showEverywhere,
    required this.onChange,
  });

  final NetworkSession network;
  final bool showEverywhere;
  final String? Function(String nick, {required bool everywhere}) onChange;

  @override
  State<_ChangeNickDialog> createState() => _ChangeNickDialogState();
}

class _ChangeNickDialogState extends State<_ChangeNickDialog> {
  late final _nick = TextEditingController(text: widget.network.nick)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.network.nick.length,
    );
  bool _everywhere = false;
  String? _error;

  @override
  void dispose() {
    _nick.dispose();
    super.dispose();
  }

  void _save() {
    final error = widget.onChange(_nick.text, everywhere: _everywhere);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change nickname'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nick,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'New nickname',
              helperText: widget.showEverywhere && !_everywhere
                  ? 'On ${widget.network.label}'
                  : null,
              errorText: _error,
              errorMaxLines: 3,
            ),
            onSubmitted: (_) => _save(),
          ),
          if (widget.showEverywhere)
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Change it on all my networks'),
              value: _everywhere,
              onChanged: (v) => setState(() => _everywhere = v),
            ),
          const SizedBox(height: 8),
          Text(
            "If the name is taken, you'll keep your current one and see a "
            'message in the chat. The new name is also used next time you '
            'connect.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Change')),
      ],
    );
  }
}
