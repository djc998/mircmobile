/// Favorite and recent rooms, remembered per network.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';

/// How many recent rooms each network keeps.
const int maxRecentRooms = 10;

class RoomPrefs {
  const RoomPrefs({this.favorites = const {}, this.recents = const {}});

  factory RoomPrefs.fromJson(Map<String, Object?> json) {
    Map<String, List<String>> read(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is List)
            '${e.key}': [for (final r in e.value as List) '$r'],
    };
    return RoomPrefs(
      favorites: read(json['favorites']),
      recents: read(json['recents']),
    );
  }

  /// Favorite rooms keyed by network host, in the order they were starred.
  final Map<String, List<String>> favorites;

  /// Recently joined rooms keyed by network host, newest first.
  final Map<String, List<String>> recents;

  static String networkKey(String host) => host.toLowerCase();

  List<String> favoritesFor(String host) =>
      favorites[networkKey(host)] ?? const [];

  List<String> recentsFor(String host) => recents[networkKey(host)] ?? const [];

  bool isFavorite(String host, String room) =>
      favoritesFor(host).any((r) => r.toLowerCase() == room.toLowerCase());

  Map<String, Object?> toJson() => {'favorites': favorites, 'recents': recents};
}

final roomPrefsProvider = NotifierProvider<RoomPrefsController, RoomPrefs>(
  RoomPrefsController.new,
);

class RoomPrefsController extends Notifier<RoomPrefs> {
  static const _key = 'roomPrefs';

  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  RoomPrefs build() {
    final raw = ref.watch(keyValueStoreProvider).getString(_key);
    if (raw == null) return const RoomPrefs();
    try {
      return RoomPrefs.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      return const RoomPrefs();
    }
  }

  void toggleFavorite(String host, String room) {
    final key = RoomPrefs.networkKey(host);
    final list = [...state.favoritesFor(host)];
    final index = list.indexWhere((r) => r.toLowerCase() == room.toLowerCase());
    if (index == -1) {
      list.add(room);
    } else {
      list.removeAt(index);
    }
    _set(
      RoomPrefs(
        favorites: {...state.favorites, key: list},
        recents: state.recents,
      ),
    );
  }

  /// Records that [room] was just joined.
  void addRecent(String host, String room) {
    final key = RoomPrefs.networkKey(host);
    final list = [
      room,
      ...state
          .recentsFor(host)
          .where((r) => r.toLowerCase() != room.toLowerCase()),
    ].take(maxRecentRooms).toList();
    _set(
      RoomPrefs(
        favorites: state.favorites,
        recents: {...state.recents, key: list},
      ),
    );
  }

  void clearRecents(String host) {
    _set(
      RoomPrefs(
        favorites: state.favorites,
        recents: {...state.recents}..remove(RoomPrefs.networkKey(host)),
      ),
    );
  }

  void _set(RoomPrefs prefs) {
    state = prefs;
    unawaited(_store.setString(_key, jsonEncode(prefs.toJson())));
  }
}
