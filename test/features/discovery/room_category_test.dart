import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:irc_client/features/discovery/domain/room_category.dart';

ChannelListEntry room(String name, String topic, [int users = 10]) =>
    ChannelListEntry(name: name, userCount: users, topic: topic);

void main() {
  group('categorizeRoom', () {
    // The mockup's rooms.
    for (final (name, topic, expected) in [
      ('#flutter', 'Flutter and Dart help. Be kind.', RoomCategory.tech),
      (
        '#chillhop',
        'Lo-fi beats, what are you listening to?',
        RoomCategory.music,
      ),
      (
        '#retrogaming',
        'Consoles, cartridges and speedruns.',
        RoomCategory.gaming,
      ),
      ('#help', 'New to IRC? Ask anything here.', RoomCategory.help),
      ('#linux', 'General Linux help and chat.', RoomCategory.tech),
      (
        '#coffee',
        'Small, slow, friendly. Pull up a chair.',
        RoomCategory.social,
      ),
      (
        '#indiedev',
        'Making games on your own or in small teams.',
        RoomCategory.gaming,
      ),
      ('##chat', '', RoomCategory.social),
      ('#xyzzy', 'Nothing to see', RoomCategory.other),
    ]) {
      test('$name → ${expected.label}', () {
        expect(categorizeRoom(name, topic), expected);
      });
    }

    test('mIRC colour codes in the topic are ignored', () {
      expect(
        categorizeRoom('#abc', '\x0304,01python\x03 and rust'),
        RoomCategory.tech,
      );
    });

    test('short keywords only match whole words', () {
      // "go" inside "google" isn't Go.
      expect(categorizeRoom('#google', 'search'), RoomCategory.other);
      expect(categorizeRoom('#go', 'the language'), RoomCategory.tech);
    });
  });

  test('busy rooms have 100 or more people', () {
    expect(isBusyRoom(room('#a', '', 99)), isFalse);
    expect(isBusyRoom(room('#a', '', 100)), isTrue);
  });

  test('filters: Popular shows everything, the rest by category', () {
    final music = room('#jazz', 'smooth');
    final tech = room('#rust', 'systems');
    expect(DiscoverFilter.popular.matches(music), isTrue);
    expect(DiscoverFilter.music.matches(music), isTrue);
    expect(DiscoverFilter.music.matches(tech), isFalse);
    expect(DiscoverFilter.tech.matches(tech), isTrue);
    // Worked out once per room.
    expect(identical(categoryOf(tech), categoryOf(tech)), isTrue);
  });
}
