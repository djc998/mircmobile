/// How you get around: bottom tabs on phones, a rail and rooms list on
/// small tablets, and a sidebar beside the chat on iPad and Mac, plus the
/// Mac's menus and keyboard shortcuts.
library;

import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/safety/content_filter.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/adaptive.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/conversation_row.dart';
import 'package:irc_client/core/ui/empty_state.dart';
import 'package:irc_client/core/ui/unread_badge.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/conversations.dart';
import 'package:irc_client/features/chat/application/panel_prefs.dart';
import 'package:irc_client/features/chat/presentation/change_nick_dialog.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/chat/presentation/find_in_chat.dart';
import 'package:irc_client/features/discovery/presentation/room_browser_screen.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/rooms/presentation/room_dialogs.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Phones are narrower than this: bottom tabs, chats full screen.
const double phoneMaxWidth = compactTitleBarMaxWidth;

/// The four places: the tabs on phones, the rail on small tablets, and
/// the sidebar's links on wide screens.
enum HomeTab {
  rooms('Rooms', Icons.forum_outlined, Icons.forum),
  discover('Discover', Icons.explore_outlined, Icons.explore),
  mentions('Mentions', Icons.alternate_email, Icons.alternate_email),
  you('You', Icons.person_outline, Icons.person);

  HomeTab(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// `10:15` today, `Yesterday`, else `Nov 18`.
String activityLabel(BuildContext context, DateTime? time, {DateTime? now}) {
  if (time == null) return '';
  final t = time.toLocal();
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return TimeOfDay.fromDateTime(t).format(context);
  if (day == DateTime(today.year, today.month, today.day - 1)) {
    return 'Yesterday';
  }
  return MaterialLocalizations.of(context).formatShortMonthDay(t);
}

/// The `/chat` route: picks the layout for the window's width.
class ChatShell extends ConsumerStatefulWidget {
  const ChatShell({super.key});

  @override
  ConsumerState<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends ConsumerState<ChatShell> {
  /// Phones: the tab showing; small tablets: the rail's choice; wide
  /// screens: what the main area shows when it isn't a chat.
  HomeTab _tab = HomeTab.rooms;

  /// Phones: the chat open full screen (its buffer key). It closes by
  /// itself when that chat is left or closed.
  String? _openKey;

  /// Wide screens: the main area shows [_tab] instead of the chat.
  bool _showingTab = false;

  ChatController get _controller => ref.read(chatControllerProvider.notifier);

  void _openChat() => setState(() {
    _openKey = ref.read(chatControllerProvider).activeKey;
    _showingTab = false;
    // Small tablets: Discover fills the screen, so go back to the list.
    if (_tab == HomeTab.discover) _tab = HomeTab.rooms;
  });

  /// Picks a conversation and shows it.
  void _open(String key) {
    _controller.selectBuffer(key);
    _openChat();
  }

  /// Phones: back from a chat to the tabs. The network's server tab
  /// becomes the active buffer so messages in the chat you left count as
  /// unread again.
  void _closeChat() {
    final active = ref.read(chatControllerProvider).activeBuffer;
    if (active != null && !active.isStatus) {
      _controller.selectBuffer(
        ChatState.bufferKey(active.networkId, statusBuffer),
      );
    }
    setState(() => _openKey = null);
  }

  void _showTab(HomeTab tab) => setState(() {
    _tab = tab;
    _openKey = null;
    _showingTab = true;
  });

  /// After a join from Discover: back to Rooms. The chat opens when the
  /// server confirms the join (or already has, for a room you're in).
  void _leaveDiscover() => setState(() {
    if (_tab == HomeTab.discover) _tab = HomeTab.rooms;
  });

  NetworkActions _actions(BuildContext context) => NetworkActions(
    browse: () => _showTab(HomeTab.discover),
    message: () => ChatScreen.promptPrivateMessage(context, _controller),
    join: () => ChatScreen.promptJoin(context, _controller),
    createRoom: () => showCreateRoomDialog(context, ref),
    appearance: () => context.push('/appearance'),
    closeNetwork: (id) => ChatScreen.closeNetwork(context, ref, id),
  );

  Future<void> _quickSwitch(BuildContext context) async {
    final key = await showQuickSwitcher(context);
    if (key != null) _open(key);
  }

  void _jumpTo(int index) {
    final order = sidebarOrder(
      ref.read(chatControllerProvider),
      ref.read(roomPrefsProvider),
    );
    if (index < order.length) _open(order[index].key);
  }

  void _find(BuildContext context) {
    final buffer = ref.read(chatControllerProvider).activeBuffer;
    if (buffer != null) unawaited(showFindInChat(context, buffer));
  }

  @override
  Widget build(BuildContext context) {
    // A room you join, a chat someone opens with you, or a pick in the
    // room browser shows that chat.
    ref.listen(chatControllerProvider.select((s) => s.activeKey), (prev, next) {
      if (prev == next) return;
      final buffer = ref.read(chatControllerProvider).buffers[next];
      if (buffer != null && !buffer.isStatus) _openChat();
    });

    final width = MediaQuery.sizeOf(context).width;
    final Widget body;
    if (width < phoneMaxWidth) {
      body = _phone(context);
    } else if (width < pinnedPanelsMinWidth) {
      body = _rail(context);
    } else {
      body = _sidebar(context);
    }
    return _MacMenus(
      onQuickSwitch: () => unawaited(_quickSwitch(context)),
      onJumpTo: _jumpTo,
      onFind: () => _find(context),
      onNewMessage: () =>
          unawaited(ChatScreen.promptPrivateMessage(context, _controller)),
      onJoin: () => unawaited(ChatScreen.promptJoin(context, _controller)),
      onBrowse: () => _showTab(HomeTab.discover),
      onMentions: () => _showTab(HomeTab.mentions),
      onAddNetwork: () => context.go('/'),
      onAppearance: () => unawaited(context.push('/appearance')),
      onSettings: () => unawaited(context.push('/settings')),
      onToggleSidebar: () =>
          unawaited(ref.read(panelPrefsProvider.notifier).toggleChats()),
      onTogglePeople: () =>
          unawaited(ref.read(panelPrefsProvider.notifier).togglePeople()),
      onCloseChat: () {
        final b = ref.read(chatControllerProvider).activeBuffer;
        if (b != null && !b.isStatus) _controller.closeBuffer(b.key);
      },
      child: body,
    );
  }

  /// The view for a tab, without the chat.
  Widget _tabView(BuildContext context, HomeTab tab, {bool list = false}) =>
      switch (tab) {
        HomeTab.rooms => RoomsHome(
          onOpen: _open,
          onBrowse: () => _showTab(HomeTab.discover),
          compact: list,
        ),
        HomeTab.discover => RoomBrowserScreen(onDone: _leaveDiscover),
        HomeTab.mentions => MentionsView(onOpen: _open),
        HomeTab.you => YouView(
          actions: _actions(context),
          onOpenServer: _openChat,
        ),
      };

  // Phones: tabs, and a chat full screen on top.
  Widget _phone(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final active = state.activeBuffer;
    if (active != null && _openKey == state.activeKey) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _closeChat();
        },
        child: ChatScreen(layout: ChatLayout.phone, onBack: _closeChat),
      );
    }
    return Scaffold(
      body: _tabView(context, _tab),
      bottomNavigationBar: _TabBar(
        selected: _tab,
        onSelect: _showTab,
        state: state,
      ),
    );
  }

