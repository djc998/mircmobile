/// Screens for creating and running your own rooms without commands.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/rooms/domain/room_modes.dart';
import 'package:material_ui/material_ui.dart';

/// Asks for a room name and privacy settings, then creates the room on the
/// chosen network. Returns whether a room was created.
Future<bool> showCreateRoomDialog(BuildContext context, WidgetRef ref) async {
  final state = ref.read(chatControllerProvider);
  final networks = state.connectedNetworks;
  if (networks.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Connect to a network first.')),
    );
    return false;
  }
  final result = await showDialog<_CreateRoomResult>(
    context: context,
    builder: (_) => _CreateRoomDialog(
      networks: networks,
      initial: state.activeNetwork?.isConnected ?? false
          ? state.activeNetwork!
          : networks.first,
    ),
  );
  if (result == null) return false;
  ref
      .read(chatControllerProvider.notifier)
      .createRoom(result.name, result.settings, networkId: result.networkId);
  return true;
}

class _CreateRoomResult {
  const _CreateRoomResult(this.networkId, this.name, this.settings);

  final String networkId;
  final String name;
  final RoomSettings settings;
}

class _CreateRoomDialog extends StatefulWidget {
  const _CreateRoomDialog({required this.networks, required this.initial});

  final List<NetworkSession> networks;
  final NetworkSession initial;

  @override
  State<_CreateRoomDialog> createState() => _CreateRoomDialogState();
}

