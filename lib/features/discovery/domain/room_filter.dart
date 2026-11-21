/// Searching and sorting the room list for the room browser.
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';

enum RoomSort { mostPeople, name }

/// Minimum-size choices shown as chips.
const List<int> roomSizeFilters = [0, 10, 50, 200];

/// Filters [rooms] by [query] (name or topic, case-insensitive, all words
/// must match) and [minUsers], then sorts them.
///
/// Rooms whose name matches rank above rooms that only match in the topic.
List<ChannelListEntry> filterRooms(
  List<ChannelListEntry> rooms, {
  String query = '',
  int minUsers = 0,
  RoomSort sort = RoomSort.mostPeople,
}) {
  final words = query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .map((w) => w.startsWith('#') ? w.substring(1) : w)
      .where((w) => w.isNotEmpty)
      .toList();

  final nameHits = <ChannelListEntry>[];
  final topicHits = <ChannelListEntry>[];
  for (final room in rooms) {
    if (room.userCount < minUsers) continue;
    if (words.isEmpty) {
      nameHits.add(room);
      continue;
    }
    final name = room.name.toLowerCase();
    final haystack = '$name ${stripFormatting(room.topic).toLowerCase()}';
    if (!words.every(haystack.contains)) continue;
    (words.every(name.contains) ? nameHits : topicHits).add(room);
  }

  int compare(ChannelListEntry a, ChannelListEntry b) => switch (sort) {
    RoomSort.mostPeople =>
      b.userCount != a.userCount
          ? b.userCount.compareTo(a.userCount)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    RoomSort.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  };

  return [...nameHits..sort(compare), ...topicHits..sort(compare)];
}
