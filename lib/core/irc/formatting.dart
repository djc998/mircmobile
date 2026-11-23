/// mIRC formatting codes (bold, colours, italics, ...).
library;

final RegExp _formatting = RegExp(
  '\x03(?:\\d{1,2}(?:,\\d{1,2})?)?' // colour with optional fg,bg
  '|\x04(?:[0-9a-fA-F]{6}(?:,[0-9a-fA-F]{6})?)?' // hex colour
  '|[\x02\x0F\x11\x16\x1D\x1E\x1F]',
);

/// Removes mIRC colour and style codes, leaving plain text: for mention
/// checks, previews, search, copying and picture links. The chat view draws
/// the codes (see `mirc_format.dart`).
String stripFormatting(String text) => text.replaceAll(_formatting, '');

/// Valid IRC nickname: starts with a letter or special, up to 30 chars.
bool isValidNick(String nick) =>
    RegExp(r'^[A-Za-z\[\]\\`_^{|}][A-Za-z0-9\[\]\\`_^{|}-]{0,29}$')
        .hasMatch(nick);

/// Characters that can be part of a nickname besides letters and digits.
const String _nickChars = r'A-Za-z0-9_\-\[\]\\{}|^`';

/// Whether [text] mentions [nick] as a whole word, ignoring case. "al"
/// matches "hi al!" but not "also".
bool mentions(String text, String nick) {
  if (nick.isEmpty) return false;
  return RegExp(
    '(^|[^$_nickChars])${RegExp.escape(nick)}(\$|[^$_nickChars])',
    caseSensitive: false,
  ).hasMatch(stripFormatting(text));
}

/// Completes the last word of [text] to a nickname from [nicks] (Tab
/// completion). At the start of the line the name gets `: ` after it, the
/// usual way to address someone. Returns null when nothing matches.
String? completeNick(String text, Iterable<String> nicks) {
  final start = text.lastIndexOf(' ') + 1;
  final word = text.substring(start).toLowerCase();
  if (word.isEmpty) return null;
  final matches = [
    for (final n in nicks)
      if (n.toLowerCase().startsWith(word)) n,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  if (matches.isEmpty) return null;
  return '${text.substring(0, start)}${matches.first}'
      '${start == 0 ? ': ' : ' '}';
}
