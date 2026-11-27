import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/links/chat_link.dart';
import 'package:irc_client/core/links/open_link.dart';
import 'package:irc_client/core/safety/content_filter.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/adaptive.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/chat_dividers.dart';
import 'package:irc_client/core/ui/composer.dart';
import 'package:irc_client/core/ui/message_group.dart';
import 'package:irc_client/core/ui/mirc_text.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:irc_client/features/calls/application/call_controller.dart';
import 'package:irc_client/features/calls/presentation/call_widgets.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/chat_layout.dart';
import 'package:irc_client/features/chat/application/conversations.dart';
import 'package:irc_client/features/chat/application/panel_prefs.dart';
import 'package:irc_client/features/chat/presentation/change_nick_dialog.dart';
import 'package:irc_client/features/chat/presentation/find_in_chat.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/links/presentation/link_preview.dart';
import 'package:irc_client/features/pictures/domain/file_link.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:irc_client/features/pictures/presentation/camera_capture.dart';
import 'package:irc_client/features/pictures/presentation/file_widgets.dart';
import 'package:irc_client/features/pictures/presentation/picture_widgets.dart';
import 'package:irc_client/features/rooms/presentation/room_info.dart';
import 'package:irc_client/features/safety/presentation/report_dialog.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Where the chat sits, which decides its top-left button.
enum ChatLayout {
  /// Phones: full screen, with a back button to Rooms home.
  phone,

  /// 600–899 pt: beside the rail and rooms list.
  rail,

  /// 900 pt and wider: beside the sidebar, which the top-left button hides
  /// and shows; People can be pinned on the right.
  sidebar,
}

