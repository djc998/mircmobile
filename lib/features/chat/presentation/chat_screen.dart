import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:irc_client/features/calls/presentation/call_widgets.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/panel_prefs.dart';
import 'package:irc_client/features/chat/presentation/change_nick_dialog.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:irc_client/features/pictures/presentation/picture_widgets.dart';
import 'package:irc_client/features/rooms/presentation/room_dialogs.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

/// The main chat view: conversation list, messages, input and nick list.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final buffer = state.activeBuffer;
    final net = state.activeNetwork;
    final isChannel = buffer?.isChannel ?? false;
    final channel = isChannel ? net?.client.channel(buffer!.name) : null;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= pinnedPanelsMinWidth;
    // Phone-sized: only the buttons for this chat stay in the title bar.
    final compact = width < compactTitleBarMaxWidth;
    final panels = ref.watch(panelPrefsProvider);
    // Comfortable shows avatars in the chat and people lists.
    final comfortable =
        ref.watch(appearanceProvider).density == ChatDensity.comfortable;
    final panelsCtl = ref.read(panelPrefsProvider.notifier);
    // On wide screens each side panel can be pinned open or hidden.
    final showChats = wide && panels.chatsPinned;
    final showPeople = wide && panels.peoplePinned && channel != null;
    final prefs = ref.watch(roomPrefsProvider);
    final host = net?.id;
    final isFavorite =
        channel != null && host != null && prefs.isFavorite(host, channel.name);

    final list = _BufferList(
      state: state,
      prefs: prefs,
      controller: controller,
      onChangeNick: (id) => showChangeNickDialog(context, ref, networkId: id),
      comfortable: comfortable,
      // On phones the drawer carries the actions that aren't about the open
      // chat; wider screens keep them in the top bar and ⋮ menu.
      actions: compact
          ? _ListActions(
              browse: () => context.go('/chat/rooms'),
              message: () => _promptPrivateMessage(context, controller),
              join: () => _promptJoin(context, controller),
              createRoom: () => showCreateRoomDialog(context, ref),
              appearance: () => context.push('/appearance'),
              closeNetwork: (id) => _closeNetwork(context, ref, id),
            )
          : null,
    );

    final people = channel == null
        ? null
        : _NickList(
            channel: channel,
            comfortable: comfortable,
            onNickTap: (nick) => unawaited(
              showUserActions(
                context,
                controller,
                net!.nick,
                nick,
                network: net,
                room: channel.name,
                onReply: () =>
                    controller.startReply(_lastLineFrom(buffer!, nick)),
              ),
            ),
          );

    return Scaffold(
      appBar: AppBar(
        leading: wide
            ? IconButton(
                tooltip: panels.chatsPinned
                    ? 'Hide servers and chats'
                    : 'Show servers and chats',
                icon: Icon(panels.chatsPinned ? Icons.menu_open : Icons.menu),
                onPressed: () => unawaited(panelsCtl.toggleChats()),
              )
            : null,
        // Tap the name for this chat's info and actions.
        title: Builder(
          builder: (titleContext) => Tooltip(
            message: 'Chat info',
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: net == null
                  ? null
                  : () => unawaited(
                      _showChatInfo(titleContext, ref, phone: compact),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      buffer == null || buffer.isStatus
                          ? net?.label ?? ''
                          : buffer.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      channel != null && channel.topic.isNotEmpty
                          ? channel.topic
                          : net == null
                          ? 'Not connected'
                          : state.networks.length > 1 &&
                                !(buffer?.isStatus ?? true)
                          ? '${net.label} · ${_statusLabel(net)}'
                          : _statusLabel(net),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          // On phones these are in the drawer and the chat info sheet, so
          // the room or person's name has room to show.
          if (!compact) ...[
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
          ],
          // Calls are for private chats.
          if (buffer != null && !buffer.isStatus && !isChannel)
            ...callButtons(context, ref),
          if (channel != null && host != null && !compact)
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
              builder: (context) => wide
                  ? IconButton(
                      tooltip: panels.peoplePinned
                          ? 'Hide people'
                          : 'Show people',
                      isSelected: panels.peoplePinned,
                      icon: const Icon(Icons.people_outline),
                      selectedIcon: const Icon(Icons.people),
                      onPressed: () => unawaited(panelsCtl.togglePeople()),
                    )
                  : IconButton(
                      tooltip: 'People',
                      icon: const Icon(Icons.people_outline),
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
            ),
          if (compact) const SizedBox(width: 4),
          if (!compact)
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'close':
                    controller.closeBuffer(buffer!.key);
                  case 'clear':
                    await controller.clearHistory(buffer!.key);
                  case 'add':
                    context.go('/');
                  case 'nick':
                    await showChangeNickDialog(context, ref);
                  case 'appearance':
                    await context.push('/appearance');
                  case 'create':
                    await showCreateRoomDialog(context, ref);
                  case 'settings':
                    await showRoomSettings(
                      context,
                      networkId: net!.id,
                      channel: channel!.name,
                    );
                  case 'disconnect':
                    await controller.disconnect();
                  case 'reconnect':
                    await controller.reconnect();
                  case 'remove':
                    await _closeNetwork(context, ref, net!.id);
                }
              },
              itemBuilder: (_) => [
                if (channel != null)
                  const PopupMenuItem(
                    value: 'settings',
                    child: Text('Room settings'),
                  ),
                const PopupMenuItem(
                  value: 'create',
                  child: Text('Create a room'),
                ),
                if (buffer != null && !buffer.isStatus)
                  PopupMenuItem(
                    value: 'close',
                    child: Text(isChannel ? 'Leave room' : 'Close chat'),
                  ),
                if (buffer != null && !buffer.isStatus)
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Clear history'),
                  ),
                const PopupMenuItem(value: 'add', child: Text('Add a network')),
                if (net != null)
                  PopupMenuItem(
                    value: 'nick',
                    child: Text('Change nickname (${net.nick})'),
                  ),
                const PopupMenuItem(
                  value: 'appearance',
                  child: Text('Appearance'),
                ),
                if (net != null &&
                    net.status == IrcConnectionStatus.disconnected)
                  PopupMenuItem(
                    value: 'reconnect',
                    child: Text('Reconnect to ${net.label}'),
                  )
                else if (net != null)
                  PopupMenuItem(
                    value: 'disconnect',
                    child: Text('Disconnect from ${net.label}'),
                  ),
                if (net != null)
                  PopupMenuItem(
                    value: 'remove',
                    child: Text('Close ${net.label}'),
                  ),
              ],
            ),
        ],
      ),
      drawer: wide ? null : Drawer(child: SafeArea(child: list)),
      endDrawer: people == null || wide
          ? null
          : Drawer(child: SafeArea(child: people)),
      body: SafeArea(
        child: Row(
          children: [
            if (showChats) SizedBox(width: 260, child: list),
            if (showChats) const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                children: [
                  if (net != null && net.hasConnectionProblem)
                    _ConnectionProblemBanner(
                      network: net,
                      controller: controller,
                    ),
                  for (final n in state.networks.values)
                    for (final invite in n.invites.take(1))
                      MaterialBanner(
                        leading: const Icon(Icons.mail_lock_outlined),
                        content: Text(
                          '${invite.from} invited you to ${invite.channel}'
                          '${state.networks.length > 1 ? ' on ${n.label}' : ''}'
                          '.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                controller.dismissInvite(n.id, invite),
                            child: const Text('Ignore'),
                          ),
                          FilledButton(
                            onPressed: () =>
                                controller.acceptInvite(n.id, invite),
                            child: const Text('Join'),
                          ),
                        ],
                      ),
                  Expanded(
                    child: _MessageList(
                      lines: buffer?.lines ?? [],
                      ownNick: net?.nick ?? '',
                      networkId: net?.id ?? '',
                      // Pictures load on their own only in a private chat
                      // where you've written to the other person.
                      autoShowPictures:
                          buffer != null &&
                          !buffer.isStatus &&
                          !isChannel &&
                          buffer.lines.any((l) => l.kind == ChatLineKind.own),
                      onReply: isChannel ? controller.startReply : null,
                      onNickTap: (nick) => unawaited(
                        showUserActions(
                          context,
                          controller,
                          net?.nick ?? '',
                          nick,
                          network: net,
                          room: channel?.name,
                          onReply: isChannel
                              ? () => controller.startReply(
                                  _lastLineFrom(buffer!, nick),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _InputBar(
                    // A new bar per conversation keeps drafts apart.
                    key: ValueKey(buffer?.key),
                    onSubmit: controller.submit,
                    replyTo: buffer?.replyTo,
                    onCancelReply: controller.cancelReply,
                    uploading: (buffer?.uploading ?? 0) > 0,
                    // Pictures are for private chats.
                    onAttach: buffer != null && !buffer.isStatus && !isChannel
                        ? () => unawaited(sendPicture(context, ref))
                        : null,
                    nicks: [
                      if (channel != null)
                        for (final m in channel.members.values)
                          if (m.nick != net?.nick)
                            m.nick
                          else if (buffer != null && !buffer.isStatus)
                            buffer.name,
                    ],
                  ),
                ],
              ),
            ),
            if (showPeople) const VerticalDivider(width: 1),
            if (showPeople) SizedBox(width: 220, child: people),
          ],
        ),
      ),
    );
  }

  /// The latest message from [nick] here, to reply to; a bare line naming
  /// them when they haven't spoken.
  static ChatLine _lastLineFrom(ChatBuffer buffer, String nick) {
    for (final line in buffer.lines.reversed) {
      if (line.sender?.toLowerCase() == nick.toLowerCase() &&
          line.kind != ChatLineKind.own) {
        return line;
      }
    }
    return ChatLine(text: '', sender: nick, kind: ChatLineKind.message);
  }

  static String _statusLabel(NetworkSession s) => switch (s.status) {
    IrcConnectionStatus.connected => 'Connected as ${s.nick}',
    IrcConnectionStatus.connecting => 'Connecting…',
    IrcConnectionStatus.registering => 'Logging in…',
    IrcConnectionStatus.reconnecting => 'Reconnecting…',
    IrcConnectionStatus.disconnected => 'Disconnected',
  };

  Future<void> _closeNetwork(
    BuildContext context,
    WidgetRef ref,
    String networkId,
  ) async {
    await ref.read(chatControllerProvider.notifier).removeNetwork(networkId);
    if (context.mounted && ref.read(chatControllerProvider).networks.isEmpty) {
      context.go('/');
    }
  }

  /// The sheet that opens from the chat's name: details and everything you
  /// can do with this room, private chat or server. [context] must be under
  /// the [Scaffold] (it opens the people drawer).
  Future<void> _showChatInfo(
    BuildContext context,
    WidgetRef ref, {
    required bool phone,
  }) {
    final state = ref.read(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final net = state.activeNetwork;
    final buffer = state.activeBuffer;
    if (net == null) return Future.value();
    final isStatus = buffer == null || buffer.isStatus;
    final channel = !isStatus && buffer.isChannel
        ? net.client.channel(buffer.name)
        : null;
    final isFavorite =
        channel != null &&
        ref.read(roomPrefsProvider).isFavorite(net.id, channel.name);

    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        // Close the sheet, then act.
        Widget item(
          IconData icon,
          String label,
          FutureOr<void> Function() run,
        ) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () {
            Navigator.pop(sheet);
            unawaited(Future.sync(run));
          },
        );
        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        isStatus ? net.label : buffer.name,
                        style: theme.textTheme.titleLarge,
                      ),
                      if (channel != null && channel.topic.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        SelectableText(
                          channel.topic,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        isStatus
                            ? _statusLabel(net)
                            : '${net.label} · ${_statusLabel(net)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                if (channel != null) ...[
                  item(
                    isFavorite ? Icons.star : Icons.star_border,
                    isFavorite ? 'Remove from favorites' : 'Add to favorites',
                    () => ref
                        .read(roomPrefsProvider.notifier)
                        .toggleFavorite(net.id, channel.name),
                  ),
                  if (phone)
                    item(
                      Icons.people_outline,
                      'People (${channel.members.length})',
                      () => Scaffold.of(context).openEndDrawer(),
                    ),
                  item(
                    Icons.tune,
                    'Room settings',
                    () => showRoomSettings(
                      context,
                      networkId: net.id,
                      channel: channel.name,
                    ),
                  ),
                ] else if (!isStatus)
                  item(
                    Icons.info_outline,
                    'Who is this? (whois)',
                    () => controller.whoisUser(buffer.name),
                  ),
                if (!isStatus) ...[
                  item(
                    Icons.delete_sweep_outlined,
                    'Clear history',
                    () => controller.clearHistory(buffer.key),
                  ),
                  item(
                    Icons.logout,
                    channel != null ? 'Leave room' : 'Close chat',
                    () => controller.closeBuffer(buffer.key),
                  ),
                ] else ...[
                  item(
                    Icons.edit,
                    'Change nickname (${net.nick})',
                    () => showChangeNickDialog(context, ref, networkId: net.id),
                  ),
                  if (net.status == IrcConnectionStatus.disconnected)
                    item(
                      Icons.refresh,
                      'Reconnect to ${net.label}',
                      () => controller.reconnect(net.id),
                    )
                  else
                    item(
                      Icons.link_off,
                      'Disconnect from ${net.label}',
                      () => controller.disconnect(net.id),
                    ),
                  item(
                    Icons.close,
                    'Close ${net.label}',
                    () => _closeNetwork(context, ref, net.id),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

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

/// Actions the phone drawer offers that aren't about the open chat.
class _ListActions {
  const _ListActions({
    required this.browse,
    required this.message,
    required this.join,
    required this.createRoom,
    required this.appearance,
    required this.closeNetwork,
  });

  final void Function() browse;
  final Future<void> Function() message;
  final Future<void> Function() join;
  final Future<void> Function() createRoom;
  final Future<void> Function() appearance;
  final Future<void> Function(String networkId) closeNetwork;
}

/// Conversations grouped by network. Favorite rooms that aren't open are
/// listed under their network so they can be joined with one tap.
class _BufferList extends StatelessWidget {
  const _BufferList({
    required this.state,
    required this.prefs,
    required this.controller,
    required this.onChangeNick,
    this.comfortable = false,
    this.actions,
  });

  final ChatState state;
  final RoomPrefs prefs;
  final ChatController controller;
  final Future<void> Function(String networkId) onChangeNick;

  /// Avatars instead of icons (Comfortable density).
  final bool comfortable;

  /// Shown on phones: Browse / Message / Join at the top, a menu on each
  /// network, and Create a room and Appearance at the bottom.
  final _ListActions? actions;

  void _closeDrawer(BuildContext context) {
    if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = this.actions;
    // Close the drawer first; the action's dialogs and pages belong to the
    // chat screen.
    void run(FutureOr<void> Function() action) {
      _closeDrawer(context);
      unawaited(Future.sync(action));
    }

    Widget topButton(
      IconData icon,
      String label,
      String tooltip,
      void Function() onTap,
    ) => Expanded(
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon),
                const SizedBox(height: 4),
                Text(label, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
        ),
      ),
    );

    return ListView(
      children: [
        if (actions != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                topButton(
                  Icons.travel_explore,
                  'Browse',
                  'Browse rooms',
                  () => run(actions.browse),
                ),
                topButton(
                  Icons.mail_outline,
                  'Message',
                  'New private message',
                  () => run(actions.message),
                ),
                topButton(
                  Icons.add_comment_outlined,
                  'Join',
                  'Join a room',
                  () => run(actions.join),
                ),
              ],
            ),
          ),
          const Divider(),
        ],
        for (final net in state.networks.values) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: switch (net.status) {
                    IrcConnectionStatus.connected => Colors.green,
                    IrcConnectionStatus.disconnected =>
                      theme.colorScheme.outline,
                    _ => Colors.orange,
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    net.label,
                    style: theme.textTheme.labelLarge,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Your nickname here; tap to change it.
                ActionChip(
                  avatar: const Icon(Icons.edit, size: 16),
                  label: Text(net.nick),
                  tooltip: 'Change nickname on ${net.label}',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    _closeDrawer(context);
                    unawaited(onChangeNick(net.id));
                  },
                ),
                if (actions != null)
                  PopupMenuButton<String>(
                    tooltip: 'Options for ${net.label}',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) => run(switch (v) {
                      'reconnect' => () => controller.reconnect(net.id),
                      'disconnect' => () => controller.disconnect(net.id),
                      _ => () => actions.closeNetwork(net.id),
                    }),
                    itemBuilder: (_) => [
                      if (net.status == IrcConnectionStatus.disconnected)
                        PopupMenuItem(
                          value: 'reconnect',
                          child: Text('Reconnect to ${net.label}'),
                        )
                      else
                        PopupMenuItem(
                          value: 'disconnect',
                          child: Text('Disconnect from ${net.label}'),
                        ),
                      PopupMenuItem(
                        value: 'close',
                        child: Text('Close ${net.label}'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          for (final b in state.buffersFor(net.id))
            ListTile(
              dense: true,
              selected: b.key == state.activeKey,
              leading: comfortable && !b.isStatus
                  ? (b.isChannel
                        ? RoomAvatar(name: b.name, size: 32)
                        : NickAvatar(nick: b.name, size: 28))
                  : Icon(
                      b.isStatus
                          ? Icons.dns_outlined
                          : prefs.isFavorite(net.id, b.name)
                          ? Icons.star
                          : b.isChannel
                          ? Icons.tag
                          : Icons.person_outline,
                    ),
              title: Text(b.isStatus ? 'Server messages' : b.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (comfortable &&
                      !b.isStatus &&
                      prefs.isFavorite(net.id, b.name))
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        Icons.star,
                        size: 16,
                        semanticLabel: 'Favorite',
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  UnreadBadge(count: b.unread, mention: b.mentioned),
                ],
              ),
              onTap: () {
                controller.selectBuffer(b.key);
                _closeDrawer(context);
              },
            ),
          for (final room in prefs.favoritesFor(net.id))
            if (!state.buffers.containsKey(ChatState.bufferKey(net.id, room)))
              ListTile(
                dense: true,
                leading: Icon(Icons.star_border, color: theme.disabledColor),
                title: Text(room, style: TextStyle(color: theme.hintColor)),
                trailing: Text('Join', style: theme.textTheme.labelSmall),
                enabled: net.isConnected,
                onTap: () {
                  controller.joinRoom(room, networkId: net.id);
                  _closeDrawer(context);
                },
              ),
          const Divider(),
        ],
        if (actions != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.add_box_outlined),
            title: const Text('Create a room'),
            onTap: () => run(actions.createRoom),
          ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.add),
          title: const Text('Add a network'),
          onTap: () {
            _closeDrawer(context);
            context.go('/');
          },
        ),
        if (actions != null)
          ListTile(
            dense: true,
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Appearance'),
            onTap: () => run(actions.appearance),
          ),
      ],
    );
  }
}

