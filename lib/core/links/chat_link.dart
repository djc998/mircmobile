/// Web links in chat messages: where they are, and whether they point
/// straight at an image or a video.
library;

import 'package:meta/meta.dart';

/// A web link found in a message.
@immutable
class ChatLink {
  const ChatLink({required this.start, required this.end, required this.uri});

  /// Where the link starts and ends in the message text.
  final int start;
  final int end;

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is ChatLink &&
      other.start == start &&
      other.end == end &&
      other.uri == uri;

  @override
  int get hashCode => Object.hash(start, end, uri);

  @override
  String toString() => 'ChatLink($start-$end, $uri)';
}

/// What a link shows when opened: a picture or a video file.
enum LinkMedia { image, video }

// `http(s)://` or `www.`, up to whitespace or a character that can't be
// in a link as people paste it.
final _linkPattern = RegExp(
  r'''(?:\b(?:https?://|www\.))[^\s<>"'`\x00-\x1f]+''',
  caseSensitive: false,
);

// Punctuation that ends a sentence rather than the link.
const _trailing = '.,;:!?\'"*_';

/// The web links in [text], in order. `www.` links are given `https://`.
///
/// Trailing punctuation is left out (`see https://x.org.`), and so is a
/// closing bracket that has no opening one in the link, so a link in
/// parentheses works while Wikipedia's `Foo_(bar)` links stay whole.
List<ChatLink> findLinks(String text) {
  final links = <ChatLink>[];
  for (final m in _linkPattern.allMatches(text)) {
    var end = m.end;
    while (end > m.start) {
      final c = text[end - 1];
      if (_trailing.contains(c)) {
        end--;
        continue;
      }
      final open = switch (c) {
        ')' => '(',
        ']' => '[',
        '}' => '{',
        _ => null,
      };
      if (open != null) {
        final inside = text.substring(m.start, end);
        final opens = open.allMatches(inside).length;
        final closes = c.allMatches(inside).length;
        if (closes > opens) {
          end--;
          continue;
        }
      }
      break;
    }
    var raw = text.substring(m.start, end);
    if (raw.toLowerCase().startsWith('www.')) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.host.isEmpty || !uri.host.contains('.')) continue;
    links.add(ChatLink(start: m.start, end: end, uri: uri));
  }
  return links;
}

const _imageTypes = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
const _videoTypes = {'mp4', 'm4v', 'mov', 'webm'};

/// Whether [uri] points straight at an image or video file, judged by
/// its extension (nothing is fetched to find out). Only https links count,
/// so previews are never loaded over an unencrypted connection.
LinkMedia? mediaOf(Uri uri) {
  if (uri.scheme != 'https') return null;
  final segments = uri.pathSegments;
  if (segments.isEmpty) return null;
  final name = segments.last.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0) return null;
  final type = name.substring(dot + 1);
  if (_imageTypes.contains(type)) return LinkMedia.image;
  if (_videoTypes.contains(type)) return LinkMedia.video;
  return null;
}

/// IRCage's own photo, file and call links (`share.ircage.com/p/…#k=…`).
/// They have their own cards in the chat, and opening a view-once photo in
/// a browser would use up its one view, so they aren't made tappable.
bool isShareLink(Uri uri) {
  final segments = uri.pathSegments;
  return uri.fragment.isNotEmpty &&
      segments.length == 2 &&
      const {'p', 'f', 'c'}.contains(segments.first) &&
      segments.last.length == 22;
}

/// The first link in [text] that is an image or video, with its kind.
({Uri uri, LinkMedia media})? firstMediaLink(String text) {
  for (final link in findLinks(text)) {
    if (isShareLink(link.uri)) continue;
    final media = mediaOf(link.uri);
    if (media != null) return (uri: link.uri, media: media);
  }
  return null;
}
