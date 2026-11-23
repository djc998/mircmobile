/// Links to short-lived, encrypted files, sent like photos.
library;

import 'package:meta/meta.dart';

/// The largest file that can be sent (the server refuses bigger ones).
const int maxFileBytes = 25 * 1024 * 1024;

/// A link to an encrypted file:
/// `https://host/f/<id>#k=<key>&n=<name>&s=<size>`.
///
/// The key and the file's name are after `#`, which is never sent to the
/// server, so it only ever holds scrambled bytes of an unnamed file.
@immutable
class FileLink {
  const FileLink({
    required this.page,
    required this.key,
    required this.name,
    required this.size,
  });

  /// The file's page, without the key (`https://host/f/<id>`).
  final Uri page;

  /// AES-256 key, base64url without padding.
  final String key;

  /// The file's name, as the sender had it (cleaned by [safeFileName]).
  final String name;

  /// Size in bytes before encryption.
  final int size;

  static final _pattern = RegExp(
    r'https://[A-Za-z0-9.-]+(?::\d+)?/f/([A-Za-z0-9_-]{22})'
    r'#k=([A-Za-z0-9_-]{43})&n=([^&\s]+)&s=(\d{1,12})',
  );

  /// The first file link in [text], if any.
  static FileLink? find(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) return null;
    final String name;
    try {
      name = safeFileName(Uri.decodeComponent(m.group(3)!));
    } on Object {
      // Badly escaped name: not a link we made.
      return null;
    }
    final whole = Uri.parse(m.group(0)!);
    return FileLink(
      page: whole.removeFragment(),
      key: m.group(2)!,
      name: name,
      size: int.parse(m.group(4)!),
    );
  }

  String get id => page.pathSegments.last;

  /// Where the encrypted bytes are downloaded from.
  Uri get raw => page.replace(path: '${page.path}/raw');

  /// The text sent to the other person, e.g.
  /// `📎 File from dennis: notes.pdf (1.2 MB) <link>`.
  String message(String sender) =>
      '📎 File from $sender: $name (${formatFileSize(size)}) $this';

  @override
  String toString() => '$page#k=$key&n=${Uri.encodeComponent(name)}&s=$size';

  @override
  bool operator ==(Object other) =>
      other is FileLink && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}

/// [name] without folders, control characters or characters file systems
/// refuse, at most 120 characters, never empty or hidden.
String safeFileName(String name) {
  var n = name.split(RegExp(r'[/\\]')).last;
  n = n.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"|?*]'), '_').trim();
  n = n.replaceFirst(RegExp(r'^\.+'), '');
  if (n.length > 120) {
    final dot = n.lastIndexOf('.');
    final ext = dot > 0 && n.length - dot <= 10 ? n.substring(dot) : '';
    n = n.substring(0, 120 - ext.length) + ext;
  }
  return n.isEmpty ? 'file' : n;
}

/// A size for people: `820 bytes`, `14 KB`, `1.2 MB`.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  final mb = bytes / (1024 * 1024);
  return '${mb < 10 ? mb.toStringAsFixed(1) : mb.round()} MB';
}
