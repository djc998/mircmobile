import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
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

    final list = _BufferList(state: state, onSelect: controller.selectBuffer);

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
            tooltip: 'Join a room',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: () => _promptJoin(context, controller),
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
              child: SafeArea(child: _NickList(channel: channel)),
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) SizedBox(width: 260, child: list),
            if (wide) const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  Expanded(child: _MessageList(lines: buffer?.lines ?? [])),
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

  Future<void> _promptJoin(
    BuildContext context,
    ChatController controller,
  ) async {
    final text = TextEditingController();
    final room = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a room'),
        content: TextField(
          controller: text,
          autofocus: true,
          autocorrect: false,
          decoration: const InputDecoration(hintText: '#channel'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    text.dispose();
    if (room != null && room.trim().isNotEmpty) {
      controller.submit('/join ${room.trim()}');
    }
  }
}

class _BufferList extends StatelessWidget {
  const _BufferList({required this.state, required this.onSelect});

  final ChatState state;
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

class _MessageList extends StatelessWidget {
  const _MessageList({required this.lines});

  final List<ChatLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[lines.length - 1 - i];
        final time = TimeOfDay.fromDateTime(line.time.toLocal())
            .format(context);
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
              TextSpan(text: '<$sender> ', style: nickStyle),
              TextSpan(text: line.text),
            ],
          ),
          ChatLineKind.action => TextSpan(
            text: '* $sender ${line.text}',
            style: const TextStyle(
              fontStyle: FontStyle.italic,
              color: Color(0xFF9C009C),
            ),
          ),
          ChatLineKind.notice => TextSpan(
            text: sender == null ? line.text : '-$sender- ${line.text}',
            style: const TextStyle(color: Color(0xFF7F0000)),
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
      },
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
  const _NickList({required this.channel});

  final IrcChannel channel;

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
