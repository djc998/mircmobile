import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:material_ui/material_ui.dart';

/// The main chat view: conversation list, messages, input and nick list.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final buffer = state.activeBuffer;
    final isChannel = buffer?.isChannel ?? false;
    final channel = isChannel ? controller.client?.channel(buffer!.name) : null;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final prefs = ref.watch(roomPrefsProvider);
    final host = controller.host;
    final favorites = host == null
        ? const <String>[]
        : prefs.favoritesFor(host);
    final isFavorite =
        channel != null && host != null && prefs.isFavorite(host, channel.name);

    final list = _BufferList(
      state: state,
      favorites: {for (final f in favorites) f.toLowerCase()},
      onSelect: controller.selectBuffer,
    );

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              buffer == null || buffer.isStatus ? state.network : buffer.name,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              channel != null && channel.topic.isNotEmpty
                  ? channel.topic
                  : _statusLabel(state),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Browse rooms',
            icon: const Icon(Icons.travel_explore),
            onPressed: () => context.go('/chat/rooms'),
          ),
          IconButton(
            tooltip: 'New private message',
            icon: const Icon(Icons.mail_outline),
            onPressed: () => _promptPrivateMessage(context, controller),
          ),
          IconButton(
            tooltip: 'Join a room',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _promptJoin(context, controller),
          ),
          if (channel != null && host != null)
            IconButton(
              tooltip: isFavorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              icon: Icon(isFavorite ? Icons.star : Icons.star_border),
              onPressed: () => ref
                  .read(roomPrefsProvider.notifier)
                  .toggleFavorite(host, channel.name),
            ),
          if (channel != null)
            Builder(
              builder: (context) => IconButton(
                tooltip: 'People',
                icon: const Icon(Icons.people_outline),
                onPressed: () => Scaffold.of(context).openEndDrawer(),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'close':
                  controller.closeBuffer(buffer!.name);
                case 'disconnect':
                  await controller.disconnect();
                  if (context.mounted) context.go('/');
              }
            },
            itemBuilder: (_) => [
              if (buffer != null && !buffer.isStatus)
                PopupMenuItem(
                  value: 'close',
                  child: Text(isChannel ? 'Leave room' : 'Close chat'),
                ),
              const PopupMenuItem(
                value: 'disconnect',
                child: Text('Disconnect'),
              ),
            ],
          ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: list)),
      endDrawer: channel == null
          ? null
          : Drawer(
              child: SafeArea(
                child: _NickList(
                  channel: channel,
                  onNickTap: (nick) => unawaited(
                    showUserActions(context, controller, state.nick, nick),
                  ),
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 260, child: list),
            if (wide) const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  if (state.hasConnectionProblem)
                    _ConnectionProblemBanner(
                      state: state,
                      controller: controller,
                    ),
                  Expanded(
                    child: _MessageList(
                      lines: buffer?.lines ?? [],
                      onNickTap: (nick) => unawaited(
                        showUserActions(context, controller, state.nick, nick),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _InputBar(onSubmit: controller.submit),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _statusLabel(ChatState s) => switch (s.status) {
    IrcConnectionStatus.connected => 'Connected as ${s.nick}',
    IrcConnectionStatus.connecting => 'Connecting…',
    IrcConnectionStatus.registering => 'Logging in…',
    IrcConnectionStatus.reconnecting => 'Reconnecting…',
    IrcConnectionStatus.disconnected => 'Disconnected',
  };

  Future<void> _promptPrivateMessage(
    BuildContext context,
    ChatController controller,
  ) async {
    final nick = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(
        title: 'New private message',
        hint: 'Nickname',
        action: 'Open chat',
      ),
    );
    if (nick != null && nick.trim().isNotEmpty) {
      controller.openPrivateChat(nick.trim());
    }
  }

  Future<void> _promptJoin(
    BuildContext context,
    ChatController controller,
  ) async {
    final room = await showDialog<String>(
      context: context,
      builder: (_) => const _TextPromptDialog(
        title: 'Join a room',
        hint: '#channel',
        action: 'Join',
      ),
    );
    if (room != null && room.trim().isNotEmpty) {
      controller.submit('/join ${room.trim()}');
    }
  }
}

class _BufferList extends StatelessWidget {
  const _BufferList({
    required this.state,
    required this.favorites,
    required this.onSelect,
  });

  final ChatState state;

  /// Lower-cased names of favorite rooms, shown with a star.
  final Set<String> favorites;
  final void Function(String name) onSelect;

  @override
  Widget build(BuildContext context) {
    final buffers = state.buffers.values.toList();
    return ListView(
      children: [
        for (final b in buffers)
          ListTile(
            dense: true,
            selected: b.name.toLowerCase() == state.active.toLowerCase(),
            leading: Icon(
              b.isStatus
                  ? Icons.dns_outlined
                  : favorites.contains(b.name.toLowerCase())
                  ? Icons.star
                  : b.isChannel
                  ? Icons.tag
                  : Icons.person_outline,
            ),
            title: Text(b.isStatus ? state.network : b.name),
            trailing: b.unread == 0
                ? null
                : Badge(
                    label: Text('${b.unread}'),
                    backgroundColor: b.mentioned
                        ? Theme.of(context).colorScheme.error
                        : Theme.of(context).colorScheme.primary,
                  ),
            onTap: () {
              onSelect(b.name);
              if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                Navigator.pop(context);
              }
            },
          ),
      ],
    );
  }
}

/// Actions for another user: private message, whois, copy nick.
Future<void> showUserActions(
  BuildContext context,
  ChatController controller,
  String ownNick,
  String nick,
) async {
  final isMe = nick.toLowerCase() == ownNick.toLowerCase();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(nick, style: Theme.of(sheet).textTheme.titleMedium),
          ),
          if (!isMe)
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Send private message'),
              onTap: () {
                Navigator.pop(sheet);
                controller.openPrivateChat(nick);
              },
            ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Who is this? (whois)'),
            onTap: () {
              Navigator.pop(sheet);
              controller.whoisUser(nick);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy nickname'),
            onTap: () {
              Navigator.pop(sheet);
              _copyNick(nick);
            },
          ),
        ],
      ),
    ),
  );
}