/// Actions for another user: private message, whois, copy nick, invite,
/// and (for the room's operators) make operator, remove and ban.
Future<void> showUserActions(
  BuildContext context,
  ChatController controller,
  String ownNick,
  String nick, {
  NetworkSession? network,
  String? room,
  VoidCallback? onReply,
}) async {
  final isMe = nick.toLowerCase() == ownNick.toLowerCase();
  final client = network?.client;
  final inRoom =
      room != null &&
      (client?.channel(room)?.members.containsKey(nick.toLowerCase()) ?? false);
  final canModerate =
      !isMe && room != null && inRoom && (client?.isOperator(room) ?? false);
  final member = room == null
      ? null
      : client?.channel(room)?.members[nick.toLowerCase()];
  final theyAreOp = member?.prefixes.contains(RegExp('[~&@]')) ?? false;
  final theyHaveVoice = member?.prefixes.contains('+') ?? false;
  // Rooms we're in that this person isn't in, for "Invite to".
  final inviteTo = isMe || client == null
      ? const <String>[]
      : [
          for (final c in client.channels.values)
            if (!c.members.containsKey(nick.toLowerCase())) c.name,
        ];
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(nick, style: Theme.of(sheet).textTheme.titleMedium),
            ),
            if (!isMe && onReply != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text('Reply to $nick here'),
                onTap: () {
                  Navigator.pop(sheet);
                  onReply();
                },
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
            if (!isMe)
              ListTile(
                leading: Icon(
                  controller.isBlocked(nick) ? Icons.undo : Icons.block,
                ),
                title: Text(
                  controller.isBlocked(nick) ? 'Unblock $nick' : 'Block $nick',
                ),
                subtitle: controller.isBlocked(nick)
                    ? null
                    : const Text('Hide their messages and pictures'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (controller.isBlocked(nick)) {
                    controller.unblockUser(nick);
                  } else {
                    controller.blockUser(nick);
                  }
                },
              ),
            for (final c in inviteTo)
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: Text('Invite to $c'),
                onTap: () {
                  Navigator.pop(sheet);
                  controller.inviteUser(nick, c, networkId: network!.id);
                },
              ),
            if (canModerate) ...[
              const Divider(),
              if (theyAreOp)
                ListTile(
                  leading: const Icon(Icons.remove_moderator_outlined),
                  title: Text('Remove operator of $room'),
                  onTap: () {
                    Navigator.pop(sheet);
                    controller.removeOperator(
                      room,
                      nick,
                      networkId: network!.id,
                    );
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: Text('Make operator of $room'),
                  onTap: () {
                    Navigator.pop(sheet);
                    controller.makeOperator(room, nick, networkId: network!.id);
                  },
                ),
              ListTile(
                leading: Icon(
                  theyHaveVoice
                      ? Icons.voice_over_off_outlined
                      : Icons.record_voice_over_outlined,
                ),
                title: Text(theyHaveVoice ? 'Take voice' : 'Give voice'),
                subtitle: const Text(
                  'In a moderated room, only people with a voice can talk',
                ),
                onTap: () {
                  Navigator.pop(sheet);
                  controller.setVoice(
                    room,
                    nick,
                    voice: !theyHaveVoice,
                    networkId: network!.id,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: Text('Remove from $room'),
                onTap: () {
                  Navigator.pop(sheet);
                  controller.kickUser(room, nick, networkId: network!.id);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.block,
                  color: Theme.of(sheet).colorScheme.error,
                ),
                title: Text('Ban from $room'),
                onTap: () {
                  Navigator.pop(sheet);
                  controller.banUser(room, nick, networkId: network!.id);
                },
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

void _copyNick(String text) {
  // Clipboard errors are harmless here; nothing to report.
  Clipboard.setData(ClipboardData(text: text)).ignore();
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.lines,
    required this.ownNick,
    required this.onNickTap,
    this.networkId = '',
    this.autoShowPictures = false,
    this.onReply,
  });

  final List<ChatLine> lines;
  final String ownNick;
  final String networkId;
  final bool autoShowPictures;
  final void Function(String nick) onNickTap;

  /// Null where replies don't apply (server tab, private chats).
  final void Function(ChatLine line)? onReply;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final line = lines[lines.length - 1 - i];
        final canReply =
            onReply != null &&
            line.sender != null &&
            line.kind != ChatLineKind.own &&
            line.kind != ChatLineKind.event &&
            line.kind != ChatLineKind.error;
        final tile = _MessageTile(
          key: ObjectKey(line),
          line: line,
          ownNick: ownNick,
          onNickTap: onNickTap,
          onReply: canReply ? () => onReply!(line) : null,
        );
        final isOwn = line.kind == ChatLineKind.own;
        final link =
            line.sender != null && (isOwn || line.kind == ChatLineKind.message)
            ? PictureLink.find(line.text)
            : null;
        if (link == null) return tile;
        return Column(
          key: ValueKey(link),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tile,
            PictureBubble(
              link: link,
              sender: line.sender!,
              networkId: networkId,
              isOwn: isOwn,
              autoShow: isOwn || autoShowPictures,
            ),
          ],
        );
      },
    );
  }
}