class _CreateRoomDialogState extends State<_CreateRoomDialog> {
  final _name = TextEditingController();
  final _password = TextEditingController();
  late String _networkId = widget.initial.id;
  bool _inviteOnly = true;
  bool _hidden = true;
  bool _usePassword = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    super.dispose();
  }

  void _create() {
    var name = _name.text.trim();
    if (name.startsWith('#')) name = name.substring(1);
    if (name.isEmpty || name.contains(RegExp(r'[\s,\x07]'))) {
      setState(() => _error = 'Use a name without spaces or commas.');
      return;
    }
    if (_usePassword && _password.text.trim().isEmpty) {
      setState(() => _error = 'Type a password, or turn Password off.');
      return;
    }
    Navigator.pop(
      context,
      _CreateRoomResult(
        _networkId,
        '#$name',
        RoomSettings(
          inviteOnly: _inviteOnly,
          secret: _hidden,
          topicLocked: true,
          password: _usePassword ? _password.text.trim() : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a room'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.networks.length > 1) ...[
            DropdownButtonFormField<String>(
              initialValue: _networkId,
              decoration: const InputDecoration(labelText: 'Network'),
              items: [
                for (final n in widget.networks)
                  DropdownMenuItem(value: n.id, child: Text(n.label)),
              ],
              onChanged: (v) => setState(() => _networkId = v ?? _networkId),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _name,
            autofocus: true,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Room name',
              prefixText: '#',
              errorText: _error,
            ),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Private'),
            subtitle: const Text('Only people you invite can join'),
            value: _inviteOnly,
            onChanged: (v) => setState(() => _inviteOnly = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hidden'),
            subtitle: const Text("Doesn't appear in the room list"),
            value: _hidden,
            onChanged: (v) => setState(() => _hidden = v),
          ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Password'),
            subtitle: const Text('People need the password to join'),
            value: _usePassword,
            onChanged: (v) => setState(() => _usePassword = v),
          ),
          if (_usePassword)
            TextField(
              controller: _password,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Room password'),
            ),
          const SizedBox(height: 8),
          Text(
            'You will run the room: you can change these settings, invite '
            'people and remove them. To keep the room when everyone has '
            'left, use "Keep this room" in Room settings.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}

/// Opens the settings of [channel] on [networkId].
Future<void> showRoomSettings(
  BuildContext context, {
  required String networkId,
  required String channel,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.9,
    child: RoomSettingsSheet(networkId: networkId, channel: channel),
  ),
);

/// Switches for a room's privacy, inviting people and keeping the room.
class RoomSettingsSheet extends ConsumerStatefulWidget {
  const RoomSettingsSheet({
    required this.networkId,
    required this.channel,
    this.embedded = false,
    super.key,
  });

  final String networkId;
  final String channel;

  /// Inside Room info's list: no title or scrolling of its own.
  final bool embedded;

  @override
  ConsumerState<RoomSettingsSheet> createState() => _RoomSettingsSheetState();
}

class _RoomSettingsSheetState extends ConsumerState<RoomSettingsSheet> {
  final _password = TextEditingController();
  final _invite = TextEditingController();
  final _limit = TextEditingController();
  TextEditingController? _description;
  bool _bansRequested = false;

  @override
  void dispose() {
    _password.dispose();
    _invite.dispose();
    _limit.dispose();
    _description?.dispose();
    super.dispose();
  }

  void _toast(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  void _update(RoomSettings settings) => ref
      .read(chatControllerProvider.notifier)
      .updateRoom(widget.channel, settings, networkId: widget.networkId);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final net = state.networks[widget.networkId];
    final chan = net?.client.channel(widget.channel);
    final theme = Theme.of(context);
    if (net == null || chan == null) {
      return const Center(child: Text("You're not in this room any more."));
    }
    final isOp = net.client.isOperator(chan.name);
    final services = net.services;
    final description = _description ??= TextEditingController(
      text: chan.topic,
    );
    final canDescribe = isOp || !chan.isTopicLocked;
    if (isOp && !_bansRequested) {
      _bansRequested = true;
      controller.requestBans(chan.name, networkId: net.id);
    }

    final children = <Widget>[
      Text(
        widget.embedded ? 'Room settings' : '${chan.name} settings',
        style: widget.embedded
            ? theme.textTheme.titleMedium
            : theme.textTheme.titleLarge,
      ),
      const SizedBox(height: 4),
      Text(
        isOp
            ? 'You run this room on ${net.label}.'
            : 'Only the people who run this room (operators, shown with '
                  '@) can change its settings.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 16),
      Text('Description', style: theme.textTheme.titleMedium),
      Text(
        canDescribe
            ? 'Shown at the top of the room and in the room list.'
            : 'Only operators can change the description here.',
      ),
      TextField(
        controller: description,
        enabled: canDescribe,
        minLines: 1,
        maxLines: 3,
        maxLength: 300,
        decoration: const InputDecoration(hintText: 'What is this room about?'),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.tonal(
          onPressed: canDescribe
              ? () {
                  controller.setRoomDescription(
                    chan.name,
                    description.text,
                    networkId: net.id,
                  );
                  _toast('Description updated.');
                }
              : null,
          child: const Text('Save description'),
        ),
      ),
      const Divider(height: 32),
      Text('Who can join', style: theme.textTheme.titleMedium),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Private'),
        subtitle: const Text('Only people you invite can join'),
        value: chan.isInviteOnly,
        onChanged: isOp ? (v) => _update(RoomSettings(inviteOnly: v)) : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Hidden'),
        subtitle: const Text("Doesn't appear in the room list"),
        value: chan.isSecret,
        onChanged: isOp ? (v) => _update(RoomSettings(secret: v)) : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Lock the topic'),
        subtitle: const Text('Only operators can change the topic'),
        value: chan.isTopicLocked,
        onChanged: isOp ? (v) => _update(RoomSettings(topicLocked: v)) : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('Moderated'),
        subtitle: const Text(
          'Only operators and people you give a voice can talk',
        ),
        value: chan.isModerated,
        onChanged: isOp ? (v) => _update(RoomSettings(moderated: v)) : null,
      ),
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: const Text('No messages from outside'),
        subtitle: const Text(
          "People who aren't in the room can't send messages to it",
        ),
        value: chan.modes.contains('n'),
        onChanged: isOp
            ? (v) => _update(RoomSettings(noOutsideMessages: v))
            : null,
      ),
      const SizedBox(height: 8),
      Text('Room size', style: theme.textTheme.titleMedium),
      Text(
        chan.limit == null
            ? 'Any number of people can be in the room.'
            : 'At most ${chan.limit} people can be in the room.',
      ),
      if (isOp)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _limit,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: 'Most people'),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                final n = int.tryParse(_limit.text.trim());
                if (n == null || n <= 0) return;
                _update(RoomSettings(limit: n));
                _limit.clear();
              },
              child: const Text('Set'),
            ),
            if (chan.limit != null) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _update(const RoomSettings(limit: 0)),
                child: const Text('No limit'),
              ),
            ],
          ],
        ),
      const SizedBox(height: 8),
      Text('Password', style: theme.textTheme.titleMedium),
      Text(
        chan.hasKey
            ? 'People need a password to join.'
            : 'Anyone allowed in can join without a password.',
      ),
      if (isOp)
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _password,
                autocorrect: false,
                decoration: InputDecoration(
                  hintText: chan.hasKey ? 'New password' : 'Password',
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: () {
                if (_password.text.trim().isEmpty) return;
                _update(RoomSettings(password: _password.text));
                _password.clear();
              },
              child: const Text('Set'),
            ),
            if (chan.hasKey) ...[
              const SizedBox(width: 8),
              TextButton(
                onPressed: () => _update(const RoomSettings(password: '')),
                child: const Text('Remove'),
              ),
            ],
          ],
        ),
      const Divider(height: 32),
      Text('Invite someone', style: theme.textTheme.titleMedium),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _invite,
              autocorrect: false,
              decoration: const InputDecoration(hintText: 'Nickname'),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () {
              final nick = _invite.text.trim();
              if (nick.isEmpty) return;
              controller.inviteUser(nick, chan.name, networkId: net.id);
              _invite.clear();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Invited $nick to ${chan.name}.')),
              );
            },
            child: const Text('Invite'),
          ),
        ],
      ),
      if (isOp) ...[
        const Divider(height: 32),
        Text('Banned', style: theme.textTheme.titleMedium),
        const Text(
          "People matching these can't join. Ban someone from the "
          'people list.',
        ),
        if (!chan.bansLoaded)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Loading…'),
          )
        else if (chan.bans.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Nobody is banned.'),
          )
        else
          for (final mask in chan.bans)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.block),
              title: Text(mask),
              trailing: TextButton(
                onPressed: () {
                  controller.unban(chan.name, mask, networkId: net.id);
                  _toast('Unbanned $mask.');
                },
                child: const Text('Unban'),
              ),
            ),
      ],
      const Divider(height: 32),
      Text('Keep this room', style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      if (services.roomLimitation case final why?)
        Text(why)
      else ...[
        const Text(
          'An empty room disappears, and the next person to join it runs '
          'it. Registering the room keeps it, and you always get to run '
          'it. This takes a registered nickname on this network.',
        ),
        const SizedBox(height: 8),
        if (!net.loggedIn)
          OutlinedButton.icon(
            icon: const Icon(Icons.badge_outlined),
            label: Text('Register my nickname (${net.nick})'),
            onPressed: () => unawaited(
              showRegisterNickDialog(context, ref, networkId: net.id),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.icon(
          icon: const Icon(Icons.verified_outlined),
          label: const Text('Keep this room'),
          onPressed: isOp
              ? () => unawaited(_keepRoom(context, net, chan))
              : null,
        ),
        if (!isOp)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Only an operator of the room can register it.'),
          ),
      ],
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: children,
    );
  }

  Future<void> _keepRoom(
    BuildContext context,
    NetworkSession net,
    IrcChannel chan,
  ) async {
    String? password;
    if (net.services.roomNeedsPassword) {
      password = await showDialog<String>(
        context: context,
        builder: (_) => const _SecretPromptDialog(
          title: 'Room password for ChanServ',
          message:
              'This network asks for a separate password that lets you '
              'manage the room registration. Keep it somewhere safe.',
          label: 'Registration password',
        ),
      );
      if (password == null || password.isEmpty) return;
    }
    ref
        .read(chatControllerProvider.notifier)
        .registerRoom(chan.name, password: password, networkId: net.id);
    // Closes the sheet, or Room info, to show the ChanServ chat.
    if (context.mounted) Navigator.pop(context);
  }
}

