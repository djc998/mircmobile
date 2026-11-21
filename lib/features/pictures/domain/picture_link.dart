/// Links to short-lived, encrypted pictures and how long they last.
library;

import 'package:meta/meta.dart';

/// How long a shared picture stays available.
enum PictureExpiry {
  hour(Duration(hours: 1), '1 hour'),
  halfDay(Duration(hours: 12), '12 hours'),
  day(Duration(days: 1), '1 day'),
  threeDays(Duration(days: 3), '3 days');

  PictureExpiry(this.duration, this.label);

  final Duration duration;
  final String label;
}

/// A link to an encrypted picture: `https://host/p/<id>#k=<key>[&o=1]`.
///
/// The key is in the part after `#`, which is never sent to the server, so
/// only people who have the link can see the picture.
@immutable
class PictureLink {
  const PictureLink({
    required this.page,
    required this.key,
    this.viewOnce = false,
  });

  /// The picture's page, without the key (`https://host/p/<id>`).
  final Uri page;

  /// AES-256 key, base64url without padding.
  final String key;

  /// Deleted from the server after the first view.
  final bool viewOnce;

  static final _pattern = RegExp(
    r'https://[A-Za-z0-9.-]+(?::\d+)?/p/([A-Za-z0-9_-]{22})'
    '#k=([A-Za-z0-9_-]{43})(&o=1)?',
  );

  /// The first picture link in [text], if any.
  static PictureLink? find(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) return null;
    final whole = Uri.parse(m.group(0)!);
    return PictureLink(
      page: whole.removeFragment(),
      key: m.group(2)!,
      viewOnce: m.group(3) != null,
    );
  }

  String get id => page.pathSegments.last;

  /// Where the encrypted bytes are downloaded from.
  Uri get raw => page.replace(path: '${page.path}/raw');

  /// The text sent to the other person.
  String message(PictureExpiry expiry) =>
      '📷 Picture (${viewOnce ? 'view once, ' : ''}'
      'disappears in ${expiry.label}): $this';

  @override
  String toString() => '$page#k=$key${viewOnce ? '&o=1' : ''}';

  @override
  bool operator ==(Object other) =>
      other is PictureLink && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