class _MessageTile extends StatefulWidget {
  const _MessageTile({
    required this.line,
    required this.ownNick,
    required this.onNickTap,
    this.onReply,
    super.key,
  });

  final ChatLine line;
  final String ownNick;
  final void Function(String nick) onNickTap;
  final VoidCallback? onReply;

  @override
  State<_MessageTile> createState() => _MessageTileState();
}

class _MessageTileState extends State<_MessageTile> {
  bool _hovered = false;

  Future<void> _showLineActions(BuildContext context) {
    final line = widget.line;
    final onReply = widget.onReply;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply),
                title: Text('Reply to ${line.sender}'),
                onTap: () {
                  Navigator.pop(sheet);
                  onReply();
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy message'),
              onTap: () {
                Navigator.pop(sheet);
                _copyNick(line.text);
              },
            ),
          ],
        ),
      ),
    );
  }

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
    final chatColors = ChatColors.of(context);
    final nickStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: sender == null ? null : chatColors.nickColor(sender),
    );
    final InlineSpan body = switch (line.kind) {
      ChatLineKind.message || ChatLineKind.own => TextSpan(
        children: [
          TextSpan(text: '<$sender> ', style: nickStyle, recognizer: _nickTap),
          TextSpan(text: line.text),
        ],
      ),
      ChatLineKind.action => TextSpan(
        style: TextStyle(fontStyle: FontStyle.italic, color: chatColors.action),
        children: [
          const TextSpan(text: '* '),
          TextSpan(text: sender, recognizer: _nickTap),
          TextSpan(text: ' ${line.text}'),
        ],
      ),
      ChatLineKind.notice => TextSpan(
        style: TextStyle(color: chatColors.notice),
        children: [
          if (sender != null)
            TextSpan(text: '-$sender- ', recognizer: _nickTap),
          TextSpan(text: line.text),
        ],
      ),
      ChatLineKind.event => TextSpan(
        text: '• ${line.text}',
        style: TextStyle(color: chatColors.event),
      ),
      ChatLineKind.error => TextSpan(
        text: '⚠ ${line.text}',
        style: TextStyle(color: theme.colorScheme.error),
      ),
    };
    final mentioned =
        line.kind != ChatLineKind.own &&
        line.sender != null &&
        mentions(line.text, widget.ownNick);
    final span = TextSpan(
      style: theme.textTheme.bodyMedium,
      children: [
        TextSpan(
          text: '$time  ',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        body,
      ],
    );
    // Phones: plain text so a swipe can reply; long-press offers Reply and
    // Copy. Computers: selectable text, reply button on hover.
    final touch = switch (theme.platform) {
      TargetPlatform.iOS || TargetPlatform.android => true,
      _ => false,
    };
    final text = touch
        ? GestureDetector(
            onLongPress: () => unawaited(_showLineActions(context)),
            child: Text.rich(span),
          )
        : SelectableText.rich(span);
    final onReply = widget.onReply;
    Widget row = Container(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: mentioned
          ? BoxDecoration(
              color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6),
              border: Border(
                left: BorderSide(color: theme.colorScheme.tertiary, width: 3),
              ),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: text),
          if (onReply != null)
            // Always there for touch and screen readers; brighter on hover.
            Opacity(
              opacity: _hovered ? 1 : 0.35,
              child: IconButton(
                tooltip: 'Reply to ${line.sender}',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                icon: const Icon(Icons.reply),
                onPressed: onReply,
              ),
            ),
        ],
      ),
    );
    if (onReply == null) return row;
    row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: row,
    );
    // Swipe right on a phone to reply, like other chat apps.
    return Dismissible(
      key: ObjectKey(line),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.25},
      confirmDismiss: (_) async {
        onReply();
        return false;
      },
      background: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Icon(Icons.reply, color: theme.colorScheme.primary),
        ),
      ),
      child: row,
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.onSubmit,
    required this.onCancelReply,
    this.replyTo,
    this.nicks = const [],
    this.onAttach,
    this.uploading = false,
    super.key,
  });

  final void Function(String text) onSubmit;

  /// Shows the picture button when set.
  final VoidCallback? onAttach;

  /// A picture is being uploaded.
  final bool uploading;
  final ChatLine? replyTo;
  final VoidCallback onCancelReply;

  /// Names Tab completes to.
  final List<String> nicks;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void didUpdateWidget(_InputBar old) {
    super.didUpdateWidget(old);
    if (widget.replyTo != null && widget.replyTo != old.replyTo) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Tab completes a nickname, as in mIRC.
  void _complete() {
    final done = completeNick(_controller.text, widget.nicks);
    if (done == null) return;
    _controller.value = TextEditingValue(
      text: done,
      selection: TextSelection.collapsed(offset: done.length),
    );
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
    final theme = Theme.of(context);
    final reply = widget.replyTo;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.uploading)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Encrypting and sending picture…',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        if (reply != null)
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(Icons.reply, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Replying to ${reply.sender}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        if (reply.text.isNotEmpty)
                          TextSpan(text: ': ${reply.text}'),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Cancel reply',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onCancelReply,
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              if (widget.onAttach != null)
                IconButton(
                  tooltip: 'Send a picture',
                  onPressed: widget.uploading ? null : widget.onAttach,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.tab): _complete,
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: reply == null
                          ? 'Message or /command'
                          : 'Reply to ${reply.sender}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
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
        ),
      ],
    );
  }
}