/// Registers the current nickname with NickServ, or logs in to it.
Future<void> showRegisterNickDialog(
  BuildContext context,
  WidgetRef ref, {
  required String networkId,
}) async {
  final net = ref.read(chatControllerProvider).networks[networkId];
  if (net == null) return;
  final result = await showDialog<({String password, String? email})>(
    context: context,
    builder: (_) => _RegisterNickDialog(nick: net.nick),
  );
  if (result == null) return;
  final controller = ref.read(chatControllerProvider.notifier);
  final email = result.email;
  if (email == null) {
    controller.identifyNick(result.password, networkId: networkId);
  } else {
    await controller.registerNick(result.password, email, networkId: networkId);
  }
  // Close the settings sheet so the NickServ chat with its reply shows.
  if (context.mounted) Navigator.pop(context);
}

class _RegisterNickDialog extends StatefulWidget {
  const _RegisterNickDialog({required this.nick});

  final String nick;

  @override
  State<_RegisterNickDialog> createState() => _RegisterNickDialogState();
}

class _RegisterNickDialogState extends State<_RegisterNickDialog> {
  final _password = TextEditingController();
  final _email = TextEditingController();
  bool _existing = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _email.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _password.text;
    final email = _email.text.trim();
    if (password.length < 6 || password.contains(' ')) {
      setState(() => _error = 'Use at least 6 characters and no spaces.');
      return;
    }
    if (!_existing && !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      setState(() => _error = 'Type a valid email address.');
      return;
    }
    Navigator.pop(context, (
      password: password,
      email: _existing ? null : email,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _existing ? 'Log in as ${widget.nick}' : 'Register ${widget.nick}',
      ),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _existing
                ? 'Type the password of your registered nickname.'
                : 'Registering reserves this nickname for you on this '
                      'network. Most networks email you a code or link to '
                      'confirm. The app remembers the password in the '
                      'device keychain and logs you in automatically.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
            ),
          ),
          if (!_existing)
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                _existing = !_existing;
                _error = null;
              }),
              child: Text(
                _existing
                    ? 'Register a new nickname instead'
                    : 'I already registered this nickname',
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_existing ? 'Log in' : 'Register'),
        ),
      ],
    );
  }
}

class _SecretPromptDialog extends StatefulWidget {
  const _SecretPromptDialog({
    required this.title,
    required this.message,
    required this.label,
  });

  final String title;
  final String message;
  final String label;

  @override
  State<_SecretPromptDialog> createState() => _SecretPromptDialogState();
}

class _SecretPromptDialogState extends State<_SecretPromptDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.message),
          TextField(
            controller: _text,
            obscureText: true,
            decoration: InputDecoration(labelText: widget.label),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text.trim()),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