  // 600–899 pt: rail, list, chat.
  Widget _rail(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final tokens = AppTokens.of(context);
    final Widget main;
    if (_tab == HomeTab.discover) {
      main = Expanded(child: RoomBrowserScreen(onDone: _leaveDiscover));
    } else {
      main = Expanded(
        child: Row(
          children: [
            SizedBox(
              width: 320,
              child: Material(
                color: tokens.surfaceRaised,
                child: SafeArea(
                  right: false,
                  child: _tabView(context, _tab, list: true),
                ),
              ),
            ),
            const VerticalDivider(width: 1),
            const Expanded(child: ChatScreen(layout: ChatLayout.rail)),
          ],
        ),
      );
    }
    return Scaffold(
      body: Row(
        children: [
          SafeArea(
            right: false,
            child: NavigationRail(
              selectedIndex: _tab.index,
              labelType: NavigationRailLabelType.all,
              onDestinationSelected: (i) => _showTab(HomeTab.values[i]),
              destinations: [
                for (final t in HomeTab.values)
                  NavigationRailDestination(
                    icon: _TabIcon(tab: t, state: state, selected: false),
                    selectedIcon: _TabIcon(
                      tab: t,
                      state: state,
                      selected: true,
                    ),
                    label: Text(t.label),
                  ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          main,
        ],
      ),
    );
  }

  // 900 pt and wider: sidebar, then the chat (with People) or a tab's view.
  Widget _sidebar(BuildContext context) {
    final pinned = ref.watch(panelPrefsProvider).chatsPinned;
    final state = ref.watch(chatControllerProvider);
    final showChat = !_showingTab && state.activeBuffer != null;
    return Scaffold(
      body: Row(
        children: [
          if (pinned) ...[
            SizedBox(
              width: 264,
              child: Sidebar(
                current: showChat ? null : _tab,
                onOpen: _open,
                onShow: _showTab,
                onQuickSwitch: () => unawaited(_quickSwitch(context)),
              ),
            ),
            const VerticalDivider(width: 1),
          ],
          Expanded(
            child: showChat
                ? const ChatScreen()
                : Scaffold(
                    appBar: pinned
                        ? null
                        : AppBar(
                            leading: IconButton(
                              tooltip: 'Show servers and chats',
                              icon: const Icon(Icons.menu),
                              onPressed: () => unawaited(
                                ref
                                    .read(panelPrefsProvider.notifier)
                                    .toggleChats(),
                              ),
                            ),
                          ),
                    body: SafeArea(child: _tabView(context, _tab)),
                  ),
          ),
        ],
      ),
    );
  }
}

/// An icon for a tab, with the Mentions badge and your avatar on You.
class _TabIcon extends ConsumerWidget {
  const _TabIcon({
    required this.tab,
    required this.state,
    required this.selected,
  });

  final HomeTab tab;
  final ChatState state;
  final bool selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final icon = Icon(selected ? tab.selectedIcon : tab.icon);
    switch (tab) {
      case HomeTab.mentions:
        final n = unreadMentionChats(state, ref.watch(roomPrefsProvider));
        return n == 0
            ? icon
            : Badge(
                label: Text('$n'),
                backgroundColor: AppTokens.of(context).mention,
                textColor: AppTokens.of(context).onMention,
                child: icon,
              );
      case HomeTab.you:
        final nick = state.activeNetwork?.nick ?? '';
        return nick.isEmpty
            ? icon
            : ExcludeSemantics(child: NickAvatar(nick: nick, size: 24));
      case HomeTab.rooms || HomeTab.discover:
        return icon;
    }
  }
}

class _TabBar extends ConsumerWidget {
  const _TabBar({
    required this.selected,
    required this.onSelect,
    required this.state,
  });

  final HomeTab selected;
  final void Function(HomeTab) onSelect;
  final ChatState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mentions = unreadMentionChats(state, ref.watch(roomPrefsProvider));
    return NavigationBar(
      selectedIndex: selected.index,
      onDestinationSelected: (i) => onSelect(HomeTab.values[i]),
      destinations: [
        for (final t in HomeTab.values)
          NavigationDestination(
            icon: _TabIcon(tab: t, state: state, selected: false),
            selectedIcon: _TabIcon(tab: t, state: state, selected: true),
            label: t.label,
            tooltip: t == HomeTab.mentions && mentions > 0
                ? '${t.label}, $mentions unread'
                : t.label,
          ),
      ],
    );
  }
}

/// Rooms home: search, favorite tiles and every open chat by latest
/// activity. Swipe a row right to favorite it, left to leave or close it.
class RoomsHome extends ConsumerStatefulWidget {
  const RoomsHome({
    required this.onOpen,
    required this.onBrowse,
    this.compact = false,
    super.key,
  });

  final void Function(String key) onOpen;

  /// Opens Discover (the room browser).
  final VoidCallback onBrowse;

  /// Beside the chat (small tablets): a smaller title.
  final bool compact;

  @override
  ConsumerState<RoomsHome> createState() => _RoomsHomeState();
}

class _RoomsHomeState extends ConsumerState<RoomsHome> {
  String _query = '';

  bool _matches(String name) {
    final q = _query.trim().toLowerCase();
    return q.isEmpty || name.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final prefs = ref.watch(roomPrefsProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final tokens = AppTokens.of(context);
    final conversations = activeConversations(state)
        .where((c) => _matches(c.name))
        .toList();
    final favorites = [
      for (final net in state.networks.values)
        for (final room in prefs.favoritesFor(net.id))
          if (_matches(room))
            (
              net: net,
              room: room,
              buffer: state.buffers[ChatState.bufferKey(net.id, room)],
            ),
    ];
    final multi = state.networks.length > 1;
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: tokens.textMuted,
          ),
        ),
      ),
    );

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20, widget.compact ? 12 : 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      'Rooms',
                      style: widget.compact
                          ? TypeScale.title.copyWith(color: tokens.textPrimary)
                          : const TextStyle(
                              fontSize: 30,
                              height: 36 / 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ).copyWith(color: tokens.textPrimary),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Browse rooms',
                  icon: const Icon(Icons.travel_explore),
                  onPressed: widget.onBrowse,
                ),
                IconButton(
                  tooltip: 'Join a room',
                  icon: const Icon(Icons.add_comment_outlined),
                  onPressed: () =>
                      unawaited(ChatScreen.promptJoin(context, controller)),
                ),
                IconButton(
                  tooltip: 'New private message',
                  style: IconButton.styleFrom(
                    backgroundColor: tokens.surfaceOverlay,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => unawaited(
                    ChatScreen.promptPrivateMessage(context, controller),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search rooms and people',
                isDense: true,
                filled: true,
                // The list pane is already surfaceRaised.
                fillColor: widget.compact
                    ? tokens.surface
                    : tokens.surfaceRaised,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(
                    tokens.radius(Radii.card),
                  ),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (favorites.isNotEmpty) ...[
            section('Favorites'),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final f in favorites)
                    FavoriteTile(
                      name: f.room,
                      isRoom: true,
                      joined: f.buffer != null,
                      unread: f.buffer?.unread ?? 0,
                      mention: f.buffer?.mentioned ?? false,
                      onTap: f.buffer != null
                          ? () => widget.onOpen(f.buffer!.key)
                          : f.net.isConnected
                          ? () =>
                                controller.joinRoom(f.room, networkId: f.net.id)
                          : () {},
                    ),
                ],
              ),
            ),
          ],
          section('Active now'),
          if (conversations.isEmpty)
            if (_query.trim().isEmpty && state.networks.isNotEmpty)
              // Step 3 of the welcome: find a first room.
              EmptyState(
                icon: Icons.explore_outlined,
                title: 'Find your first room',
                message:
                    'Discover lists every room on your networks. Join one '
                    'with a tap.',
                action: 'Discover rooms',
                onAction: widget.onBrowse,
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: Text(
                  _query.trim().isNotEmpty
                      ? 'No rooms or chats match "${_query.trim()}".'
                      : 'Not connected to a network yet.',
                  style: TextStyle(color: tokens.textMuted),
                ),
              ),
          for (final c in conversations)
            _SwipeRow(
              key: ValueKey(c.key),
              conversation: c,
              favorite: c.isRoom && prefs.isFavorite(c.network.id, c.name),
              child: ConversationRow(
                avatars:
                    ref.watch(appearanceProvider).density ==
                    ChatDensity.comfortable,
                name: c.name,
                isRoom: c.isRoom,
                network: multi ? shortNetworkName(c.network.label) : null,
                time: activityLabel(context, c.lastActivity),
                preview: ContentFilter.clean(context, c.preview),
                unread: c.buffer.unread,
                mention: c.buffer.mentioned,
                favorite: c.isRoom && prefs.isFavorite(c.network.id, c.name),
                muted: prefs.isMuted(c.network.id, c.name),
                selected: widget.compact && c.key == state.activeKey,
                onTap: () => widget.onOpen(c.key),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mute, favorite and leave for one chat: long-press a row in Rooms home,
/// or right-click it in the sidebar.
Future<void> showConversationMenu(
  BuildContext context,
  WidgetRef ref,
  ConversationInfo c, {
  Offset? position,
}) {
  final prefs = ref.read(roomPrefsProvider);
  final notifier = ref.read(roomPrefsProvider.notifier);
  final muted = prefs.isMuted(c.network.id, c.name);
  final favorite = c.isRoom && prefs.isFavorite(c.network.id, c.name);
  return showActionMenu(
    context,
    title: c.name,
    position: position,
    actions: [
      MenuAction(
        icon: muted
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
        label: muted ? 'Unmute ${c.name}' : 'Mute ${c.name}',
        onSelected: () => notifier.toggleMute(c.network.id, c.name),
      ),
      if (c.isRoom)
        MenuAction(
          icon: favorite ? Icons.star_border : Icons.star,
          label: favorite
              ? 'Remove ${c.name} from favorites'
              : 'Add ${c.name} to favorites',
          onSelected: () => notifier.toggleFavorite(c.network.id, c.name),
        ),
      MenuAction(
        icon: Icons.logout,
        label: c.isRoom ? 'Leave ${c.name}' : 'Close chat with ${c.name}',
        destructive: true,
        onSelected: () =>
            ref.read(chatControllerProvider.notifier).closeBuffer(c.key),
      ),
    ],
  );
}

/// Swipe right to favorite or unfavorite a room; left to leave the room or
/// close the chat.
class _SwipeRow extends ConsumerWidget {
  const _SwipeRow({
    required this.conversation,
    required this.favorite,
    required this.child,
    super.key,
  });

  final ConversationInfo conversation;
  final bool favorite;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final c = conversation;
    final leave = c.isRoom ? 'Leave ${c.name}' : 'Close chat with ${c.name}';
    final fav = favorite
        ? 'Remove ${c.name} from favorites'
        : 'Add ${c.name} to favorites';
    void toggleFavorite() => ref
        .read(roomPrefsProvider.notifier)
        .toggleFavorite(c.network.id, c.name);
    void close() =>
        ref.read(chatControllerProvider.notifier).closeBuffer(c.key);
    final muted = ref.watch(roomPrefsProvider).isMuted(c.network.id, c.name);
    final mute = muted ? 'Unmute ${c.name}' : 'Mute ${c.name}';
    void toggleMute() =>
        ref.read(roomPrefsProvider.notifier).toggleMute(c.network.id, c.name);

    Future<void> menu([Offset? at]) =>
        showConversationMenu(context, ref, c, position: at);
    Widget background(
      IconData icon,
      String label,
      Color bg,
      Color fg,
      bool end,
    ) => Container(
      color: bg,
      alignment: end
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: mute): toggleMute,
        if (c.isRoom) CustomSemanticsAction(label: fav): toggleFavorite,
        CustomSemanticsAction(label: leave): close,
      },
      child: GestureDetector(
        onLongPress: () => unawaited(menu()),
        onSecondaryTapUp: (d) => unawaited(menu(d.globalPosition)),
        child: Dismissible(
          key: ValueKey('swipe-${c.key}'),
          direction: c.isRoom
              ? DismissDirection.horizontal
              : DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              toggleFavorite();
            } else {
              close();
            }
            // The list rebuilds without the row (leave) or with the new star.
            return false;
          },
          background: background(
            favorite ? Icons.star_border : Icons.star,
            favorite ? 'Unfavorite' : 'Favorite',
            tokens.accentSoft,
            tokens.onAccentSoft,
            false,
          ),
          secondaryBackground: background(
            Icons.logout,
            c.isRoom ? 'Leave' : 'Close',
            tokens.mention,
            tokens.onMention,
            true,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Every message that mentions you, newest first; tap one to open its chat.
class MentionsView extends ConsumerWidget {
  const MentionsView({required this.onOpen, super.key});

  final void Function(String key) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final tokens = AppTokens.of(context);
    final chat = ChatColors.of(context);
    final mentions = mentionsIn(state);
    return SafeArea(
      bottom: false,
      child: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Semantics(
              header: true,
              child: Text(
                'Mentions',
                style: TypeScale.title.copyWith(color: tokens.textPrimary),
              ),
            ),
          ),
          if (mentions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Messages that mention your nickname show up here.',
                style: TextStyle(color: tokens.textMuted),
              ),
            ),
          for (final m in mentions)
            ListTile(
              leading: NickAvatar(nick: m.line.sender!, size: 40),
              title: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: m.line.sender,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: chat.nickColor(m.line.sender!),
                      ),
                    ),
                    TextSpan(
                      text: m.conversation.isRoom
                          ? ' in ${m.conversation.name}'
                          : ' (private)',
                      style: TextStyle(color: tokens.textMuted),
                    ),
                  ],
                ),

                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                m.line.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                activityLabel(context, m.line.time),
                style: TypeScale.meta.copyWith(color: tokens.textMuted),
              ),
              onTap: () => onOpen(m.conversation.key),
            ),
        ],
      ),
    );
  }
}

