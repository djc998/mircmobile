/// Favorite, recent and muted rooms, remembered per network.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';

/// How many recent rooms each network keeps.
const int maxRecentRooms = 10;

class RoomPrefs {
  const RoomPrefs({
    this.favorites = const {},
    this.recents = const {},
    this.muted = const {},
  });

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
      muted: read(json['muted']),
    );
  }

  /// Favorite rooms keyed by network host, in the order they were starred.
  final Map<String, List<String>> favorites;

  /// Recently joined rooms keyed by network host, newest first.
  final Map<String, List<String>> recents;

  /// Muted rooms and private chats keyed by network host: their unread
  /// counts are grey and don't count towards the Mentions badge.
  final Map<String, List<String>> muted;

  static String networkKey(String host) => host.toLowerCase();

  List<String> favoritesFor(String host) =>
      favorites[networkKey(host)] ?? const [];

  List<String> recentsFor(String host) => recents[networkKey(host)] ?? const [];

  bool isFavorite(String host, String room) =>
      favoritesFor(host).any((r) => r.toLowerCase() == room.toLowerCase());

  List<String> mutedFor(String host) => muted[networkKey(host)] ?? const [];

  bool isMuted(String host, String name) =>
      mutedFor(host).any((r) => r.toLowerCase() == name.toLowerCase());

  RoomPrefs copyWith({
    Map<String, List<String>>? favorites,
    Map<String, List<String>>? recents,
    Map<String, List<String>>? muted,
  }) => RoomPrefs(
    favorites: favorites ?? this.favorites,
    recents: recents ?? this.recents,
    muted: muted ?? this.muted,
  );

  Map<String, Object?> toJson() => {
    'favorites': favorites,
    'recents': recents,
    'muted': muted,
  };
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
    _set(state.copyWith(favorites: {...state.favorites, key: list}));
  }

  /// Mutes or unmutes a room or private chat.
  void toggleMute(String host, String name) =>
      _set(state.copyWith(muted: _toggled(state.muted, host, name)));

  static Map<String, List<String>> _toggled(
    Map<String, List<String>> map,
    String host,
    String name,
  ) {
    final key = RoomPrefs.networkKey(host);
    final list = [...map[key] ?? const <String>[]];
    final index = list.indexWhere((r) => r.toLowerCase() == name.toLowerCase());
    if (index == -1) {
      list.add(name);
    } else {
      list.removeAt(index);
    }
    return {...map, key: list};
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
    _set(state.copyWith(recents: {...state.recents, key: list}));
  }

  void clearRecents(String host) {
    _set(
      state.copyWith(
        recents: {...state.recents}..remove(RoomPrefs.networkKey(host)),
      ),
    );
  }

  void _set(RoomPrefs prefs) {
    state = prefs;
    unawaited(_store.setString(_key, jsonEncode(prefs.toJson())));
  }
}
