/// Rough categories for rooms, guessed from their name and topic, for the
/// chips in Discover. IRC has no categories, so this is a best guess.
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';

enum RoomCategory {
  tech('Tech'),
  gaming('Gaming'),
  music('Music'),
  help('Help'),
  social('Social'),

  /// Nothing matched; only in Popular.
  other('Other');

  RoomCategory(this.label);
  final String label;
}

/// Rooms with at least this many people are marked "Busy now".
const int busyRoomMinPeople = 100;

bool isBusyRoom(ChannelListEntry room) => room.userCount >= busyRoomMinPeople;

const Map<RoomCategory, List<String>> _keywords = {
  RoomCategory.help: [
    'help',
    'support',
    'newbie',
    'newbies',
    'beginner',
    'beginners',
    'question',
    'questions',
    'ask',
    'faq',
    'howto',
    'learn',
    'learning',
  ],
  RoomCategory.gaming: [
    'game',
    'games',
    'gaming',
    'gamer',
    'gamers',
    'minecraft',
    'retro',
    'speedrun',
    'speedruns',
    'nintendo',
    'playstation',
    'xbox',
    'steam',
    'rpg',
    'mmo',
    'indie',
    'esports',
    'chess',
    'doom',
    'quake',
    'pokemon',
    'dnd',
    'cartridges',
    'consoles',
    'console',
    'gamedev',
  ],
  RoomCategory.music: [
    'music',
    'radio',
    'lofi',
    'chillhop',
    'jazz',
    'metal',
    'rock',
    'hiphop',
    'dj',
    'song',
    'songs',
    'band',
    'guitar',
    'piano',
    'synth',
    'edm',
    'techno',
    'beats',
    'listening',
    'playlist',
  ],
  RoomCategory.tech: [
    'linux',
    'python',
    'flutter',
    'dart',
    'rust',
    'golang',
    'go',
    'java',
    'javascript',
    'js',
    'node',
    'nodejs',
    'dev',
    'code',
    'coding',
    'programming',
    'debian',
    'ubuntu',
    'arch',
    'gentoo',
    'fedora',
    'bsd',
    'freebsd',
    'openbsd',
    'kernel',
    'git',
    'docker',
    'kubernetes',
    'k8s',
    'security',
    'sysadmin',
    'unix',
    'vim',
    'emacs',
    'android',
    'ios',
    'macos',
    'web',
    'php',
    'ruby',
    'perl',
    'haskell',
    'sql',
    'postgres',
    'database',
    'ai',
    'ml',
    'hardware',
    'electronics',
    'tor',
    'cpp',
    'lisp',
    'swift',
    'kotlin',
    'typescript',
    'react',
    'math',
    'science',
    'software',
    'opensource',
    'compilers',
    'networking',
    'nixos',
    'zig',
  ],
  RoomCategory.social: [
    'chat',
    'social',
    'lounge',
    'cafe',
    'coffee',
    'offtopic',
    'random',
    'hangout',
    'friends',
    'general',
    'talk',
    'pub',
    'bar',
    'friendly',
    'chill',
    'community',
  ],
};

/// Ties go to the earlier category here.
const List<RoomCategory> _order = [
  RoomCategory.help,
  RoomCategory.gaming,
  RoomCategory.music,
  RoomCategory.tech,
  RoomCategory.social,
];

List<String> _words(String text) => text
    .toLowerCase()
    .split(RegExp('[^a-z0-9+]+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// The best-guess category for a room. Words in the name count three times
/// as much as words in the topic; inside the name, longer keywords also
/// match as part of a word (`#retrogaming` is Gaming).
RoomCategory categorizeRoom(String name, String topic) {
  final nameWords = _words(name);
  final topicWords = _words(stripFormatting(topic));
  var best = RoomCategory.other;
  var bestScore = 0;
  for (final category in _order) {
    var score = 0;
    for (final kw in _keywords[category]!) {
      for (final w in nameWords) {
        if (w == kw || (kw.length >= 4 && w.contains(kw))) {
          score += 3;
          break;
        }
      }
      for (final w in topicWords) {
        if (w == kw || (kw.length >= 5 && w.startsWith(kw))) {
          score += 1;
          break;
        }
      }
    }
    if (score > bestScore) {
      best = category;
      bestScore = score;
    }
  }
  return best;
}

final Expando<RoomCategory> _categories = Expando('room category');

/// [categorizeRoom] for a listed room, worked out once per room (big
/// networks list tens of thousands).
RoomCategory categoryOf(ChannelListEntry room) =>
    _categories[room] ??= categorizeRoom(room.name, room.topic);

/// The chips in Discover: Popular (every room, most people first) and one
/// per category.
enum DiscoverFilter {
  popular('Popular', null),
  tech('Tech', RoomCategory.tech),
  gaming('Gaming', RoomCategory.gaming),
  music('Music', RoomCategory.music),
  help('Help', RoomCategory.help),
  social('Social', RoomCategory.social);

  DiscoverFilter(this.label, this.category);
  final String label;
  final RoomCategory? category;

  bool matches(ChannelListEntry room) =>
      category == null || categoryOf(room) == category;
}
