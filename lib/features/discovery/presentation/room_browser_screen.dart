import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/discovery/domain/room_filter.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Lists every room on the network with search, sort and a size filter.
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

  @override
  void initState() {
    super.initState();
    // Fetch on first open; later opens reuse the cached list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(chatControllerProvider);
      if (state.roomsFetchedAt == null && !state.roomsLoading) {
        ref.read(chatControllerProvider.notifier).fetchRooms();
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _join(ChannelListEntry room) => _joinName(room.name);

  void _joinName(String name) {
    ref.read(chatControllerProvider.notifier).joinRoom(name);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/chat');
    }
  }

  @override
  Widget build(BuildContext context) {
    // If the browser was opened while still logging in, fetch once connected.
    ref.listen(chatControllerProvider.select((s) => s.status), (_, status) {
      final s = ref.read(chatControllerProvider);
      if (status == IrcConnectionStatus.connected &&
          s.roomsFetchedAt == null &&
          !s.roomsLoading) {
        ref.read(chatControllerProvider.notifier).fetchRooms();
      }
    });
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final connected = state.status == IrcConnectionStatus.connected;
    final prefs = ref.watch(roomPrefsProvider);
    final host = controller.host ?? '';
    final recents = prefs.recentsFor(host);
    final rooms = filterRooms(
      _favoritesOnly
          ? state.rooms.where((r) => prefs.isFavorite(host, r.name)).toList()
          : state.rooms,
      query: _query,
      minUsers: _minUsers,
      sort: _sort,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Rooms on ${state.network}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: connected && !state.roomsLoading
                ? controller.fetchRooms
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
            if (recents.isNotEmpty && _query.isEmpty && connected)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: Text('Recent:'),
                    ),
                    for (final room in recents)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ActionChip(
                          avatar: const Icon(Icons.history, size: 18),
                          label: Text(room),
                          onPressed: () => _joinName(room),
                        ),
                      ),
                  ],
                ),
              ),
            if (state.roomsLoading) const LinearProgressIndicator(),
            Expanded(
              child: _body(
                context,
                state,
                rooms,
                connected,
                controller,
                prefs,
                host,
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
    List<ChannelListEntry> rooms,
    bool connected,
    ChatController controller,
    RoomPrefs prefs,
    String host,
  ) {
    final theme = Theme.of(context);
    if (!connected && state.rooms.isEmpty) {
      return const _Message(
        icon: Icons.cloud_off,
        text: 'Connect to a network to see its rooms.',
      );
    }
    if (state.roomsError != null && state.rooms.isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        text:
            "The server didn't send its room list: ${state.roomsError}\n"
            'Try again in a minute.',
      );
    }
    if (state.roomsLoading && state.rooms.isEmpty) {
      return const _Message(
        icon: Icons.travel_explore,
        text: 'Fetching rooms… big networks can take a few seconds.',
      );
    }
    if (rooms.isEmpty) {
      return _Message(
        icon: Icons.search_off,
        text: state.rooms.isEmpty
            ? 'No rooms yet. Tap refresh to load them.'
            : _favoritesOnly
            ? 'No favorites here yet. Tap the star next to a room to add it.'
            : 'No rooms match. Try another word or a smaller size.',
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: () async => controller.fetchRooms(),
      child: ListView.separated(
        itemCount: rooms.length + 1,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                '${rooms.length} of ${state.rooms.length} rooms',
                style: theme.textTheme.bodySmall,
              ),
            );
          }
          final room = rooms[i - 1];
          final topic = stripFormatting(room.topic).trim();
          return ListTile(
            title: Text(room.name),
            subtitle: topic.isEmpty
                ? null
                : Text(topic, maxLines: 2, overflow: TextOverflow.ellipsis),
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
                  tooltip: prefs.isFavorite(host, room.name)
                      ? 'Remove ${room.name} from favorites'
                      : 'Add ${room.name} to favorites',
                  icon: Icon(
                    prefs.isFavorite(host, room.name)
                        ? Icons.star
                        : Icons.star_border,
                  ),
                  onPressed: host.isEmpty
                      ? null
                      : () => ref
                            .read(roomPrefsProvider.notifier)
                            .toggleFavorite(host, room.name),
                ),
                FilledButton.tonal(
                  onPressed: connected ? () => _join(room) : null,
                  child: const Text('Join'),
                ),
              ],
            ),
            onTap: connected ? () => _join(room) : null,
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