class _NickList extends StatelessWidget {
  const _NickList({
    required this.channel,
    required this.onNickTap,
    this.comfortable = false,
  });

  final IrcChannel channel;
  final void Function(String nick) onNickTap;

  /// Avatars with role rings (Comfortable density).
  final bool comfortable;

  @override
  Widget build(BuildContext context) {
    final members = channel.members.values.toList()
      ..sort((a, b) {
        final rank = _rank(a).compareTo(_rank(b));
        return rank != 0
            ? rank
            : a.nick.toLowerCase().compareTo(b.nick.toLowerCase());
      });
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
                  // Closes the slide-out list on phones; does nothing when
                  // the list is pinned at the side.
                  Scaffold.of(context).closeEndDrawer();
                  onNickTap(m.nick);
                },
                leading: comfortable
                    ? NickAvatar(nick: m.nick, size: 28, role: _role(m))
                    : null,
                trailing: const Icon(Icons.more_horiz, size: 18),
                title: Text(
                  '${m.topPrefix}${m.nick}',
                  style: TextStyle(
                    color: ChatColors.of(context).nickColor(m.nick),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Owners, admins, ops and half-ops get the operator ring; voice the
  /// accent ring.
  static NickRole _role(IrcMember m) => m.prefixes.contains(RegExp('[~&@%]'))
      ? NickRole.op
      : m.prefixes.contains('+')
      ? NickRole.voiced
      : NickRole.member;

  static int _rank(IrcMember m) =>
      m.prefixes.isEmpty ? 99 : '~&@%+'.indexOf(m.topPrefix).abs();
}

/// Asks what to do when a secure connection can't be made: trust an
/// unverified certificate, or fall back to an unencrypted connection.
class _ConnectionProblemBanner extends StatelessWidget {
  const _ConnectionProblemBanner({
    required this.network,
    required this.controller,
  });

  final NetworkSession network;
  final ChatController controller;

  @override
  Widget build(BuildContext context) {
    final cert = network.untrustedCertificate;
    final id = network.id;
    final String message;
    final List<Widget> actions;
    if (cert != null) {
      message =
          "${network.label}'s security certificate can't be verified "
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
          onPressed: () => controller.dismissConnectionProblem(id),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => controller.trustCertificateAndReconnect(id),
          child: const Text('Trust and connect'),
        ),
      ];
    } else {
      message =
          "Couldn't open a secure connection to ${network.label}. You can "
          'try an unencrypted connection instead. Others on the network '
          'path could read your messages and password.';
      actions = [
        TextButton(
          onPressed: () => controller.dismissConnectionProblem(id),
          child: const Text('Keep trying'),
        ),
        TextButton(
          onPressed: () => controller.connectWithoutEncryption(id),
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