void _copyNick(String text) {
  // Clipboard errors are harmless here; nothing to report.
  Clipboard.setData(ClipboardData(text: text)).ignore();
}

class _MessageList extends StatelessWidget {
  const _MessageList({required this.lines, required this.onNickTap});

  final List<ChatLine> lines;
  final void Function(String nick) onNickTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[lines.length - 1 - i];
        return _MessageTile(line: line, onNickTap: onNickTap);
      },
    );
  }
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({required this.line, required this.onNickTap});

  final ChatLine line;
  final void Function(String nick) onNickTap;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  // Owned here so it can be disposed with the row.
  late final TapGestureRecognizer _nickTap = TapGestureRecognizer()
    ..onTap = () {
      final sender = widget.line.sender;
      if (sender != null) widget.onNickTap(sender);
    };

  @override
  void dispose() {
    _nickTap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = widget.line;
    final time = TimeOfDay.fromDateTime(line.time.toLocal()).format(context);
    final sender = line.sender;
    final nickStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: sender == null
          ? null
          : AppTheme.nickColor(sender, theme.brightness),
    );
    final InlineSpan body = switch (line.kind) {
      ChatLineKind.message || ChatLineKind.own => TextSpan(
        children: [
          TextSpan(text: '<$sender> ', style: nickStyle, recognizer: _nickTap),
          TextSpan(text: line.text),
        ],
      ),
      ChatLineKind.action => TextSpan(
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          color: Color(0xFF9C009C),
        ),
        children: [
          const TextSpan(text: '* '),
          TextSpan(text: sender, recognizer: _nickTap),
          TextSpan(text: ' ${line.text}'),
        ],
      ),
      ChatLineKind.notice => TextSpan(
        style: const TextStyle(color: Color(0xFF7F0000)),
        children: [
          if (sender != null)
            TextSpan(text: '-$sender- ', recognizer: _nickTap),
          TextSpan(text: line.text),
        ],
      ),
      ChatLineKind.event => TextSpan(
        text: '• ${line.text}',
        style: const TextStyle(color: Color(0xFF009300)),
      ),
      ChatLineKind.error => TextSpan(
        text: '⚠ ${line.text}',
        style: TextStyle(color: theme.colorScheme.error),
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText.rich(
        TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$time  ',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            body,
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({required this.onSubmit});

  final void Function(String text) onSubmit;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              minLines: 1,
              maxLines: 5,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: const InputDecoration(
                hintText: 'Message or /command',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _send,
            icon: const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

class _NickList extends StatelessWidget {
  const _NickList({required this.channel, required this.onNickTap});

  final IrcChannel channel;
  final void Function(String nick) onNickTap;

  @override
  Widget build(BuildContext context) {
    final members = channel.members.values.toList()
      ..sort((a, b) {
        final rank = _rank(a).compareTo(_rank(b));
        return rank != 0
            ? rank
            : a.nick.toLowerCase().compareTo(b.nick.toLowerCase());
      });
    final brightness = Theme.of(context).brightness;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${members.length} people in ${channel.name}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: members.length,
            itemBuilder: (context, i) {
              final m = members[i];
              return ListTile(
                dense: true,
                onTap: () {
                  Scaffold.of(context).closeEndDrawer();
                  onNickTap(m.nick);
                },
                trailing: const Icon(Icons.more_horiz, size: 18),
                title: Text(
                  '${m.topPrefix}${m.nick}',
                  style: TextStyle(
                    color: AppTheme.nickColor(m.nick, brightness),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static int _rank(IrcMember m) =>
      m.prefixes.isEmpty ? 99 : '~&@%+'.indexOf(m.topPrefix).abs();
}

/// Asks what to do when a secure connection can't be made: trust an
/// unverified certificate, or fall back to an unencrypted connection.
class _ConnectionProblemBanner extends StatelessWidget {
  const _ConnectionProblemBanner({
    required this.state,
    required this.controller,
  });

  final ChatState state;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final cert = state.untrustedCertificate;
    final String message;
    final List<Widget> actions;
    if (cert != null) {
      message =
          "This server's security certificate can't be verified "
          '(${cert.isExpired
              ? 'expired'
              : cert.isSelfSigned
              ? 'self-signed'
              : 'not issued for this server'}). '
          'This is common on older networks like EFnet. If you trust it, '
          'the chat is still encrypted and the app remembers this exact '
          'certificate.\n'
          'Issued to: ${cert.subject}\nFingerprint: ${cert.sha256}';
      actions = [
        TextButton(
          onPressed: controller.dismissConnectionProblem,
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: controller.trustCertificateAndReconnect,
          child: const Text('Trust and connect'),
        ),
      ];
    } else {
      message =
          "Couldn't open a secure connection to this network. You can "
          'try an unencrypted connection instead. Others on the network '
          'path could read your messages and password.';
      actions = [
        TextButton(
          onPressed: controller.dismissConnectionProblem,
          child: const Text('Keep trying'),
        ),
        TextButton(
          onPressed: controller.connectWithoutEncryption,
          child: const Text('Connect without encryption'),
        ),
      ];
    }
    return MaterialBanner(
      leading: const Icon(Icons.gpp_maybe_outlined),
      content: Text(message),
      actions: actions,
    );
  }
}

/// A one-field dialog that owns (and disposes) its text controller, so the
/// controller outlives the dialog's closing animation.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.hint,
    required this.action,
  });

  final String title;
  final String hint;
  final String action;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
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
      content: TextField(
        controller: _text,
        autofocus: true,
        autocorrect: false,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(widget.action),
        ),
      ],
    );
  }
}