/// You: your nickname and networks, and the app's settings.
class YouView extends ConsumerWidget {
  const YouView({required this.actions, this.onOpenServer, super.key});

  final NetworkActions actions;
  final VoidCallback? onOpenServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final tokens = AppTokens.of(context);
    final net = state.activeNetwork ?? state.networks.values.firstOrNull;
    final connected = state.connectedNetworks.length;
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                if (net != null) NickAvatar(nick: net.nick, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        net?.nick ?? 'You',
                        style: TypeScale.title.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                      Text(
                        connected == 1
                            ? 'Connected to 1 network'
                            : 'Connected to $connected networks',
                        style: TypeScale.meta.copyWith(color: tokens.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NetworksPanel(
              state: state,
              prefs: ref.watch(roomPrefsProvider),
              controller: ref.read(chatControllerProvider.notifier),
              onChangeNick: (id) =>
                  showChangeNickDialog(context, ref, networkId: id),
              actions: actions,
              onOpenServer: onOpenServer,
            ),
          ),
        ],
      ),
    );
  }
}

/// The wide-screen sidebar: links to Home, Discover and Mentions, the jump
/// box, your rooms by section, and you at the bottom.
class Sidebar extends ConsumerWidget {
  const Sidebar({
    required this.onOpen,
    required this.onShow,
    required this.onQuickSwitch,
    this.current,
    super.key,
  });

