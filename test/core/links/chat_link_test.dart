import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/links/chat_link.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/mirc_text.dart';
import 'package:material_ui/material_ui.dart';

List<String> linksIn(String text) => [
  for (final l in findLinks(text)) text.substring(l.start, l.end),
];

List<TextSpan> flat(List<InlineSpan> spans) => [
  for (final s in spans)
    if (s is TextSpan) ...[
      if (s.text != null) s,
      if (s.children != null) ...flat(s.children!),
    ],
];

void main() {
  group('findLinks', () {
    test('finds http and https links in a sentence', () {
      expect(
        linksIn('see https://flutter.dev/docs and http://example.org now'),
        ['https://flutter.dev/docs', 'http://example.org'],
      );
    });

    test('leaves out the punctuation that ends a sentence', () {
      expect(linksIn('Look: https://x.org/a.'), ['https://x.org/a']);
      expect(linksIn('really? https://x.org/?q=1!'), ['https://x.org/?q=1']);
      expect(linksIn('"https://x.org/b",'), ['https://x.org/b']);
    });

    test('a link in parentheses, and one with its own', () {
      expect(linksIn('(see https://x.org/a)'), ['https://x.org/a']);
      expect(linksIn('https://en.wikipedia.org/wiki/Dart_(language)'), [
        'https://en.wikipedia.org/wiki/Dart_(language)',
      ]);
    });

    test('www. links get https', () {
      final links = findLinks('go to www.ircage.com today');
      expect(links.single.uri.toString(), 'https://www.ircage.com');
      expect(
        'go to www.ircage.com today'.substring(
          links.single.start,
          links.single.end,
        ),
        'www.ircage.com',
      );
    });

    test('not links: other schemes, no dot in the host', () {
      expect(linksIn('ftp://x.org mailto:a@b.c http://localhost'), isEmpty);
    });
  });

  group('mediaOf', () {
    test('images and videos by extension, https only', () {
      expect(mediaOf(Uri.parse('https://i.imgur.com/a.PNG')), LinkMedia.image);
      expect(
        mediaOf(Uri.parse('https://x.org/cat.gif?size=2')),
        LinkMedia.image,
      );
      expect(mediaOf(Uri.parse('https://x.org/clip.mp4')), LinkMedia.video);
      expect(mediaOf(Uri.parse('https://x.org/clip.webm')), LinkMedia.video);
      expect(mediaOf(Uri.parse('http://x.org/a.png')), isNull);
      expect(mediaOf(Uri.parse('https://x.org/page.html')), isNull);
      expect(mediaOf(Uri.parse('https://x.org/')), isNull);
    });
  });

  test("IRCage's own photo links aren't previewed as images", () {
    const photo = 'https://share.ircage.com/p/abcdefghijklmnopqrstuv#k=xyz';
    expect(isShareLink(Uri.parse(photo)), isTrue);
    expect(
      firstMediaLink('$photo and https://x.org/a.png')?.uri.toString(),
      'https://x.org/a.png',
    );
    expect(firstMediaLink('just https://x.org/page'), isNull);
  });

  group('mircSpans links', () {
    final tokens = AppTokens.indigo(Brightness.light);

    test('a link is underlined and tapping it opens it', () {
      final opened = <Uri>[];
      final taps = LinkTaps(opened.add);
      addTearDown(taps.dispose);
      final spans = flat(
        mircSpans(
          'hi \x02https://x.org/a\x02 bye',
          tokens: tokens,
          background: tokens.surface,
          textColor: tokens.textPrimary,
          links: taps,
        ),
      );
      final link = spans.singleWhere((s) => s.recognizer != null);
      expect(link.text, 'https://x.org/a');
      expect(link.style?.decoration, TextDecoration.underline);
      (link.recognizer! as TapGestureRecognizer).onTap!();
      expect(opened, [Uri.parse('https://x.org/a')]);
      expect(spans.map((s) => s.text).join(), 'hi https://x.org/a bye');
    });

    test('photo links and messages without links stay plain', () {
      final taps = LinkTaps((_) {});
      addTearDown(taps.dispose);
      final spans = flat(
        mircSpans(
          'https://share.ircage.com/p/abcdefghijklmnopqrstuv#k=1 hi',
          tokens: tokens,
          background: tokens.surface,
          textColor: tokens.textPrimary,
          links: taps,
        ),
      );
      expect(spans.where((s) => s.recognizer != null), isEmpty);
    });

    test('your nick is still highlighted next to a link', () {
      final taps = LinkTaps((_) {});
      addTearDown(taps.dispose);
      final spans = flat(
        mircSpans(
          'me: https://x.org',
          tokens: tokens,
          background: tokens.surface,
          textColor: tokens.textPrimary,
          highlight: 'me',
          highlightStyle: const TextStyle(fontWeight: FontWeight.w600),
          links: taps,
        ),
      );
      expect(
        spans.firstWhere((s) => s.text == 'me').style?.fontWeight,
        FontWeight.w600,
      );
      expect(
        spans.where((s) => s.recognizer != null).single.text,
        'https://x.org',
      );
    });
  });
}
