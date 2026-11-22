/// Suggestions shown as chips above the composer while typing `@nick`,
/// `/command` or `#room`.
library;

import 'package:flutter/foundation.dart';
import 'package:irc_client/core/irc/input_commands.dart';

/// One suggestion: [label] is what the chip shows, [replacement] what the
/// word being typed becomes.
@immutable
class Completion {
  const Completion(this.label, this.replacement);

  final String label;
  final String replacement;

  @override
  bool operator ==(Object other) =>
      other is Completion &&
      other.label == label &&
      other.replacement == replacement;

  @override
  int get hashCode => Object.hash(label, replacement);

  @override
  String toString() => 'Completion($label → "$replacement")';
}

/// Every command name the input understands, without the slash.
final List<String> inputCommandNames = [
  for (final usage in inputCommandHelp.keys)
    for (final part in usage.split(', ')) part.split(' ').first.substring(1),
];

/// At most this many chips.
const int maxCompletions = 8;

/// Suggestions for the word ending at [cursor] in [text]:
///
/// - `/to` at the start of the line → commands (`/topic `)
/// - `@al` → people in the room; picking one writes `alice: ` at the start
///   of a line (so they're notified) or `alice ` elsewhere
/// - `#li` → rooms you're in (`#linux `)
List<Completion> completionsFor(
  String text,
  int cursor, {
  Iterable<String> nicks = const [],
  Iterable<String> rooms = const [],
}) {
  if (cursor < 0 || cursor > text.length) return const [];
  final before = text.substring(0, cursor);
  final start = before.lastIndexOf(RegExp(r'\s')) + 1;
  final word = before.substring(start);
  if (word.isEmpty) return const [];
  List<Completion> matching(
    Iterable<String> names,
    Completion Function(String) make, {
    bool keepSigil = false,
  }) {
    // Rooms are matched with their `#`; commands and nicks without the sigil.
    final prefix = (keepSigil ? word : word.substring(1)).toLowerCase();
    final seen = <String>{};
    return [
      for (final n in names)
        if (n.toLowerCase().startsWith(prefix) && seen.add(n.toLowerCase()))
          make(n),
    ].take(maxCompletions).toList();
  }

  switch (word[0]) {
    case '/' when start == 0:
      return matching(inputCommandNames, (c) => Completion('/$c', '/$c '));
    case '@':
      final sorted = [...nicks]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return matching(
        sorted,
        (n) => Completion('@$n', start == 0 ? '$n: ' : '$n '),
      );
    case '#':
      return matching(rooms, (r) => Completion(r, '$r '), keepSigil: true);
  }
  return const [];
}

/// [text] with the word ending at [cursor] replaced by [completion], and
/// where the cursor goes after it.
(String, int) applyCompletion(String text, int cursor, Completion completion) {
  final before = text.substring(0, cursor);
  final start = before.lastIndexOf(RegExp(r'\s')) + 1;
  var after = text.substring(cursor);
  // Don't double the space the completion ends with.
  if (completion.replacement.endsWith(' ') && after.startsWith(' ')) {
    after = after.substring(1);
  }
  final result = text.substring(0, start) + completion.replacement;
  return (result + after, result.length);
}