  /// The tab the main area shows, or null when it shows a chat.
  final HomeTab? current;
  final void Function(String key) onOpen;
  final void Function(HomeTab) onShow;
  final VoidCallback onQuickSwitch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final prefs = ref.watch(roomPrefsProvider);
    final tokens = AppTokens.of(context);
    final sections = sidebarSections(state, prefs);
    final multi = state.networks.length > 1;
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final mentions = unreadMentionChats(state, prefs);
    final net = state.activeNetwork ?? state.networks.values.firstOrNull;
    final connected = state.connectedNetworks.length;

    Widget link(HomeTab tab, String label, IconData icon, {int badge = 0}) =>
        ListTile(
          dense: true,
          selected: current == tab,
          selectedTileColor: Color.alphaBlend(
            tokens.accentSoft,
            tokens.surfaceRaised,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radius(8)),
          ),
          leading: Icon(icon, size: 20),
          title: Text(label),
          trailing: badge > 0
              ? UnreadBadge(count: badge, mention: tab == HomeTab.mentions)
              : null,
          onTap: () => onShow(tab),
        );

    return Material(
      color: tokens.surfaceRaised,
      child: SafeArea(
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: BorderRadius.circular(tokens.radius(9)),
                    ),
                    child: Text(
                      '#',
                      style: TextStyle(
                        color: tokens.onAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    appName,
                    style: TypeScale.heading.copyWith(
                      color: tokens.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Semantics(
                button: true,
                label: 'Jump to a room or person',
                excludeSemantics: true,
                child: InkWell(
                  onTap: onQuickSwitch,
                  borderRadius: BorderRadius.circular(tokens.radius(8)),
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      border: Border.all(color: tokens.line),
                      borderRadius: BorderRadius.circular(tokens.radius(8)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 18, color: tokens.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Jump to a room or person',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                        Text(
                          isMac ? '⌘K' : 'Ctrl+K',
                          style: TypeScale.meta.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  link(HomeTab.rooms, 'Home', Icons.home_outlined),
                  link(
                    HomeTab.discover,
                    'Discover rooms',
                    Icons.explore_outlined,
                  ),
                  link(
                    HomeTab.mentions,
                    'Mentions',
                    Icons.alternate_email,
                    badge: mentions,
                  ),
                  for (final MapEntry(key: section, value: list)
                      in sections.entries)
                    if (list.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                        child: Semantics(
                          header: true,
                          child: Text(
                            section.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: tokens.textMuted,
                            ),
                          ),
                        ),
                      ),
                      for (final c in list)
                        GestureDetector(
                          onSecondaryTapUp: (d) => unawaited(
                            showConversationMenu(
                              context,
                              ref,
                              c,
                              position: d.globalPosition,
                            ),
                          ),
                          onLongPress: () =>
                              unawaited(showConversationMenu(context, ref, c)),
                          child: ConversationRow(
                            avatars:
                                ref.watch(appearanceProvider).density ==
                                ChatDensity.comfortable,
                            dense: true,
                            name: c.name,
                            isRoom: c.isRoom,
                            network: multi
                                ? shortNetworkName(c.network.label)
                                : null,
                            unread: c.buffer.unread,
                            mention: c.buffer.mentioned,
                            muted: prefs.isMuted(c.network.id, c.name),
                            selected:
                                current == null && c.key == state.activeKey,
                            onTap: () => onOpen(c.key),
                          ),
                        ),
                    ],
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading:
                  net == null ||
                      ref.watch(appearanceProvider).density ==
                          ChatDensity.compact
                  ? const Icon(Icons.person_outline)
                  : NickAvatar(nick: net.nick, size: 32),
              title: Text(net?.nick ?? 'You'),
              subtitle: Text(
                connected == 1
                    ? 'Connected to 1 network'
                    : 'Connected to $connected networks',
              ),
              selected: current == HomeTab.you,
              trailing: net == null
                  ? null
                  : Icon(
                      Icons.circle,
                      size: 10,
                      color: switch (net.status) {
                        IrcConnectionStatus.connected => tokens.success,
                        IrcConnectionStatus.disconnected => tokens.textMuted,
                        _ => tokens.op,
                      },
                    ),
              onTap: () => onShow(HomeTab.you),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cmd+K: type part of a name, Enter (or tap) to open it. Returns the
/// conversation's key.
Future<String?> showQuickSwitcher(BuildContext context) => showDialog<String>(
  context: context,
  builder: (_) => const _QuickSwitcher(),
);

class _QuickSwitcher extends ConsumerStatefulWidget {
  const _QuickSwitcher();

  @override
  ConsumerState<_QuickSwitcher> createState() => _QuickSwitcherState();
}

class _QuickSwitcherState extends ConsumerState<_QuickSwitcher> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider);
    final matches = switcherMatches(state, _query);
    final multi = state.networks.length > 1;
    return Dialog(
      alignment: const Alignment(0, -0.5),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Jump to a room or person',
                ),
                onChanged: (v) => setState(() => _query = v),
                onSubmitted: (_) {
                  if (matches.isNotEmpty) {
                    Navigator.pop(context, matches.first.key);
                  }
                },
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                children: [
                  if (matches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Nothing matches.'),
                    ),
                  for (final c in matches)
                    ConversationRow(
                      avatars:
                          ref.watch(appearanceProvider).density ==
                          ChatDensity.comfortable,
                      dense: true,
                      name: c.name,
                      isRoom: c.isRoom,
                      network: multi ? shortNetworkName(c.network.label) : null,
                      unread: c.buffer.unread,
                      mention: c.buffer.mentioned,
                      onTap: () => Navigator.pop(context, c.key),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Mac's menu bar and the keyboard shortcuts (Cmd on a Mac, Ctrl on
/// other computers).
class _MacMenus extends StatelessWidget {
  const _MacMenus({
    required this.child,
    required this.onQuickSwitch,
    required this.onJumpTo,
    required this.onFind,
    required this.onNewMessage,
    required this.onJoin,
    required this.onBrowse,
    required this.onMentions,
    required this.onAddNetwork,
    required this.onAppearance,
    required this.onSettings,
    required this.onToggleSidebar,
    required this.onTogglePeople,
    required this.onCloseChat,
  });

  final Widget child;
  final VoidCallback onQuickSwitch;
  final void Function(int index) onJumpTo;
  final VoidCallback onFind;
  final VoidCallback onNewMessage;
  final VoidCallback onJoin;
  final VoidCallback onBrowse;
  final VoidCallback onMentions;
  final VoidCallback onAddNetwork;
  final VoidCallback onAppearance;
  final VoidCallback onSettings;
  final VoidCallback onToggleSidebar;
  final VoidCallback onTogglePeople;
  final VoidCallback onCloseChat;

  static const List<LogicalKeyboardKey> _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final isMac = platform == TargetPlatform.macOS;
    final desktop = switch (platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    if (!desktop) return child;
    SingleActivator key(
      LogicalKeyboardKey k, {
      bool shift = false,
      bool alt = false,
      bool ctrl = false,
    }) => SingleActivator(
      k,
      meta: isMac,
      control: !isMac || ctrl,
      shift: shift,
      alt: alt,
    );

    final quick = key(LogicalKeyboardKey.keyK);
    final find = key(LogicalKeyboardKey.keyF);
    final message = key(LogicalKeyboardKey.keyN);
    final join = key(LogicalKeyboardKey.keyJ);
    final browse = key(LogicalKeyboardKey.keyB, shift: true);
    final mentions = key(LogicalKeyboardKey.keyM, shift: true);
    final sidebar = key(LogicalKeyboardKey.keyS, ctrl: true);
    final people = key(LogicalKeyboardKey.keyP, alt: true);
    final close = key(LogicalKeyboardKey.keyW);
    final settings = key(LogicalKeyboardKey.comma);

    final shortcuts = CallbackShortcuts(
      bindings: {
        quick: onQuickSwitch,
        find: onFind,
        message: onNewMessage,
        join: onJoin,
        browse: onBrowse,
        mentions: onMentions,
        sidebar: onToggleSidebar,
        people: onTogglePeople,
        close: onCloseChat,
        settings: onSettings,
        for (final (i, d) in _digits.indexed) key(d): () => onJumpTo(i),
      },
      child: Focus(autofocus: true, child: child),
    );
    if (!isMac) return shortcuts;

    PlatformMenuItem item(
      String label,
      VoidCallback onSelected, [
      MenuSerializableShortcut? shortcut,
    ]) => PlatformMenuItem(
      label: label,
      shortcut: shortcut,
      onSelected: onSelected,
    );
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: appName,
          menus: [
            PlatformMenuItemGroup(
              members: [
                const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.about,
                ),
                item('Settings…', onSettings, settings),
                item('Appearance…', onAppearance),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.servicesSubmenu,
                ),
              ],
            ),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            const PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.quit,
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            item('New Private Message…', onNewMessage, message),
            item('Join a Room…', onJoin, join),
            item('Add a Network…', onAddNetwork),
            PlatformMenuItemGroup(
              members: [item('Close Chat', onCloseChat, close)],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [item('Find in Chat…', onFind, find)],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            item('Show or Hide Sidebar', onToggleSidebar, sidebar),
            item('Show or Hide People', onTogglePeople, people),
            item('Mentions', onMentions, mentions),
            item('Discover Rooms', onBrowse, browse),
            const PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Room',
          menus: [
            item('Jump to a Room or Person…', onQuickSwitch, quick),
            PlatformMenuItemGroup(
              members: [
                for (final (i, d) in _digits.indexed)
                  item('Go to Chat ${i + 1}', () => onJumpTo(i), key(d)),
              ],
            ),
          ],
        ),
        const PlatformMenu(
          label: 'Window',
          menus: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
      child: shortcuts,
    );
  }
}
