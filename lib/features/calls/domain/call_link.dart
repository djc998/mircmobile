/// Links to voice and video calls: `https://host/c/<id>#video` or `#voice`.
library;

import 'package:meta/meta.dart';

/// A call invite. It travels as an ordinary private message, so people on
/// other IRC apps can open it in a browser.
@immutable
class CallLink {
  const CallLink({required this.page, required this.video});

  /// `https://host/c/<id>`, without the `#video` / `#voice` part.
  final Uri page;

  /// A video call (otherwise voice only).
  final bool video;

  static final _pattern = RegExp(
    r'https://[A-Za-z0-9.-]+(?::\d+)?/c/([A-Za-z0-9_-]{22})#(video|voice)\b',
  );

  /// The first call link in [text], if any.
  static CallLink? find(String text) {
    final m = _pattern.firstMatch(text);
    if (m == null) return null;
    return CallLink(
      page: Uri.parse(m.group(0)!).removeFragment(),
      video: m.group(2) == 'video',
    );
  }

  /// Parses the `url` the server returns for a new call.
  static CallLink? parse(String url) => find(url);

  String get id => page.pathSegments.last;

  /// Where the two sides exchange connection details.
  Uri get socket => page.replace(
    scheme: page.scheme == 'http' ? 'ws' : 'wss',
    path: '${page.path}/ws',
  );

  /// Where relay (TURN) and STUN addresses come from.
  Uri get ice => page.replace(path: '${page.path}/ice');

  Uri get decline => page.replace(path: '${page.path}/decline');

  /// The text sent to the other person.
  String message(String sender) => video
      ? '🎥 Video call from $sender: $this'
      : '📞 Voice call from $sender: $this';

  @override
  String toString() => '$page#${video ? 'video' : 'voice'}';

  @override
  bool operator ==(Object other) =>
      other is CallLink && other.toString() == toString();

  @override
  int get hashCode => toString().hashCode;
}
