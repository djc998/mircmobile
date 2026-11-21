import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/features/discovery/domain/room_filter.dart';

void main() {
  const rooms = [
    ChannelListEntry(name: '#linux', userCount: 900, topic: 'Linux help'),
    ChannelListEntry(name: '#python', userCount: 1500, topic: 'Python'),
    ChannelListEntry(name: '#chat', userCount: 40, topic: 'Talk about linux'),
    ChannelListEntry(name: '#Arch', userCount: 900, topic: 'Arch \x02Linux'),
    ChannelListEntry(name: '#tiny', userCount: 2, topic: ''),
  ];

  List<String> names(List<ChannelListEntry> r) => r.map((e) => e.name).toList();

  test('no query sorts by most people, ties by name', () {
    expect(names(filterRooms(rooms)), [
      '#python',
      '#Arch',
      '#linux',
      '#chat',
      '#tiny',
    ]);
  });

  test('A–Z sort ignores case', () {
    expect(names(filterRooms(rooms, sort: RoomSort.name)), [
      '#Arch',
      '#chat',
      '#linux',
      '#python',
      '#tiny',
    ]);
  });

  test('name matches rank above topic-only matches', () {
    expect(names(filterRooms(rooms, query: 'linux')), [
      '#linux',
      '#Arch',
      '#chat',
    ]);
  });

  test('query is case-insensitive, ignores # and formatting codes', () {
    expect(names(filterRooms(rooms, query: '#PYTHON')), ['#python']);
    expect(names(filterRooms(rooms, query: 'arch linux')), ['#Arch']);
  });

  test('all words must match', () {
    expect(filterRooms(rooms, query: 'linux python'), isEmpty);
  });

  test('minimum size filter', () {
    expect(names(filterRooms(rooms, minUsers: 50)), [
      '#python',
      '#Arch',
      '#linux',
    ]);
    expect(names(filterRooms(rooms, query: 'linux', minUsers: 10)), [
      '#linux',
      '#Arch',
      '#chat',
    ]);
  });
}
