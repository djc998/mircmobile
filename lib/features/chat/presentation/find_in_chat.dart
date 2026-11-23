/// Search the open conversation (Cmd+F on a Mac, the search button
/// elsewhere).
library;

import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Lines in [lines] whose text or sender contains [query] (any case),
/// newest first.
List<ChatLine> findInLines(List<ChatLine> lines, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  return [
    for (final l in lines.reversed)
      if (stripFormatting(l.text).toLowerCase().contains(q) ||
          (l.sender?.toLowerCase().contains(q) ?? false))
        l,
  ];
}

String _when(BuildContext context, DateTime time) {
  final t = time.toLocal();
  final date = MaterialLocalizations.of(context).formatShortDate(t);
  return '$date · ${TimeOfDay.fromDateTime(t).format(context)}';
}

/// A search box over [buffer]'s messages, with matches listed newest first.
Future<void> showFindInChat(BuildContext context, ChatBuffer buffer) =>
    showDialog<void>(
      context: context,
      builder: (_) => _FindInChat(buffer: buffer),
    );

class _FindInChat extends StatefulWidget {
  const _FindInChat({required this.buffer});

  final ChatBuffer buffer;

  @override
  State<_FindInChat> createState() => _FindInChatState();
}

class _FindInChatState extends State<_FindInChat> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final chat = ChatColors.of(context);
    final matches = findInLines(widget.buffer.lines, _query);
    final name = widget.buffer.isStatus
        ? 'server messages'
        : widget.buffer.name;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Search $name',
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            if (_query.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    matches.isEmpty
                        ? 'No matches'
                        : '${matches.length} '
                              '${matches.length == 1 ? 'match' : 'matches'}',
                    style: TypeScale.meta.copyWith(color: tokens.textMuted),
                  ),
                ),
              ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final l in matches)
                    ListTile(
                      dense: true,
                      title: Text.rich(
                        TextSpan(
                          children: [
                            if (l.sender != null)
                              TextSpan(
                                text: '${l.sender}  ',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: chat.nickColor(l.sender!),
                                ),
                              ),
                            TextSpan(text: stripFormatting(l.text)),
                          ],
                        ),
                      ),
                      subtitle: Text(_when(context, l.time)),
                    ),
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
