import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/discovery/domain/room_filter.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Lists every room on every connected network, with search, sort, a size
/// filter and a network filter.
class RoomBrowserScreen extends ConsumerStatefulWidget {
  const RoomBrowserScreen({super.key});

  @override
  ConsumerState<RoomBrowserScreen> createState() => _RoomBrowserScreenState();
}

class _RoomBrowserScreenState extends ConsumerState<RoomBrowserScreen> {
  final _search = TextEditingController();
  String _query = '';
  int _minUsers = 0;
  RoomSort _sort = RoomSort.mostPeople;
  bool _favoritesOnly = false;

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
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chat');
    }
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
    final connected = state.connectedNetworks;
    final networks = state.networks.values.toList();
    final multi = networks.length > 1;
    final filterId = state.networks.containsKey(_networkId) ? _networkId : null;
    final prefs = ref.watch(roomPrefsProvider);

    // Rooms in scope (network filter), then search/size/sort on top.
    final inScope = [
      for (final r in state.allRooms)
        if (filterId == null || r.network.id == filterId) r,
    ];
    final byEntry = Map<ChannelListEntry, NetworkRoom>.identity();
    for (final r in inScope) {
      if (!_favoritesOnly || prefs.isFavorite(r.network.id, r.entry.name)) {
        byEntry[r.entry] = r;
      }
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

    return Scaffold(
      appBar: AppBar(
        title: Text(
          networks.length == 1
              ? 'Rooms on ${networks.first.label}'
              : multi
              ? 'Rooms on ${networks.length} networks'
              : 'Rooms',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: connected.isNotEmpty && !loading
                ? () => controller.fetchRooms(filterId)
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                autocorrect: false,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search rooms and topics',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
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
            if (multi)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: const Icon(Icons.hub_outlined, size: 18),
                        label: const Text('All networks'),
                        selected: filterId == null,
                        onSelected: (_) => setState(() => _networkId = null),
                      ),
                    ),
                    for (final n in networks)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(n.label),
                          selected: filterId == n.id,
                          onSelected: (_) => setState(() => _networkId = n.id),
                        ),
                      ),
                  ],
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      avatar: const Icon(Icons.star, size: 18),
                      label: const Text('Favorites'),
                      selected: _favoritesOnly,
                      onSelected: (v) => setState(() => _favoritesOnly = v),
                    ),
                  ),
                  for (final min in roomSizeFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(min == 0 ? 'Any size' : '$min+ people'),
                        selected: _minUsers == min,
                        onSelected: (_) => setState(() => _minUsers = min),
                      ),
                    ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Most people'),
                    selected: _sort == RoomSort.mostPeople,
                    onSelected: (_) =>
                        setState(() => _sort = RoomSort.mostPeople),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('A–Z'),
                    selected: _sort == RoomSort.name,
                    onSelected: (_) => setState(() => _sort = RoomSort.name),
                  ),
                ],
              ),
            ),
            if (recents.isNotEmpty && _query.isEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('Recent:'),
                    ),
                    for (final r in recents)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.history, size: 18),
                          label: Text(
                            multi ? '${r.room} · ${r.network.label}' : r.room,
                          ),
                          onPressed: () => _join(r.network.id, r.room),
                        ),
                      ),
                  ],
                ),
              ),
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
    final theme = Theme.of(context);
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
      return const _Message(
        icon: Icons.cloud_off,
        text: 'Connect to a network to see its rooms.',
      );
    }
    if (errors.isNotEmpty && total == 0) {
      return _Message(
        icon: Icons.error_outline,
        text:
            "The server didn't send its room list: ${errors.join('\n')}\n"
            'Try again in a minute.',
      );
    }
    if (state.roomsLoading && total == 0) {
      return const _Message(
        icon: Icons.travel_explore,
        text: 'Fetching rooms… big networks can take a few seconds.',
      );
    }
    if (rooms.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        text: total == 0
            ? 'No rooms yet. Tap refresh to load them.'
            : _favoritesOnly
            ? 'No favorites here yet. Tap the star next to a room to add it.'
            : 'No rooms match. Try another word or a smaller size.',
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: () async => controller.fetchRooms(filterId),
      child: ListView.separated(
        itemCount: rooms.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${rooms.length} of $total rooms',
                style: theme.textTheme.bodySmall,
              ),
            );
          }
          final r = rooms[i - 1];
          final room = r.entry;
          final net = r.network;
          final favorite = prefs.isFavorite(net.id, room.name);
          final topic = stripFormatting(room.topic).trim();
          final canJoin = net.isConnected;
          return ListTile(
            title: Text(room.name),
            subtitle: topic.isEmpty && !multi
                ? null
                : Text.rich(
                    TextSpan(
                      children: [
                        if (multi)
                          TextSpan(
                            text: topic.isEmpty ? net.label : '${net.label} · ',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        TextSpan(text: topic),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            leading: CircleAvatar(
              child: Text(
                _compact(room.userCount),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: favorite
                      ? 'Remove ${room.name} from favorites'
                      : 'Add ${room.name} to favorites',
                  icon: Icon(favorite ? Icons.star : Icons.star_border),
                  onPressed: () => ref
                      .read(roomPrefsProvider.notifier)
                      .toggleFavorite(net.id, room.name),
                ),
                FilledButton.tonal(
                  onPressed: canJoin ? () => _join(net.id, room.name) : null,
                  child: const Text('Join'),
                ),
              ],
            ),
            onTap: canJoin ? () => _join(net.id, room.name) : null,
          );
        },
      ),
    );
  }

  static String _compact(int n) =>
      n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
