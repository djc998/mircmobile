import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/empty_state.dart';
import 'package:irc_client/core/ui/room_card.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/conversations.dart';
import 'package:irc_client/features/discovery/domain/room_category.dart';
import 'package:irc_client/features/discovery/domain/room_filter.dart';
import 'package:irc_client/features/discovery/presentation/room_preview.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/rooms/presentation/room_dialogs.dart';
import 'package:material_ui/material_ui.dart';

/// Discover: every room on every connected network as cards, with
/// category chips, search, a network filter, favorites, size and sort.
/// Tapping a card opens a preview; Join becomes Open for rooms you're in.
class RoomBrowserScreen extends ConsumerStatefulWidget {
  const RoomBrowserScreen({this.onDone, super.key});

  /// Called after joining or creating a room when the browser is a tab
  /// (Discover) rather than its own page, so the shell can leave it.
  final VoidCallback? onDone;

  @override
  ConsumerState<RoomBrowserScreen> createState() => _RoomBrowserScreenState();
}

class _RoomBrowserScreenState extends ConsumerState<RoomBrowserScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _minUsers = 0;
  RoomSort _sort = RoomSort.mostPeople;
  bool _favoritesOnly = false;
  DiscoverFilter _category = DiscoverFilter.popular;

  /// Only show rooms from this network; null shows every network.
  String? _networkId;

  @override
  void initState() {
    super.initState();
    // Fetch on first open; later opens reuse the cached lists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatControllerProvider.notifier).fetchMissingRooms();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _join(String networkId, String name) {
    ref
        .read(chatControllerProvider.notifier)
        .joinRoom(name, networkId: networkId);
    final done = widget.onDone;
    if (done != null) {
      done();
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chat');
    }
  }

  /// Filters that differ from the defaults, for the badge on Filters.
  int get _activeFilters =>
      (_favoritesOnly ? 1 : 0) +
      (_minUsers != 0 ? 1 : 0) +
      (_sort != RoomSort.mostPeople ? 1 : 0);

  /// Favorites only, room size and sort order, in a sheet.
  Future<void> _showFilters() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheet) => StatefulBuilder(
      builder: (sheet, setSheet) {
        void update(VoidCallback change) {
          setState(change);
          setSheet(() {});
        }

        Widget label(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          child: Text(text, style: Theme.of(sheet).textTheme.titleSmall),
        );
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.star_outline),
                  title: const Text('Favorites only'),
                  value: _favoritesOnly,
                  onChanged: (v) => update(() => _favoritesOnly = v),
                ),
                label('Room size'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final min in roomSizeFilters)
                      ChoiceChip(
                        label: Text(min == 0 ? 'Any size' : '$min+ people'),
                        selected: _minUsers == min,
                        onSelected: (_) => update(() => _minUsers = min),
                      ),
                  ],
                ),
                label('Sort'),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Most people'),
                      selected: _sort == RoomSort.mostPeople,
                      onSelected: (_) =>
                          update(() => _sort = RoomSort.mostPeople),
                    ),
                    ChoiceChip(
                      label: const Text('A–Z'),
                      selected: _sort == RoomSort.name,
                      onSelected: (_) => update(() => _sort = RoomSort.name),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(sheet),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  /// Whether you're in [name] on [networkId] (the server confirmed the
  /// join; a chat restored from history doesn't count).
  bool _inRoom(ChatState state, String networkId, String name) =>
      state.buffers.containsKey(ChatState.bufferKey(networkId, name)) &&
      state.networks[networkId]?.client.channel(name) != null;

  /// Opens a room you're already in, or joins it.
  void _openOrJoin(String networkId, String name) {
    final key = ChatState.bufferKey(networkId, name);
    if (_inRoom(ref.read(chatControllerProvider), networkId, name)) {
      ref.read(chatControllerProvider.notifier).selectBuffer(key);
      final done = widget.onDone;
      if (done != null) {
        done();
      } else if (context.canPop()) {
        context.pop();
      } else {
        context.go('/chat');
      }
      return;
    }
    _join(networkId, name);
  }

  @override
  Widget build(BuildContext context) {
    // Networks that finish logging in while the browser is open get
    // fetched too.
    ref.listen(
      chatControllerProvider.select((s) => s.connectedNetworks.length),
      (_, _) => ref.read(chatControllerProvider.notifier).fetchMissingRooms(),
    );
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final tokens = AppTokens.of(context);
    final connected = state.connectedNetworks;
    final networks = state.networks.values.toList();
    final multi = networks.length > 1;
    final filterId = state.networks.containsKey(_networkId) ? _networkId : null;
    final prefs = ref.watch(roomPrefsProvider);

    // Rooms in scope (network filter), then category, favorites, search,
    // size and sort on top.
    final inScope = [
      for (final r in state.allRooms)
        if (filterId == null || r.network.id == filterId) r,
    ];
    final byEntry = Map<ChannelListEntry, NetworkRoom>.identity();
    for (final r in inScope) {
      if (_favoritesOnly && !prefs.isFavorite(r.network.id, r.entry.name)) {
        continue;
      }
      if (!_category.matches(r.entry)) continue;
      byEntry[r.entry] = r;
    }
    final rooms = [
      for (final e in filterRooms(
        byEntry.keys.toList(),
        query: _query,
        minUsers: _minUsers,
        sort: _sort,
      ))
        byEntry[e]!,
    ];

    final recents = [
      for (final n in connected)
        if (filterId == null || n.id == filterId)
          for (final room in prefs.recentsFor(n.id)) (network: n, room: room),
    ];
    final loading = state.roomsLoading;
    final where = networks.length == 1
        ? 'Rooms on ${networks.first.label}'
        : multi
        ? 'Rooms on ${networks.length} networks'
        : 'Rooms';

    Widget chipRow(List<Widget> chips, {EdgeInsets? padding}) =>
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: padding ?? const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              for (final c in chips)
                Padding(padding: const EdgeInsets.only(right: 8), child: c),
            ],
          ),
        );

    return Scaffold(
      floatingActionButton: connected.isEmpty
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Create room'),
              onPressed: () async {
                final created = await showCreateRoomDialog(context, ref);
                if (!created || !context.mounted) return;
                if (widget.onDone != null) {
                  widget.onDone!();
                } else if (context.canPop()) {
                  context.pop();
                }
              },
            ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  if (context.canPop())
                    const BackButton()
                  else
                    const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Discover',
                            style: const TextStyle(
                              fontSize: 30,
                              height: 36 / 30,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ).copyWith(color: tokens.textPrimary),
                          ),
                        ),
                        Text(
                          where,
                          style: TypeScale.meta.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Badge(
                    isLabelVisible: _activeFilters > 0,
                    label: Text('$_activeFilters'),
                    child: IconButton(
                      tooltip: 'Filters',
                      icon: const Icon(Icons.tune),
                      onPressed: () => unawaited(_showFilters()),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: connected.isNotEmpty && !loading
                        ? () => controller.fetchRooms(filterId)
                        : null,
                  ),
                ],
              ),
            ),
            if (multi)
              chipRow([
                ChoiceChip(
                  avatar: const Icon(Icons.hub_outlined, size: 18),
                  label: const Text('All networks'),
                  selected: filterId == null,
                  onSelected: (_) => setState(() => _networkId = null),
                ),
                for (final n in networks)
                  ChoiceChip(
                    label: Text(n.label),
                    selected: filterId == n.id,
                    onSelected: (_) => setState(() => _networkId = n.id),
                  ),
              ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _search,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: inScope.isEmpty
                      ? 'Search rooms and topics'
                      : 'Search ${groupedCount(inScope.length)} rooms',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: tokens.surfaceRaised,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      tokens.radius(Radii.card),
                    ),
                    borderSide: BorderSide(color: tokens.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(
                      tokens.radius(Radii.card),
                    ),
                    borderSide: BorderSide(color: tokens.line),
                  ),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                          }),
                        ),
                ),
              ),
            ),
            // Categories, guessed from each room's name and topic.
            chipRow([
              for (final c in DiscoverFilter.values)
                ChoiceChip(
                  label: Text(c.label),
                  showCheckmark: false,
                  selected: _category == c,
                  selectedColor: tokens.accent,
                  labelStyle: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: _category == c
                        ? tokens.onAccent
                        : tokens.textPrimary,
                  ),
                  onSelected: (_) => setState(() => _category = c),
                ),
            ], padding: const EdgeInsets.fromLTRB(16, 12, 16, 0)),
            if (recents.isNotEmpty && _query.isEmpty)
              chipRow([
                const Text('Recent:'),
                for (final r in recents)
                  ActionChip(
                    avatar: const Icon(Icons.history, size: 18),
                    label: Text(
                      multi ? '${r.room} · ${r.network.label}' : r.room,
                    ),
                    onPressed: () => _openOrJoin(r.network.id, r.room),
                  ),
              ]),
            const SizedBox(height: 8),
            if (loading) const LinearProgressIndicator(),
            Expanded(
              child: _body(
                context,
                state,
                inScope.length,
                rooms,
                controller,
                prefs,
                multi: multi,
                filterId: filterId,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    ChatState state,
    int total,
    List<NetworkRoom> rooms,
    ChatController controller,
    RoomPrefs prefs, {
    required bool multi,
    required String? filterId,
  }) {
    final tokens = AppTokens.of(context);
    final scope = [
      for (final n in state.networks.values)
        if (filterId == null || n.id == filterId) n,
    ];
    final anyConnected = scope.any((n) => n.isConnected);
    final errors = [
      for (final n in scope)
        if (n.roomsError case final error? when n.rooms.isEmpty)
          if (multi) '${n.label}: $error' else error,
    ];
    if (!anyConnected && total == 0) {
      return const EmptyState(
        icon: Icons.cloud_off,
        title: 'Not connected',
        message: 'Connect to a network to see its rooms.',
      );
    }
    if (errors.isNotEmpty && total == 0) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'No room list',
        message:
            "The server didn't send its room list: ${errors.join('\n')}\n"
            'Try again in a minute.',
        action: 'Try again',
        onAction: () => controller.fetchRooms(filterId),
      );
    }
    if (state.roomsLoading && total == 0) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Text(
            'Fetching rooms… big networks can take a few seconds.',
            style: TypeScale.meta.copyWith(color: tokens.textMuted),
          ),
          const SizedBox(height: 10),
          const SkeletonList(label: 'Fetching rooms'),
        ],
      );
    }
    if (rooms.isEmpty) {
      return EmptyState(
        icon: Icons.search_off,
        title: total == 0 ? 'No rooms yet' : 'Nothing here',
        message: total == 0
            ? 'Tap refresh to load them.'
            : _favoritesOnly
            ? 'No favorites here yet. Tap the star on a room to add it.'
            : _category != DiscoverFilter.popular
            ? 'No ${_category.label} rooms match. Try Popular or another '
                  'word.'
            : 'No rooms match. Try another word or a smaller size.',
      );
    }

    Widget card(NetworkRoom r) {
      final room = r.entry;
      final net = r.network;
      final joined = _inRoom(state, net.id, room.name);
      final category = categoryOf(room);
      final favorite = prefs.isFavorite(net.id, room.name);
      void toggleFavorite() => ref
          .read(roomPrefsProvider.notifier)
          .toggleFavorite(net.id, room.name);
      final open = net.isConnected || joined
          ? () => _openOrJoin(net.id, room.name)
          : null;
      return RoomCard(
        key: ValueKey('${net.id}/${room.name}'),
        name: room.name,
        people: room.userCount,
        topic: stripFormatting(room.topic).trim(),
        category: category == RoomCategory.other ? null : category.label,
        busy: isBusyRoom(room),
        network: multi ? shortNetworkName(net.label) : null,
        joined: joined,
        favorite: favorite,
        onFavorite: toggleFavorite,
        onJoin: open,
        onTap: () => showRoomPreview(
          context,
          room: room,
          networkLabel: net.label,
          joined: joined,
          favorite: favorite,
          onJoin: open,
          onFavorite: toggleFavorite,
        ),
      );
    }

    final count = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '${rooms.length} of $total rooms',
        style: TypeScale.meta.copyWith(color: tokens.textMuted),
      ),
    );
    return RefreshIndicator.adaptive(
      onRefresh: () async => controller.fetchRooms(filterId),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Two columns of cards on tablets and the Mac.
          final columns = constraints.maxWidth >= 700 ? 2 : 1;
          final rows = (rooms.length / columns).ceil();
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            itemCount: rows + 1,
            itemBuilder: (context, i) {
              if (i == 0) return count;
              final start = (i - 1) * columns;
              if (columns == 1) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card(rooms[start]),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++) ...[
                        if (c > 0) const SizedBox(width: 10),
                        Expanded(
                          child: start + c < rooms.length
                              ? card(rooms[start + c])
                              : const SizedBox(),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
