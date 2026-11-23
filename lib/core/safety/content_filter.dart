/// The content filter: masks offensive words in what people write, and
/// spots adult rooms so Discover can hide them. On by default (Settings →
/// Safety), as the App Store asks of apps with user-generated content.
///
/// Matching is on whole words, case-insensitive, so "class" or "assist"
/// are left alone. The lists are short on purpose: slurs and the strongest
/// swearing, not every rude word.
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/irc_events.dart';
import 'package:material_ui/material_ui.dart';

/// Words masked in any form that starts with them ("fucking", "shitty").
const List<String> _stems = [
  'fuck',
  'motherfuck',
  'shit',
  'bullshit',
  'cunt',
  'nigger',
  'nigga',
  'faggot',
  'whore',
  'slut',
  'twat',
  'wank',
  'dickhead',
  'cocksuck',
  'kike',
  'chink',
  'tranny',
];

/// Words masked only as whole words (as stems they'd catch "spicy" or
/// "fire retardant").
const List<String> _words = [
  'fag',
  'fags',
  'bitch',
  'bitches',
  'asshole',
  'assholes',
  'retard',
  'retards',
  'retarded',
  'spic',
  'spics',
  'pussy',
  'pussies',
  'gook',
  'gooks',
  'wetback',
  'wetbacks',
  'dyke',
  'dykes',
  'paki',
  'pakis',
  'raghead',
  'ragheads',
  'trannies',
];

/// Room names and topics that mark a room as adult.
const List<String> _adultWords = [
  'sex',
  'sexy',
  'porn',
  'porno',
  'xxx',
  'nsfw',
  'nude',
  'nudes',
  'naked',
  'hentai',
  'fetish',
  'fetishes',
  'kink',
  'kinky',
  'bdsm',
  'horny',
  'erotic',
  'erotica',
  'swinger',
  'swingers',
  'milf',
  'cybersex',
  'cyber',
  'adult',
  'adults',
  '18+',
];

// Letters, digits and IRC nick characters count as part of a word.
const _wordChar = r'[\p{L}\p{N}_]';

final RegExp _offensive = RegExp(
  '(?<!$_wordChar)(?:'
  '(?:${_stems.map(RegExp.escape).join('|')})$_wordChar*'
  '|(?:${_words.map(RegExp.escape).join('|')})'
  ')(?!$_wordChar)',
  caseSensitive: false,
  unicode: true,
);

final RegExp _adult = RegExp(
  '(?<!$_wordChar)(?:${_adultWords.map(RegExp.escape).join('|')})'
  '(?!$_wordChar)',
  caseSensitive: false,
  unicode: true,
);

/// [text] with offensive words masked: the first letter stays, the rest
/// become `*`, so "shit" reads "s***". Formatting codes are kept.
String maskOffensive(String text) => text.replaceAllMapped(
  _offensive,
  (m) => m[0]![0] + '*' * (m[0]!.length - 1),
);

/// Whether [text] has a word [maskOffensive] would mask.
bool hasOffensive(String text) => _offensive.hasMatch(text);

/// Whether [room] looks like an adult room from its name or topic. Room
/// names like `#sex` or `#nsfw-chat` split on `-`, `_` and `.` too.
bool isAdultRoom(ChannelListEntry room) {
  final name = room.name.replaceAll(RegExp('^[#&]+'), '');
  final text =
      '${name.replaceAll(RegExp('[-_.]'), ' ')} '
      '${stripFormatting(room.topic)}';
  return _adult.hasMatch(text);
}

/// Whether the filter is on, for everything below it. Read with
/// [ContentFilter.of] or use [ContentFilter.clean].
class ContentFilter extends InheritedWidget {
  const ContentFilter({required this.enabled, required super.child, super.key});

  final bool enabled;

  /// Off when there's no setting above (tests, previews).
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentFilter>()?.enabled ??
      false;

  /// [text] masked when the filter is on.
  static String clean(BuildContext context, String text) =>
      of(context) ? maskOffensive(text) : text;

  @override
  bool updateShouldNotify(ContentFilter old) => old.enabled != enabled;
}
