/// Draws mIRC-formatted text as styled spans that stay readable.
library;

import 'package:flutter/gestures.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/mirc_format.dart';
import 'package:irc_client/core/links/chat_link.dart';
import 'package:irc_client/core/safety/content_filter.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:material_ui/material_ui.dart';

/// Monospace families for `\x11` runs, first that exists wins.
const List<String> _monoFamilies = [
  'JetBrains Mono',
  'SF Mono',
  'Menlo',
  'Roboto Mono',
  'Consolas',
  'monospace',
];

/// Spans for [text] with its mIRC codes drawn.
///
/// - [colours] off: the codes are removed and the text is plain.
/// - Colours are nudged until they read at 4.5:1 on what's behind them:
///   the run's own background colour if it has one, else [background].
/// - [textColor] is the normal text colour (for reverse and for runs that
///   only set a background).
/// - [filter] masks offensive words ([maskOffensive]).
/// - Whole-word [highlight] (your nick) gets [highlightStyle].
/// - With [links], web links are tappable and drawn with [linkStyle]
///   (underlined by default). IRCage's own photo and file links aren't.
List<InlineSpan> mircSpans(
  String text, {
  required AppTokens tokens,
  required Color background,
  required Color textColor,
  bool colours = true,
  bool filter = false,
  String? highlight,
  TextStyle? highlightStyle,
  LinkTaps? links,
  TextStyle? linkStyle,
}) {
  final runs = colours ? parseMirc(text) : [MircRun(stripFormatting(text))];
  final spans = <InlineSpan>[];
  for (final run in runs) {
    final found = links == null
        ? const <ChatLink>[]
        : [
            for (final l in findLinks(run.text))
              if (!isShareLink(l.uri)) l,
          ];
    String shown(String raw) => filter ? maskOffensive(raw) : raw;
    final text = shown(run.text);
    TextStyle? style;
    if (!run.plain) {
      // Reverse with no colours set swaps the normal colours.
      final bg = isReverseForeground(run.background)
          ? textColor
          : run.background;
      final fg = isReverseBackground(run.foreground)
          ? background
          : run.foreground;
      final behind = bg ?? background;
      final color = fg != null
          ? tokens.readable(fg, behind)
          : bg != null
          ? tokens.readable(textColor, behind)
          : null;
      style = TextStyle(
        color: color,
        backgroundColor: bg,
        fontWeight: run.bold ? FontWeight.w700 : null,
        fontStyle: run.italic ? FontStyle.italic : null,
        decoration: TextDecoration.combine([
          if (run.underline) TextDecoration.underline,
          if (run.strike) TextDecoration.lineThrough,
        ]),
        fontFamilyFallback: run.mono ? _monoFamilies : null,
        fontFamily: run.mono ? _monoFamilies.last : null,
      );
    }
    List<InlineSpan> plain(String raw) {
      final text = shown(raw);
      return highlight == null || highlight.isEmpty
          ? [TextSpan(text: text)]
          : _highlighted(text, highlight, highlightStyle);
    }

    if (found.isEmpty) {
      if (highlight == null || highlight.isEmpty) {
        spans.add(TextSpan(text: text, style: style));
      } else {
        spans.add(
          TextSpan(
            style: style,
            children: _highlighted(text, highlight, highlightStyle),
          ),
        );
      }
      continue;
    }
    final children = <InlineSpan>[];
    var at = 0;
    for (final link in found) {
      if (link.start > at) {
        children.addAll(plain(run.text.substring(at, link.start)));
      }
      children.add(
        TextSpan(
          text: shown(run.text.substring(link.start, link.end)),
          style:
              linkStyle ??
              const TextStyle(decoration: TextDecoration.underline),
          recognizer: links!.recognizer(link.uri),
          mouseCursor: SystemMouseCursors.click,
          semanticsLabel: 'Link: ${link.uri.host}',
        ),
      );
      at = link.end;
    }
    if (at < run.text.length) children.addAll(plain(run.text.substring(at)));
    spans.add(TextSpan(style: style, children: children));
  }
  return spans;
}

/// Tap handlers for the links in a message, one per link, kept so they
/// can be disposed with the widget that draws the message.
class LinkTaps {
  LinkTaps(this.onOpen);

  /// Called with the link that was tapped.
  final void Function(Uri uri) onOpen;

  final _taps = <Uri, TapGestureRecognizer>{};

  TapGestureRecognizer recognizer(Uri uri) => _taps.putIfAbsent(
    uri,
    () => TapGestureRecognizer()..onTap = () => onOpen(uri),
  );

  void dispose() {
    for (final tap in _taps.values) {
      tap.dispose();
    }
    _taps.clear();
  }
}

/// [text] split so each whole-word [nick] gets [style].
List<InlineSpan> _highlighted(String text, String nick, TextStyle? style) {
  final pattern = RegExp(
    r'(?<![\w\[\]\\`^{}|-])'
    '${RegExp.escape(nick)}'
    r'(?![\w\[\]\\`^{}|-])',
    caseSensitive: false,
  );
  final spans = <InlineSpan>[];
  var at = 0;
  for (final m in pattern.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    spans.add(TextSpan(text: m[0], style: style));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

/// Whether messages show mIRC colours and styles (Appearance). Put above
/// the message list; read with [MircColours.of].
class MircColours extends InheritedWidget {
  const MircColours({required this.enabled, required super.child, super.key});

  final bool enabled;

  /// True when there's no setting above (tests, previews).
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MircColours>()?.enabled ??
      true;

  @override
  bool updateShouldNotify(MircColours old) => old.enabled != enabled;
}