/// The open conversation: header, messages, composer and (in rooms) the
/// people list. `ChatShell` puts it beside the lists that pick it.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({this.layout = ChatLayout.sidebar, this.onBack, super.key});

  final ChatLayout layout;

  /// Phones: back to Rooms home.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final buffer = state.activeBuffer;
    final net = state.activeNetwork;
    final isChannel = buffer?.isChannel ?? false;
    final channel = isChannel ? net?.client.channel(buffer!.name) : null;
    final wide = layout == ChatLayout.sidebar;
    final compact = layout == ChatLayout.phone;
    final panels = ref.watch(panelPrefsProvider);
    // Comfortable shows avatars in the chat and people lists.
    final comfortable =
        ref.watch(appearanceProvider).density == ChatDensity.comfortable;
    final panelsCtl = ref.read(panelPrefsProvider.notifier);
    // On wide screens the people panel can be pinned open or hidden.
    final showPeople = wide && panels.peoplePinned && channel != null;
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
                onMention: () => controller.startReply(_mentionOf(nick)),
                onCall: () => unawaited(_call(context, ref, nick)),
              ),
            ),
          );

    // Phones: what's new in other chats, on the back button.
    final elsewhere = compact
        ? unreadElsewhere(state, ref.watch(roomPrefsProvider))
        : (chats: 0, mention: false);
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: elsewhere.chats > 0 ? 100 : null,
        leading: switch (layout) {
          ChatLayout.phone => _BackToRooms(unread: elsewhere, onBack: onBack),
          ChatLayout.sidebar => IconButton(
            tooltip: panels.chatsPinned
                ? 'Hide servers and chats'
                : 'Show servers and chats',
            icon: Icon(panels.chatsPinned ? Icons.menu_open : Icons.menu),
            onPressed: () => unawaited(panelsCtl.toggleChats()),
          ),
          ChatLayout.rail => null,
        },
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
                child: Row(
                  children: [
                    if (comfortable && buffer != null && !buffer.isStatus) ...[
                      if (isChannel)
                        RoomAvatar(name: buffer.name, size: 36)
                      else
                        NickAvatar(nick: buffer.name, size: 36),
                      const SizedBox(width: 10),
                    ],
                    Flexible(
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
                            _subtitle(state, net, buffer, channel),
                            style: TypeScale.meta.copyWith(
                              color: AppTokens.of(context).textMuted,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        actions: [
          // Calls are for private chats.
          if (buffer != null && !buffer.isStatus && !isChannel)
            ...callButtons(context, ref),
          if (buffer != null)
            IconButton(
              tooltip: 'Search this chat',
              icon: const Icon(Icons.search),
              onPressed: () => unawaited(showFindInChat(context, buffer)),
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
          const SizedBox(width: 4),
        ],
      ),
      endDrawer: people == null || wide
          ? null
          : Drawer(child: SafeArea(child: people)),
      body: SafeArea(
        child: Row(
          children: [
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
                    child: MircColours(
                      enabled: ref.watch(appearanceProvider).ircColours,
                      child: _withMessageFont(
                        context,
                        ref.watch(appearanceProvider).font,
                        _MessageList(
                          // A new list per conversation: scroll and the "new"
                          // pill start fresh.
                          key: ValueKey(buffer?.key),
                          lines: buffer?.lines ?? [],
                          ownNick: net?.nick ?? '',
                          networkId: net?.id ?? '',
                          style:
                              buffer == null || buffer.isStatus || !comfortable
                              ? _ChatStyle.lines
                              : isChannel
                              ? _ChatStyle.groups
                              : _ChatStyle.bubbles,
                          unreadMarker: buffer?.unreadMarker,
                          roleOf: channel == null
                              ? null
                              : (nick) {
                                  final m = channel.members[nick.toLowerCase()];
                                  return m == null
                                      ? NickRole.member
                                      : nickRoleOf(m);
                                },
                          // Pictures load on their own only in a private chat
                          // where you've written to the other person.
                          autoShowPictures:
                              buffer != null &&
                              !buffer.isStatus &&
                              !isChannel &&
                              buffer.lines.any(
                                (l) => l.kind == ChatLineKind.own,
                              ),
                          autoShowLinkImages: ref
                              .watch(appearanceProvider)
                              .autoLinkImages,
                          onReply: isChannel ? controller.startReply : null,
                          onLoadOlder:
                              buffer != null && controller.canLoadOlder(buffer)
                              ? () => controller.loadOlder(buffer.key)
                              : null,
                          loadingOlder:
                              buffer?.historyWant == HistoryWant.older,
                          onReport: buffer == null || buffer.isStatus
                              ? null
                              : (line) => unawaited(
                                  _reportMessage(
                                    context,
                                    controller,
                                    line,
                                    networkId: buffer.networkId,
                                    room: isChannel ? buffer.name : null,
                                  ),
                                ),
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
                              onMention: isChannel
                                  ? () =>
                                        controller.startReply(_mentionOf(nick))
                                  : null,
                              onCall: () =>
                                  unawaited(_call(context, ref, nick)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TypingLine(nicks: buffer?.typingNicks ?? const []),
                  Composer(
                    // A new composer per conversation keeps drafts apart.
                    key: ValueKey(buffer?.key),
                    onSubmit: controller.submit,
                    onChanged: controller.noteTyping,
                    hint: buffer == null || buffer.isStatus
                        ? 'Message or /command'
                        : 'Message ${buffer.name}',
                    replyTo: buffer?.replyTo?.sender,
                    replyText: stripFormatting(buffer?.replyTo?.text ?? ''),
                    onCancelReply: controller.cancelReply,
                    rooms: [
                      for (final b in state.buffers.values)
                        if (b.networkId == net?.id && b.isChannel) b.name,
                    ],
                    uploading: (buffer?.uploading ?? 0) > 0,
                    // Pictures are for private chats.
                    onAttach: buffer != null && !buffer.isStatus && !isChannel
                        ? () => unawaited(sendPicture(context, ref))
                        : null,
                    onSendFile: buffer != null && !buffer.isStatus && !isChannel
                        ? () => unawaited(sendFile(context, ref))
                        : null,
                    onTakePhoto:
                        buffer != null &&
                            !buffer.isStatus &&
                            !isChannel &&
                            canTakePhotos(Theme.of(context).platform)
                        ? () => unawaited(
                            sendPicture(
                              context,
                              ref,
                              source: PhotoSource.camera,
                            ),
                          )
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

  /// Under the chat's name: "142 people · Libera.Chat" in a room, the
  /// network in a private chat, the connection on the server tab. While
  /// not connected, the connection status instead.
  static String _subtitle(
    ChatState state,
    NetworkSession? net,
    ChatBuffer? buffer,
    IrcChannel? channel,
  ) {
    if (net == null) return 'Not connected';
    if (buffer == null || buffer.isStatus) return _statusLabel(net);
    if (net.status != IrcConnectionStatus.connected) {
      return '${net.label} · ${_statusLabel(net)}';
    }
    if (channel != null) {
      final n = channel.members.length;
      return '$n ${n == 1 ? 'person' : 'people'} · ${net.label}';
    }
    return net.label;
  }

  static String statusLabel(NetworkSession s) => _statusLabel(s);

  /// A bare line naming [nick]: replying to it writes `nick: ` in front of
  /// your message, which is how IRC mentions someone.
  static ChatLine _mentionOf(String nick) =>
      ChatLine(text: '', sender: nick, kind: ChatLineKind.message);

  /// Opens a private chat with [nick] and starts a voice call there.
  static Future<void> _call(
    BuildContext context,
    WidgetRef ref,
    String nick,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    ref.read(chatControllerProvider.notifier).openPrivateChat(nick);
    final error = await ref
        .read(callControllerProvider.notifier)
        .startCall(video: false);
    if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
  }

  static String _statusLabel(NetworkSession s) => switch (s.status) {
    IrcConnectionStatus.connected => 'Connected as ${s.nick}',
    IrcConnectionStatus.connecting => 'Connecting…',
    IrcConnectionStatus.registering => 'Logging in…',
    IrcConnectionStatus.reconnecting => 'Reconnecting…',
    IrcConnectionStatus.disconnected => 'Disconnected',
  };

  /// Disconnects and forgets a network; back to the network picker when
  /// it was the last one.
  static Future<void> closeNetwork(
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
    // Rooms get the full Room info page.
    if (channel != null) {
      return showRoomInfo(
        context,
        networkId: net.id,
        channel: channel.name,
        onPeople: phone || layout == ChatLayout.rail
            ? () => Scaffold.of(context).openEndDrawer()
            : null,
      );
    }
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
                          ContentFilter.clean(
                            context,
                            stripFormatting(channel.topic),
                          ),
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
                if (!isStatus)
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
                    'Close chat',
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
                    () => closeNetwork(context, ref, net.id),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  /// Asks for a nickname and opens a private chat with them.
  static Future<void> promptPrivateMessage(
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

  /// Asks for a room name and joins it.
  static Future<void> promptJoin(
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

/// Actions that aren't about the open chat, for [NetworksPanel].
class NetworkActions {
  const NetworkActions({
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
/// Your networks and everything that isn't about one chat: Browse /
/// Message / Join at the top; per network your nickname, a menu to
/// reconnect, disconnect or close it, its server messages and favorite rooms
/// not joined yet; then Create a room, Add a network and Appearance. Shown
/// in the "You" tab and panel.
class NetworksPanel extends StatelessWidget {
  const NetworksPanel({
    required this.state,
    required this.prefs,
    required this.controller,
    required this.onChangeNick,
    required this.actions,
    this.onOpenServer,
    super.key,
  });

  final ChatState state;
  final RoomPrefs prefs;
  final ChatController controller;
  final Future<void> Function(String networkId) onChangeNick;
  final NetworkActions? actions;

  /// After a network's server messages are picked (phones open the chat).
  final VoidCallback? onOpenServer;

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
            if (b.isStatus)
              ListTile(
                dense: true,
                leading: const Icon(Icons.dns_outlined),
                title: const Text('Server messages'),
                trailing: UnreadBadge(count: b.unread, mention: b.mentioned),
                onTap: () {
                  controller.selectBuffer(b.key);
                  _closeDrawer(context);
                  onOpenServer?.call();
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
        ListTile(
          dense: true,
          leading: const Icon(Icons.settings_outlined),
          title: const Text('Settings'),
          onTap: () {
            _closeDrawer(context);
            unawaited(context.push('/settings'));
          },
        ),
      ],
    );
  }
}

/// Actions for another user: private message, whois, copy nick, invite,
/// and (for the room's operators) make operator, remove and ban.
/// The profile card for [nick]: avatar with their role, then Message,
/// Call and Mention, then whois, copy, invite, Ignore and Report, and (for
/// the room's operators) moderation.
Future<void> showUserActions(
  BuildContext context,
  ChatController controller,
  String ownNick,
  String nick, {
  NetworkSession? network,
  String? room,
  VoidCallback? onReply,
  VoidCallback? onMention,
  VoidCallback? onCall,
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
            _ProfileHeader(
              nick: nick,
              member: member,
              room: room,
              network: network,
              isMe: isMe,
            ),
            if (!isMe)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    _QuickAction(
                      icon: Icons.chat_bubble_outline,
                      label: 'Message',
                      onTap: () {
                        Navigator.pop(sheet);
                        controller.openPrivateChat(nick);
                      },
                    ),
                    if (onCall != null)
                      _QuickAction(
                        icon: Icons.call_outlined,
                        label: 'Call',
                        onTap: () {
                          Navigator.pop(sheet);
                          onCall();
                        },
                      ),
                    if (onMention != null)
                      _QuickAction(
                        icon: Icons.alternate_email,
                        label: 'Mention',
                        onTap: () {
                          Navigator.pop(sheet);
                          onMention();
                        },
                      ),
                  ],
                ),
              ),
            const Divider(height: 1),
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
                  controller.isBlocked(nick)
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                title: Text(
                  controller.isBlocked(nick)
                      ? 'Stop ignoring $nick'
                      : 'Ignore $nick',
                ),
                subtitle: controller.isBlocked(nick)
                    ? null
                    : const Text('Hide their messages, photos and invitations'),
                onTap: () {
                  Navigator.pop(sheet);
                  if (controller.isBlocked(nick)) {
                    controller.unblockUser(nick);
                  } else {
                    controller.blockUser(nick);
                  }
                },
              ),
            if (!isMe)
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text('Report $nick'),
                onTap: () {
                  Navigator.pop(sheet);
                  unawaited(
                    _showReport(
                      context,
                      controller,
                      nick,
                      room: room,
                      network: network,
                    ),
                  );
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

/// The top of the profile card: avatar with role ring, nick, and what we
/// know (role in the room, away, network).
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.nick,
    required this.isMe,
    this.member,
    this.room,
    this.network,
  });

  final String nick;
  final bool isMe;
  final IrcMember? member;
  final String? room;
  final NetworkSession? network;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final m = member;
    final role = m == null ? NickRole.member : nickRoleOf(m);
    final details = [
      if (isMe) 'You',
      if (role == NickRole.op && room != null) 'Operator of $room',
      if (role == NickRole.voiced && room != null) 'Has a voice in $room',
      if (m?.away ?? false) 'Away',
      ?network?.label,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          NickAvatar(nick: nick, size: 64, role: role, away: m?.away ?? false),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nick,
                  style: TypeScale.title.copyWith(
                    color: ChatColors.of(context).nickColor(nick),
                  ),
                ),
                if (details.isNotEmpty)
                  Text(
                    details,
                    style: TypeScale.meta.copyWith(color: tokens.textMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A round button with a label under it, for the profile card.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(tokens.accentSoft, tokens.surface),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: tokens.onAccentSoft),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TypeScale.meta.copyWith(color: tokens.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// IRC has no app-wide report button: this says who can act (the room's
/// operators and the network's staff) and offers to message an operator or
/// ignore the person.
Future<void> _showReport(
  BuildContext context,
  ChatController controller,
  String nick, {
  String? room,
  NetworkSession? network,
}) {
  final ops = [
    if (room != null)
      for (final m
          in network?.client.channel(room)?.members.values ??
              const <IrcMember>[])
        if (nickRoleOf(m) == NickRole.op &&
            m.nick.toLowerCase() != nick.toLowerCase() &&
            m.nick.toLowerCase() != network?.nick.toLowerCase())
          m.nick,
  ];
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('Report $nick'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IRC rooms are run by their operators, and each network has '
              'its own staff. ${ops.isEmpty ? 'Ask the network staff '
                        '(often in #help) for help.' : 'You can tell an '
                        'operator of $room what happened:'}',
            ),
            for (final op in ops.take(5))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: NickAvatar(nick: op, size: 32, role: NickRole.op),
                title: Text(op),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.pop(dialog);
                    controller.openPrivateChat(op);
                  },
                  child: const Text('Message'),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
        if (!controller.isBlocked(nick))
          FilledButton(
            onPressed: () {
              Navigator.pop(dialog);
              controller.blockUser(nick);
            },
            child: Text('Ignore $nick'),
          ),
      ],
    ),
  );
}

/// Asks why, then reports [line] to the app's makers and ignores its
/// sender.
Future<void> _reportMessage(
  BuildContext context,
  ChatController controller,
  ChatLine line, {
  required String networkId,
  String? room,
}) async {
  final sender = line.sender ?? '';
  final messenger = ScaffoldMessenger.of(context);
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => ReportDialog(
      title: 'Report message',
      explanation:
          'The message is sent to the IRCage team for review and $sender is '
          'ignored, so you stop seeing their messages. Room operators and '
          'network staff can act on them too: Report on their profile '
          'shows who.',
    ),
  );
  if (reason == null) return;
  final error = await controller.reportMessage(
    line,
    networkId: networkId,
    room: room,
    reason: reason,
  );
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        error == null
            ? "Thanks, it's been reported. You won't see messages from "
                  '$sender anymore.'
            : '$error $sender is ignored.',
      ),
    ),
  );
}

void _copyNick(String text) {
  // Clipboard errors are harmless here; nothing to report.
  Clipboard.setData(ClipboardData(text: text)).ignore();
}

/// Messages in the font picked in Appearance.
Widget _withMessageFont(BuildContext context, MessageFont font, Widget child) =>
    font == MessageFont.mono
    ? DefaultTextStyle.merge(
        style: TextStyle(
          fontFamily: MessageFont.monoFamilyFor(Theme.of(context).platform),
          fontFamilyFallback: MessageFont.monoFamilies,
        ),
        child: child,
      )
    : child;

/// How the open conversation's messages are drawn.
enum _ChatStyle {
  /// `HH:MM <nick> text`: Compact density and the server tab.
  lines,

  /// Grouped under one avatar: rooms in Comfortable.
  groups,

  /// Bubbles: private chats in Comfortable.
  bubbles,
}

/// Lines that count towards the "3 new" pill.
bool _countsAsNew(ChatLine l) => switch (l.kind) {
  ChatLineKind.message || ChatLineKind.action || ChatLineKind.notice => true,
  _ => false,
};

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.lines,
    required this.ownNick,
    required this.onNickTap,
    this.style = _ChatStyle.lines,
    this.networkId = '',
    this.autoShowPictures = false,
    this.autoShowLinkImages = false,
    this.unreadMarker,
    this.roleOf,
    this.onReply,
    this.onReport,
    this.onLoadOlder,
    this.loadingOlder = false,
    super.key,
  });

  final List<ChatLine> lines;
  final String ownNick;
  final String networkId;
  final bool autoShowPictures;

  /// Load images people link to without a tap (Appearance setting).
  final bool autoShowLinkImages;
  final _ChatStyle style;
  final ChatLine? unreadMarker;
  final NickRole Function(String nick)? roleOf;
  final void Function(String nick) onNickTap;

  /// Null where replies don't apply (server tab, private chats).
  final void Function(ChatLine line)? onReply;

  /// Reports someone else's message; null on the server tab.
  final void Function(ChatLine line)? onReport;

  /// Fetches older messages from the server (CHATHISTORY); null when it
  /// has none to give. Called when the top of the list comes into view.
  final VoidCallback? onLoadOlder;

  /// An older-messages request is out.
  final bool loadingOlder;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scroll = ScrollController();

  /// Within this many pixels of the newest message counts as at the bottom.
  static const double _bottomSlack = 48;
  bool _atBottom = true;

  /// The newest line seen while at the bottom; later ones are "new".
  ChatLine? _lastSeen;

  /// Lines already here when the chat opened don't animate in; each later
  /// line animates once.
  final Set<ChatLine> _initial = Set.identity();
  final Set<ChatLine> _animated = Set.identity();
  bool _primed = false;

  /// Whether [line] should fade and slide in (only the first time).
  bool _animate(ChatLine line) =>
      _primed && !_initial.contains(line) && _animated.add(line);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final at = !_scroll.hasClients || _scroll.offset <= _bottomSlack;
      if (at != _atBottom) setState(() => _atBottom = at);
      // Near the top (the end of the reversed list): fetch older messages.
      final older = widget.onLoadOlder;
      if (older != null &&
          !widget.loadingOlder &&
          _scroll.hasClients &&
          _scroll.position.extentAfter < 300) {
        older();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _hasOlderRow => widget.onLoadOlder != null || widget.loadingOlder;

  /// The top row: a spinner while older messages load, otherwise a button
  /// to load them (scrolling up also does).
  Widget _olderRow(BuildContext context) => Padding(
    key: const ValueKey('older-messages'),
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Center(
      child: widget.loadingOlder
          ? Semantics(
              label: 'Loading earlier messages',
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            )
          : TextButton.icon(
              icon: const Icon(Icons.history),
              label: const Text('Load earlier messages'),
              onPressed: widget.onLoadOlder,
            ),
    ),
  );

  void _jumpToLatest() {
    final d = Motion.of(context, Motion.slow);
    if (d == Duration.zero) {
      _scroll.jumpTo(0);
    } else {
      _scroll.animateTo(0, duration: d, curve: Motion.curve);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lines;
    if (!_primed) {
      _initial.addAll(lines);
      _primed = true;
    }
    if (_atBottom || _lastSeen == null) {
      _lastSeen = lines.isEmpty ? null : lines.last;
    }
    final seen = lines.lastIndexWhere((l) => identical(l, _lastSeen));
    final fresh = _atBottom || seen < 0
        ? const <ChatLine>[]
        : lines.skip(seen + 1).where(_countsAsNew).toList();

    final items = layoutChat(
      lines,
      grouped: widget.style != _ChatStyle.lines,
      ownNick: widget.ownNick,
      unreadMarker: widget.unreadMarker,
    );
    final list = ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: EdgeInsets.symmetric(
        horizontal: widget.style == _ChatStyle.lines ? 12 : 10,
        vertical: 8,
      ),
      // One more row at the top for older messages from the server.
      itemCount: items.length + (_hasOlderRow ? 1 : 0),
      itemBuilder: (context, i) {
        if (i == items.length) return _olderRow(context);
        final item = items[items.length - 1 - i];
        final first = switch (item) {
          GroupItem(:final lines) || PresenceItem(:final lines) => lines.first,
          SystemItem(:final line) || LineItem(:final line) => line,
          DayItem() || UnreadItem() => null,
        };
        final child = _item(context, item);
        return first != null && _animate(first)
            ? _Appear(key: child.key, child: child)
            : child;
      },
    );
    return Stack(
      children: [
        Positioned.fill(child: list),
        if (fresh.isNotEmpty)
          PositionedDirectional(
            end: 16,
            bottom: 12,
            child: JumpPill(
              count: fresh.length,
              mention: fresh.any((l) => lineMentions(l, widget.ownNick)),
              onTap: _jumpToLatest,
            ),
          ),
      ],
    );
  }

  bool _canReply(ChatLine line) =>
      widget.onReply != null &&
      line.sender != null &&
      line.kind != ChatLineKind.own &&
      line.kind != ChatLineKind.event &&
      line.kind != ChatLineKind.error;

  VoidCallback? _replyTo(ChatLine line) =>
      _canReply(line) ? () => widget.onReply!(line) : null;

  /// Only other people's messages can be reported.
  VoidCallback? _reportOf(ChatLine line) {
    final report = widget.onReport;
    return report != null &&
            line.sender != null &&
            line.kind == ChatLineKind.message
        ? () => report(line)
        : null;
  }

  PictureLink? _pictureIn(ChatLine line) =>
      line.sender != null &&
          (line.kind == ChatLineKind.own || line.kind == ChatLineKind.message)
      ? PictureLink.find(stripFormatting(line.text))
      : null;

  /// A photo or file shown under its message, if the message has one.
  Widget? _picture(ChatLine line, {double indent = 48}) {
    final dcc = line.dccId;
    if (dcc != null) {
      return DccCard(key: ValueKey(dcc), id: dcc, indent: indent);
    }
    final link = _pictureIn(line);
    if (link == null) {
      final file =
          line.sender != null &&
              (line.kind == ChatLineKind.own ||
                  line.kind == ChatLineKind.message)
          ? FileLink.find(stripFormatting(line.text))
          : null;
      if (file == null) return _linkPreview(line, indent: indent);
      return FileBubble(
        key: ValueKey(file),
        link: file,
        sender: line.sender!,
        isOwn: line.kind == ChatLineKind.own,
        indent: indent,
      );
    }
    final isOwn = line.kind == ChatLineKind.own;
    return PictureBubble(
      key: ValueKey(link),
      link: link,
      sender: line.sender!,
      networkId: widget.networkId,
      isOwn: isOwn,
      autoShow: isOwn || widget.autoShowPictures,
      indent: indent,
    );
  }

  /// The first image or video someone linked to in [line], if any.
  Widget? _linkPreview(ChatLine line, {required double indent}) {
    final sender = line.sender;
    if (sender == null ||
        (line.kind != ChatLineKind.own &&
            line.kind != ChatLineKind.message &&
            line.kind != ChatLineKind.action)) {
      return null;
    }
    final found = firstMediaLink(stripFormatting(line.text));
    if (found == null) return null;
    return LinkPreview(
      key: ValueKey(found.uri),
      uri: found.uri,
      media: found.media,
      sender: sender,
      autoShow: line.kind == ChatLineKind.own || widget.autoShowLinkImages,
      indent: indent,
    );
  }

  Widget _item(BuildContext context, ChatItem item) {
    switch (item) {
      case DayItem(:final day):
        return DayDivider(key: ValueKey(day), day: day);
      case UnreadItem():
        return const UnreadDivider(key: ValueKey('unread'));
      case PresenceItem(:final lines):
        return SystemEventLine(
          key: ObjectKey(lines.first),
          text: presenceSummary(lines),
          details: [
            for (final l in lines) ContentFilter.clean(context, l.text),
          ],
        );
      case SystemItem(:final line):
        return SystemEventLine(
          key: ObjectKey(line),
          text: ContentFilter.clean(context, line.text),
          error: line.kind == ChatLineKind.error,
        );
      case LineItem(:final line):
        final tile = _MessageTile(
          key: ObjectKey(line),
          line: line,
          ownNick: widget.ownNick,
          onNickTap: widget.onNickTap,
          onReply: _replyTo(line),
          onReport: _reportOf(line),
        );
        final picture = _picture(line);
        if (picture == null) return tile;
        return Column(
          key: ObjectKey(line),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [tile, picture],
        );
      case GroupItem():
        return widget.style == _ChatStyle.bubbles
            ? _bubbles(context, item)
            : _group(context, item);
    }
  }

  Widget _group(BuildContext context, GroupItem group) {
    final sender = group.sender;
    return Padding(
      key: ObjectKey(group.lines.first),
      padding: const EdgeInsets.only(top: 2),
      child: MessageGroup(
        nick: sender,
        time: _time(context, group.time),
        role: widget.roleOf?.call(sender) ?? NickRole.member,
        own: group.own,
        mentioned: group.mentioned,
        onNickTap: () => widget.onNickTap(sender),
        children: [
          for (final (i, line) in group.lines.indexed) ...[
            _appearIf(
              i > 0 && _animate(line),
              _LineActions(
                key: ObjectKey(line),
                line: line,
                onReply: _replyTo(line),
                onReport: _reportOf(line),
                child: _LineBody(line: line, ownNick: widget.ownNick),
              ),
            ),
            ?_picture(line, indent: 0),
          ],
        ],
      ),
    );
  }

  Widget _bubbles(BuildContext context, GroupItem group) {
    final tokens = AppTokens.of(context);
    final own = group.own;
    return Padding(
      key: ObjectKey(group.lines.first),
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: own
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          for (final (i, line) in group.lines.indexed) ...[
            if (i > 0) const SizedBox(height: 2),
            _appearIf(
              i > 0 && _animate(line),
              _LineActions(
                key: ObjectKey(line),
                line: line,
                onReply: _replyTo(line),
                onReport: _reportOf(line),
                child: MessageBubble(
                  own: own,
                  continued: i > 0,
                  child: _LineBody(
                    line: line,
                    ownNick: widget.ownNick,
                    bubble: true,
                  ),
                ),
              ),
            ),
            ?_picture(line, indent: 0),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
            child: Text(
              _time(context, group.lines.last.time),
              style: TypeScale.meta.copyWith(
                color: tokens.textMuted,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _appearIf(bool animate, Widget child) =>
    animate ? _Appear(key: child.key, child: child) : child;

/// A new message fading in and sliding up 8 pt (none with Reduce Motion).
class _Appear extends StatefulWidget {
  const _Appear({required this.child, super.key});

  final Widget child;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_t.status == AnimationStatus.dismissed) {
      final d = Motion.of(context);
      if (d == Duration.zero) {
        _t.value = 1;
      } else {
        _t
          ..duration = d
          ..forward();
      }
    }
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _t,
    child: widget.child,
    builder: (context, child) {
      final v = Motion.curve.transform(_t.value);
      return Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - v)),
          child: child,
        ),
      );
    },
  );
}

String _time(BuildContext context, DateTime t) =>
    TimeOfDay.fromDateTime(t.toLocal()).format(context);

/// One message's text inside a group or bubble: no time or nick, since the
/// group shows them. Your nick is highlighted where it mentions you.
/// Opens a link from a message, or says it couldn't.
void _openChatLink(BuildContext context, Uri uri) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  unawaited(
    openLink(uri).then((ok) {
      if (!ok) {
        messenger?.showSnackBar(
          const SnackBar(content: Text("Couldn't open the link.")),
        );
      }
    }),
  );
}

class _LineBody extends StatefulWidget {
  const _LineBody({
    required this.line,
    required this.ownNick,
    this.bubble = false,
  });

  final ChatLine line;
  final String ownNick;

  /// Inside a bubble: colours come from the bubble.
  final bool bubble;

  @override
  State<_LineBody> createState() => _LineBodyState();
}

class _LineBodyState extends State<_LineBody> {
  late final _links = LinkTaps((uri) => _openChatLink(context, uri));

  @override
  void dispose() {
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final ownNick = widget.ownNick;
    final bubble = widget.bubble;
    final tokens = AppTokens.of(context);
    final chat = ChatColors.of(context);
    final mentioned = lineMentions(line, ownNick);
    final base = bubble
        ? DefaultTextStyle.of(context).style
        : TypeScale.body.copyWith(color: tokens.textPrimary);
    // What the text sits on, so mIRC colours can be kept readable.
    final behind = bubble
        ? (line.kind == ChatLineKind.own
              ? tokens.accent
              : tokens.surfaceOverlay)
        : mentioned
        ? Color.alphaBlend(tokens.mentionSoft, tokens.surface)
        : tokens.surface;
    final colours = MircColours.of(context);
    List<InlineSpan> body(Color textColor, {bool highlight = false}) =>
        mircSpans(
          line.text,
          tokens: tokens,
          background: behind,
          textColor: textColor,
          colours: colours,
          filter: ContentFilter.of(context),
          highlight: highlight ? ownNick : null,
          highlightStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: bubble ? null : tokens.readable(tokens.mention, behind),
          ),
          links: _links,
          linkStyle: TextStyle(
            decoration: TextDecoration.underline,
            color: bubble ? null : tokens.readable(tokens.accent, behind),
          ),
        );
    final baseColor = base.color ?? tokens.textPrimary;
    final span = switch (line.kind) {
      ChatLineKind.action => TextSpan(
        style: TextStyle(
          fontStyle: FontStyle.italic,
          color: bubble ? null : chat.action,
        ),
        children: [
          TextSpan(text: '${line.sender} '),
          ...body(bubble ? baseColor : chat.action),
        ],
      ),
      ChatLineKind.notice => TextSpan(
        style: TextStyle(color: bubble ? null : chat.notice),
        children: body(bubble ? baseColor : chat.notice),
      ),
      _ => TextSpan(children: body(baseColor, highlight: mentioned)),
    };
    final full = TextSpan(style: base, children: [span]);
    final time = _time(context, line.time);
    final kind = switch (line.kind) {
      ChatLineKind.action => 'action',
      ChatLineKind.notice => 'notice',
      _ => 'message',
    };
    return MergeSemantics(
      child: Semantics(
        label:
            '${line.sender}, $time, $kind${mentioned ? ', mentions you' : ''}',
        child: _isTouch(context)
            ? Text.rich(full)
            : SelectableText.rich(
                full,
                contextMenuBuilder: _lineContextMenu(context),
              ),
      ),
    );
  }
}

/// Phones and tablets: plain text so a swipe can reply; computers:
/// selectable text with a reply button on hover.
bool _isTouch(BuildContext context) => switch (Theme.of(context).platform) {
  TargetPlatform.iOS || TargetPlatform.android => true,
  _ => false,
};

/// Reply and copy for one message: swipe right or the reply button to
/// reply, long-press (touch) for Reply and Copy.
class _LineActions extends StatefulWidget {
  const _LineActions({
    required this.line,
    required this.child,
    this.onReply,
    this.onReport,
    super.key,
  });

  final ChatLine line;
  final Widget child;
  final VoidCallback? onReply;
  final VoidCallback? onReport;

  @override
  State<_LineActions> createState() => _LineActionsState();
}

class _LineActionsState extends State<_LineActions> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final onReply = widget.onReply;
    final onReport = widget.onReport;
    if (_isTouch(context)) {
      // Phones: swipe or long-press; screen readers get Reply and Report.
      final pressable = GestureDetector(
        onLongPress: () => unawaited(
          _showLineActions(context, widget.line, onReply, onReport),
        ),
        child: onReport == null
            ? widget.child
            : Semantics(
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Report message'):
                      onReport,
                },
                child: widget.child,
              ),
      );
      if (onReply == null) return pressable;
      return _swipeToReply(
        context,
        widget.line,
        onReply,
        Semantics(
          customSemanticsActions: {
            CustomSemanticsAction(label: 'Reply to ${widget.line.sender}'):
                onReply,
          },
          child: pressable,
        ),
      );
    }
    // Computers: right-click for the menu; reply and report buttons show
    // on hover or keyboard focus.
    final clickable = GestureDetector(
      onSecondaryTapUp: (d) => unawaited(
        _showLineActions(
          context,
          widget.line,
          onReply,
          onReport,
          position: d.globalPosition,
        ),
      ),
      // Right-clicking the (selectable) text gets Reply and Report added
      // to its Copy / Select All menu.
      child: _LineMenuItems(
        items: [
          if (onReply != null)
            ContextMenuButtonItem(
              label: 'Reply to ${widget.line.sender}',
              onPressed: () {
                ContextMenuController.removeAny();
                onReply();
              },
            ),
          if (onReport != null)
            ContextMenuButtonItem(
              label: 'Report message',
              onPressed: () {
                ContextMenuController.removeAny();
                onReport();
              },
            ),
        ],
        child: widget.child,
      ),
    );
    if (onReply == null && onReport == null) return clickable;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: clickable),
          Focus(
            canRequestFocus: false,
            onFocusChange: (f) => setState(() => _hovered = f),
            child: Opacity(
              opacity: _hovered ? 1 : 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onReply != null)
                    IconButton(
                      tooltip: 'Reply to ${widget.line.sender}',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: const Icon(Icons.reply),
                      onPressed: onReply,
                    ),
                  if (onReport != null)
                    IconButton(
                      tooltip: 'Report message',
                      visualDensity: VisualDensity.compact,
                      iconSize: 18,
                      icon: const Icon(Icons.flag_outlined),
                      onPressed: onReport,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Extra items for a message's text menu on computers, from
/// [_LineActions] to the selectable text inside it.
class _LineMenuItems extends InheritedWidget {
  const _LineMenuItems({required this.items, required super.child});

  final List<ContextMenuButtonItem> items;

  @override
  bool updateShouldNotify(_LineMenuItems old) => old.items != items;
}

/// The text's own menu (Copy, Select All) plus the message's actions
/// from the [_LineMenuItems] above [context], in the platform's style (a
/// Mac menu on macOS). Looked up here: the menu itself is built in the
/// overlay, outside the message.
EditableTextContextMenuBuilder _lineContextMenu(BuildContext context) {
  final extra =
      context.dependOnInheritedWidgetOfExactType<_LineMenuItems>()?.items ??
      const <ContextMenuButtonItem>[];
  return (context, state) => AdaptiveTextSelectionToolbar.buttonItems(
    anchors: state.contextMenuAnchors,
    buttonItems: [...state.contextMenuButtonItems, ...extra],
  );
}

Widget _swipeToReply(
  BuildContext context,
  ChatLine line,
  VoidCallback onReply,
  Widget child,
) => Dismissible(
  key: ObjectKey(line),
  direction: DismissDirection.startToEnd,
  dismissThresholds: const {DismissDirection.startToEnd: 0.25},
  confirmDismiss: (_) async {
    unawaited(HapticFeedback.selectionClick());
    onReply();
    return false;
  },
  background: Align(
    alignment: AlignmentDirectional.centerStart,
    child: Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Icon(Icons.reply, color: AppTokens.of(context).accent),
    ),
  ),
  child: child,
);

Future<void> _showLineActions(
  BuildContext context,
  ChatLine line,
  VoidCallback? onReply,
  VoidCallback? onReport, {
  Offset? position,
}) => showActionMenu(
  context,
  position: position,
  actions: [
    if (onReply != null)
      MenuAction(
        icon: Icons.reply,
        label: 'Reply to ${line.sender}',
        onSelected: onReply,
      ),
    MenuAction(
      icon: Icons.copy,
      label: 'Copy message',
      onSelected: () => _copyNick(stripFormatting(line.text)),
    ),
    if (onReport != null)
      MenuAction(
        icon: Icons.flag_outlined,
        label: 'Report message',
        destructive: true,
        onSelected: onReport,
      ),
  ],
);

/// One line as `HH:MM <nick> text`, for Compact and the server tab.
class _MessageTile extends StatefulWidget {
  const _MessageTile({
    required this.line,
    required this.ownNick,
    required this.onNickTap,
    this.onReply,
    this.onReport,
    super.key,
  });

  final ChatLine line;
  final String ownNick;
  final void Function(String nick) onNickTap;
  final VoidCallback? onReply;
  final VoidCallback? onReport;

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
  late final _links = LinkTaps((uri) => _openChatLink(context, uri));

  @override
  void dispose() {
    _nickTap.dispose();
    _links.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = AppTokens.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = widget.line;
    final time = _time(context, line.time);
    final sender = line.sender;
    final chatColors = ChatColors.of(context);
    final nickStyle = TextStyle(
      fontWeight: FontWeight.bold,
      color: sender == null ? null : chatColors.nickColor(sender),
    );
    final mentioned = lineMentions(line, widget.ownNick);
    final behind = mentioned
        ? Color.alphaBlend(tokens.mentionSoft, tokens.surface)
        : tokens.surface;
    final colours = MircColours.of(context);
    List<InlineSpan> text(Color textColor) => mircSpans(
      line.text,
      tokens: tokens,
      background: behind,
      textColor: textColor,
      colours: colours,
      filter: ContentFilter.of(context),
      links: _links,
      linkStyle: TextStyle(
        decoration: TextDecoration.underline,
        color: tokens.readable(tokens.accent, behind),
      ),
    );
    final InlineSpan body = switch (line.kind) {
      ChatLineKind.message || ChatLineKind.own => TextSpan(
        children: [
          TextSpan(text: '<$sender> ', style: nickStyle, recognizer: _nickTap),
          ...text(theme.colorScheme.onSurface),
        ],
      ),
      ChatLineKind.action => TextSpan(
        style: TextStyle(fontStyle: FontStyle.italic, color: chatColors.action),
        children: [
          const TextSpan(text: '* '),
          TextSpan(text: sender, recognizer: _nickTap),
          const TextSpan(text: ' '),
          ...text(chatColors.action),
        ],
      ),
      ChatLineKind.notice => TextSpan(
        style: TextStyle(color: chatColors.notice),
        children: [
          if (sender != null)
            TextSpan(text: '-$sender- ', recognizer: _nickTap),
          ...text(chatColors.notice),
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
    // The message font from Appearance arrives as the default text style.
    final inherited = DefaultTextStyle.of(context).style;
    final span = TextSpan(
      style: theme.textTheme.bodyMedium?.copyWith(
        fontFamily: inherited.fontFamily,
        fontFamilyFallback: inherited.fontFamilyFallback,
      ),
      children: [
        TextSpan(
          text: '$time  ',
          style: TextStyle(color: muted, fontSize: 12),
        ),
        body,
      ],
    );
    return _LineActions(
      line: line,
      onReply: widget.onReply,
      onReport: widget.onReport,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        decoration: mentioned
            ? BoxDecoration(
                color: tokens.mentionSoft,
                border: Border(
                  left: BorderSide(color: tokens.mentionBar, width: 3),
                ),
              )
            : null,
        child: _isTouch(context)
            ? Text.rich(span)
            : SelectableText.rich(
                span,
                contextMenuBuilder: _lineContextMenu(context),
              ),
      ),
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
    final tokens = AppTokens.of(context);
    final members = channel.members.values.toList()
      ..sort((a, b) {
        final rank = _rank(a).compareTo(_rank(b));
        return rank != 0
            ? rank
            : a.nick.toLowerCase().compareTo(b.nick.toLowerCase());
      });
    // Away people go last whatever their role, dimmed.
    final groups = <(String, List<IrcMember>)>[
      (
        'Operators',
        [
          for (final m in members)
            if (!m.away && _role(m) == NickRole.op) m,
        ],
      ),
      (
        'Voiced',
        [
          for (final m in members)
            if (!m.away && _role(m) == NickRole.voiced) m,
        ],
      ),
      (
        'Members',
        [
          for (final m in members)
            if (!m.away && _role(m) == NickRole.member) m,
        ],
      ),
      (
        'Away',
        [
          for (final m in members)
            if (m.away) m,
        ],
      ),
    ];

    Widget tile(BuildContext context, IrcMember m) => Opacity(
      opacity: m.away ? 0.6 : 1,
      child: ListTile(
        dense: true,
        onTap: () {
          // Closes the slide-out list on phones; does nothing when the list
          // is pinned at the side.
          Scaffold.of(context).closeEndDrawer();
          onNickTap(m.nick);
        },
        leading: comfortable
            ? NickAvatar(nick: m.nick, size: 28, role: _role(m), away: m.away)
            : null,
        trailing: const Icon(Icons.more_horiz, size: 18),
        title: Text(
          '${m.topPrefix}${m.nick}',
          style: TextStyle(color: ChatColors.of(context).nickColor(m.nick)),
        ),
      ),
    );

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
          child: CustomScrollView(
            slivers: [
              for (final (title, list) in groups)
                if (list.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Semantics(
                        header: true,
                        child: Text(
                          '$title · ${list.length}',
                          style: TypeScale.meta.copyWith(
                            color: tokens.textMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) => tile(context, list[i]),
                  ),
                ],
            ],
          ),
        ),
      ],
    );
  }

  /// Owners, admins, ops and half-ops get the operator ring; voice the
  /// accent ring.
  static NickRole _role(IrcMember m) => nickRoleOf(m);

  static int _rank(IrcMember m) =>
      m.prefixes.isEmpty ? 99 : '~&@%+'.indexOf(m.topPrefix).abs();
}

/// Operators (and above) get the gold ring, voiced people the accent one.
NickRole nickRoleOf(IrcMember m) => m.prefixes.contains(RegExp('[~&@%]'))
    ? NickRole.op
    : m.prefixes.contains('+')
    ? NickRole.voiced
    : NickRole.member;

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

/// "bob is typing…" above the message box; nothing when nobody is.
class TypingLine extends StatelessWidget {
  const TypingLine({required this.nicks, super.key});

  final List<String> nicks;

  /// The words for [nicks]: one, two, or "Several people".
  static String text(List<String> nicks) => switch (nicks) {
    [] => '',
    [final a] => '$a is typing…',
    [final a, final b] => '$a and $b are typing…',
    _ => 'Several people are typing…',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final words = text(nicks);
    return AnimatedSize(
      duration: Motion.of(context, Motion.fast),
      alignment: Alignment.bottomLeft,
      child: words.isEmpty
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
                child: Text(
                  words,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TypeScale.meta.copyWith(
                    color: tokens.textMuted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
    );
  }
}

/// The back button on a phone chat, with how many other chats have new
/// messages (coral `@` when one of them mentions you), so a busy room
/// shows while you're in a private chat.
class _BackToRooms extends StatelessWidget {
  const _BackToRooms({required this.unread, this.onBack});

  final UnreadElsewhere unread;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final n = unread.chats;
    final label = n == 0
        ? 'Back to rooms'
        : 'Back to rooms, $n ${n == 1 ? 'chat' : 'chats'} with new messages'
              '${unread.mention ? ', one mentions you' : ''}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Back to rooms',
        child: InkResponse(
          onTap: onBack,
          radius: 24,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12, end: 4),
            // Large text shrinks the badge rather than overflowing.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              // At least 48 tall: an easy target.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 48),
                  const BackButtonIcon(),
                  if (n > 0) ...[
                    const SizedBox(width: 4),
                    UnreadBadge(count: n, mention: unread.mention),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
