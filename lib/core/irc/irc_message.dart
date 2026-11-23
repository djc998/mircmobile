/// IRC line model and parser (RFC 1459 / RFC 2812 + IRCv3 message tags).
library;

import 'package:meta/meta.dart';

/// The source of a message, e.g. `nick!user@host` or `irc.example.org`.
@immutable
class IrcPrefix {
  const IrcPrefix({
    required this.raw,
    required this.nick,
    this.user,
    this.host,
  });

  /// Parses `nick!user@host`, `nick@host` or a bare server name.
  factory IrcPrefix.parse(String raw) {
    var nick = raw;
    String? user;
    String? host;
    final at = raw.indexOf('@');
    if (at != -1) {
      host = raw.substring(at + 1);
      nick = raw.substring(0, at);
    }
    final bang = nick.indexOf('!');
    if (bang != -1) {
      user = nick.substring(bang + 1);
      nick = nick.substring(0, bang);
    }
    return IrcPrefix(raw: raw, nick: nick, user: user, host: host);
  }

  final String raw;

  /// The nickname, or the server name when the source is a server.
  final String nick;
  final String? user;
  final String? host;

  /// True when the source looks like a server rather than a user.
  bool get isServer => user == null && host == null && nick.contains('.');

  @override
  bool operator ==(Object other) => other is IrcPrefix && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;

  @override
  String toString() => raw;
}

/// Thrown when a line cannot be parsed into a message.
class IrcParseException implements Exception {
  IrcParseException(this.message, this.line);

  final String message;
  final String line;

  @override
  String toString() => 'IrcParseException: $message in "$line"';
}

/// One IRC protocol message.
@immutable
class IrcMessage {
  IrcMessage({
    required String command,
    List<String> params = const [],
    Map<String, String> tags = const {},
    this.prefix,
  }) : command = command.toUpperCase(),
       params = List.unmodifiable(params),
       tags = Map.unmodifiable(tags);

  /// Parses one raw IRC line. Trailing CR/LF is ignored.
  factory IrcMessage.parse(String line) {
    var end = line.length;
    while (end > 0 && (line[end - 1] == '\n' || line[end - 1] == '\r')) {
      end--;
    }
    final s = line.substring(0, end);
    var i = 0;

    void skipSpaces() {
      while (i < s.length && s.codeUnitAt(i) == 0x20) {
        i++;
      }
    }

    String readWord() {
      final start = i;
      while (i < s.length && s.codeUnitAt(i) != 0x20) {
        i++;
      }
      return s.substring(start, i);
    }

    skipSpaces();
    var tags = const <String, String>{};
    if (i < s.length && s[i] == '@') {
      i++;
      tags = _parseTags(readWord());
      skipSpaces();
    }

    IrcPrefix? prefix;
    if (i < s.length && s[i] == ':') {
      i++;
      final raw = readWord();
      if (raw.isEmpty) throw IrcParseException('empty prefix', line);
      prefix = IrcPrefix.parse(raw);
      skipSpaces();
    }

    final command = readWord();
    if (command.isEmpty) throw IrcParseException('missing command', line);

    final params = <String>[];
    while (true) {
      skipSpaces();
      if (i >= s.length) break;
      if (s[i] == ':') {
        params.add(s.substring(i + 1));
        break;
      }
      params.add(readWord());
    }

    return IrcMessage(
      command: command,
      params: params,
      tags: tags,
      prefix: prefix,
    );
  }

  final Map<String, String> tags;
  final IrcPrefix? prefix;

  /// Upper-cased command or 3-digit numeric.
  final String command;
  final List<String> params;

  /// Numeric reply code, or null for named commands.
  int? get numeric => command.length == 3 ? int.tryParse(command) : null;

  /// The last parameter, usually the human readable text.
  String? get trailing => params.isEmpty ? null : params.last;

  /// Parameter at [index], or null.
  String? param(int index) => index < params.length ? params[index] : null;

  /// The IRCv3 `server-time` tag, when present and valid.
  DateTime? get serverTime {
    final t = tags['time'];
    return t == null ? null : DateTime.tryParse(t);
  }

  /// Serializes back to a wire line, without the CRLF terminator.
  String toLine() {
    final b = StringBuffer();
    if (tags.isNotEmpty) {
      b
        ..write('@')
        ..write(
          tags.entries
              .map(
                (e) => e.value.isEmpty ? e.key : '${e.key}=${_escape(e.value)}',
              )
              .join(';'),
        )
        ..write(' ');
    }
    if (prefix != null) b.write(':${prefix!.raw} ');
    b.write(command);
    for (var p = 0; p < params.length; p++) {
      final value = params[p];
      final isLast = p == params.length - 1;
      if (isLast &&
          (value.isEmpty || value.contains(' ') || value.startsWith(':'))) {
        b.write(' :$value');
      } else {
        if (value.isEmpty || value.contains(' ') || value.startsWith(':')) {
          throw ArgumentError.value(
            value,
            'params',
            'Only the last parameter may be empty, contain spaces or start '
                'with ":"',
          );
        }
        b.write(' $value');
      }
    }
    return b.toString();
  }

  @override
  String toString() => toLine();

  /// Parses `key=value;key2` with IRCv3 escaping (message tags, and soju's
  /// BOUNCER NETWORK attributes).
  static Map<String, String> parseTags(String raw) => _parseTags(raw);

  static Map<String, String> _parseTags(String raw) {
    final tags = <String, String>{};
    for (final part in raw.split(';')) {
      if (part.isEmpty) continue;
      final eq = part.indexOf('=');
      if (eq == -1) {
        tags[part] = '';
      } else {
        tags[part.substring(0, eq)] = _unescape(part.substring(eq + 1));
      }
    }
    return tags;
  }

  static String _unescape(String v) {
    if (!v.contains(r'\')) return v;
    final b = StringBuffer();
    for (var i = 0; i < v.length; i++) {
      final c = v[i];
      if (c != r'\') {
        b.write(c);
        continue;
      }
      if (i + 1 >= v.length) break; // A lone trailing backslash is dropped.
      final n = v[++i];
      b.write(switch (n) {
        ':' => ';',
        's' => ' ',
        'r' => '\r',
        'n' => '\n',
        _ => n, // Covers `\\` and unknown escapes.
      });
    }
    return b.toString();
  }

  static String _escape(String v) => v
      .replaceAll(r'\', r'\\')
      .replaceAll(';', r'\:')
      .replaceAll(' ', r'\s')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');
}
