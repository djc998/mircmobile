/// Where messages are written: a rounded field with a + button and Send,
/// completion chips for `@nick`, `/command` and `#room`, and the reply and
/// upload notes above it.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:irc_client/core/irc/completions.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/irc/mirc_compose.dart';
import 'package:irc_client/core/irc/mirc_format.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/mirc_text.dart';
import 'package:material_ui/material_ui.dart';

/// A command the + menu can start, e.g. `/me` "Describe an action".
class ComposerCommand {
  const ComposerCommand(this.command, this.label, this.icon);

  /// Written into the field, e.g. `/me `.
  final String command;
  final String label;
  final IconData icon;
}

/// Commands the + menu offers in rooms and private chats.
const List<ComposerCommand> composerCommands = [
  ComposerCommand('/me ', 'Describe an action (/me)', Icons.emoji_people),
  ComposerCommand('/topic ', 'Change the topic (/topic)', Icons.title),
  ComposerCommand('/join #', 'Join a room (/join)', Icons.add_comment_outlined),
  ComposerCommand('/msg ', 'Private message (/msg)', Icons.mail_outline),
  ComposerCommand('/nick ', 'Change nickname (/nick)', Icons.edit),
  ComposerCommand('/whois ', 'Look someone up (/whois)', Icons.info_outline),
];

/// A change to the field's text and selection.
typedef _Edit = TextEditingValue Function(TextEditingValue value);

class Composer extends StatefulWidget {
  const Composer({
    required this.onSubmit,
    this.hint = 'Message',
    this.replyTo,
    this.replyText = '',
    this.onCancelReply,
    this.onAttach,
    this.uploading = false,
    this.nicks = const [],
    this.rooms = const [],
    this.commands = composerCommands,
    super.key,
  });

  final void Function(String text) onSubmit;

  /// Placeholder, e.g. `Message #flutter`.
  final String hint;

  /// Who is being replied to; shows "Replying to …" above the field.
  final String? replyTo;
  final String replyText;
  final VoidCallback? onCancelReply;

  /// Adds "Send a picture" to the + menu when set.
  final VoidCallback? onAttach;

  /// A picture is being uploaded.
  final bool uploading;

  /// Names `@` and Tab complete to.
  final List<String> nicks;

  /// Rooms `#` completes to.
  final List<String> rooms;

  /// What the + menu offers besides a picture.
  final List<ComposerCommand> commands;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _controller = MircEditingController();
  final _focus = FocusNode();
  List<Completion> _completions = const [];

  /// The field has formatting codes: show the preview line.
  bool _formatted = false;

  @override
  void initState() {
    super.initState();
    _controller
      ..addListener(_updateCompletions)
      ..addListener(() {
        final has = hasMircCodes(_controller.text);
        // While formatted, every edit changes the preview.
        if (has || has != _formatted) setState(() => _formatted = has);
      });
  }

  @override
  void didUpdateWidget(Composer old) {
    super.didUpdateWidget(old);
    if (widget.replyTo != null && widget.replyTo != old.replyTo) {
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _updateCompletions() {
    final sel = _controller.selection;
    final next = sel.isValid && sel.isCollapsed
        ? completionsFor(
            _controller.text,
            sel.baseOffset,
            nicks: widget.nicks,
            rooms: widget.rooms,
          )
        : const <Completion>[];
    if (!_sameCompletions(next, _completions)) {
      setState(() => _completions = next);
    }
  }

  static bool _sameCompletions(List<Completion> a, List<Completion> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _apply(Completion c) {
    final (text, cursor) = applyCompletion(
      _controller.text,
      _controller.selection.baseOffset,
      c,
    );
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _focus.requestFocus();
  }

  void _insert(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _focus.requestFocus();
  }

  /// Tab completes a nickname, as in mIRC.
  void _complete() {
    final done = completeNick(_controller.text, widget.nicks);
    if (done == null) return;
    _insert(done);
  }

  /// Shift+Enter: a line break where the cursor is.
  void _newLine() {
    final v = _controller.value;
    final sel = v.selection.isValid
        ? v.selection
        : TextSelection.collapsed(offset: v.text.length);
    final text = v.text.replaceRange(sel.start, sel.end, '\n');
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: sel.start + 1),
    );
  }

  /// Applies a formatting change to the field and keeps typing there.
  void _format(_Edit change) {
    _controller.value = change(_controller.value);
    _focus.requestFocus();
  }

  /// Bold, italic, underline, strikethrough, colours and reset, applied to
  /// the selected text or to what's typed next.
  Future<void> _showFormat() async {
    final picked =
        await showModalBottomSheet<TextEditingValue Function(TextEditingValue)>(
          context: context,
          showDragHandle: true,
          builder: (sheet) {
            final tokens = AppTokens.of(sheet);
            Widget style(MircStyle s, TextStyle look, String letter) => Tooltip(
              message: s.label,
              child: Semantics(
                button: true,
                label: s.label,
                excludeSemantics: true,
                child: InkResponse(
                  radius: 26,
                  onTap: () =>
                      Navigator.pop<_Edit>(sheet, (v) => applyStyle(v, s)),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Text(
                        letter,
                        style: look.copyWith(
                          fontSize: 20,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _controller.selection.isValid &&
                              !_controller.selection.isCollapsed
                          ? 'Format the selected text'
                          : 'Format what you type next',
                      style: TypeScale.meta.copyWith(color: tokens.textMuted),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        style(
                          MircStyle.bold,
                          const TextStyle(fontWeight: FontWeight.w800),
                          'B',
                        ),
                        style(
                          MircStyle.italic,
                          const TextStyle(fontStyle: FontStyle.italic),
                          'I',
                        ),
                        style(
                          MircStyle.underline,
                          const TextStyle(decoration: TextDecoration.underline),
                          'U',
                        ),
                        style(
                          MircStyle.strike,
                          const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          ),
                          'S',
                        ),
                        const Spacer(),
                        TextButton.icon(
                          icon: const Icon(Icons.format_clear),
                          label: const Text('Plain'),
                          onPressed: () => Navigator.pop(sheet, applyReset),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Colour',
                      style: TypeScale.meta.copyWith(
                        color: tokens.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      children: [
                        for (var i = 0; i < mircBaseColors.length; i++)
                          Tooltip(
                            message: mircColorNames[i],
                            child: Semantics(
                              button: true,
                              label: '${mircColorNames[i]} text',
                              excludeSemantics: true,
                              child: InkResponse(
                                radius: 24,
                                onTap: () => Navigator.pop<_Edit>(
                                  sheet,
                                  (v) => applyColor(v, i),
                                ),
                                child: SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: Center(
                                    child: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        color: mircBaseColors[i],
                                        shape: BoxShape.circle,
                                        border: Border.all(color: tokens.line),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
    if (picked != null) _format(picked);
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    widget.onSubmit(text);
    _controller.clear();
    _focus.requestFocus();
  }

  Future<void> _showMenu() async {
    final picked = await showModalBottomSheet<VoidCallback>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.onAttach != null)
                ListTile(
                  leading: const Icon(Icons.add_photo_alternate_outlined),
                  title: const Text('Send a picture'),
                  enabled: !widget.uploading,
                  onTap: () => Navigator.pop(sheet, widget.onAttach),
                ),
              for (final c in widget.commands)
                ListTile(
                  leading: Icon(c.icon),
                  title: Text(c.label),
                  onTap: () => Navigator.pop(sheet, () => _insert(c.command)),
                ),
            ],
          ),
        ),
      ),
    );
    picked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Codes show as small muted letters in the field.
    _controller.markerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: tokens.readable(tokens.textMuted, tokens.surfaceOverlay),
      backgroundColor: tokens.surfaceOverlay,
    );
    final mac = Theme.of(context).platform == TargetPlatform.macOS;
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
    final reply = widget.replyTo;
    final circle = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radius(18)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.uploading)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 12, 0),
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Encrypting and sending picture…',
                    style: TypeScale.meta.copyWith(color: tokens.textMuted),
                  ),
                ],
              ),
            ),
          ),
        if (reply != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
              ),
              padding: const EdgeInsets.fromLTRB(12, 2, 2, 2),
              child: Row(
                children: [
                  Icon(Icons.reply, size: 18, color: tokens.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Replying to $reply',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (widget.replyText.isNotEmpty)
                            TextSpan(text: ': ${widget.replyText}'),
                        ],
                      ),
                      style: TypeScale.meta.copyWith(
                        color: tokens.textPrimary,
                        fontSize: 13,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancel reply',
                    iconSize: 18,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onCancelReply,
                  ),
                ],
              ),
            ),
          ),
        // The codes are invisible in the field, so show how it will look.
        if (_formatted)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
            child: Semantics(
              label: 'Preview',
              child: Text.rich(
                TextSpan(
                  style: TypeScale.body.copyWith(color: tokens.textPrimary),
                  children: [
                    TextSpan(
                      text: 'Preview  ',
                      style: TypeScale.meta.copyWith(
                        color: tokens.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    ...mircSpans(
                      _controller.text,
                      tokens: tokens,
                      background: tokens.surface,
                      textColor: tokens.textPrimary,
                    ),
                  ],
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (_completions.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
              children: [
                for (final c in _completions)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ActionChip(
                      label: Text(c.label),
                      tooltip: 'Insert ${c.label}',
                      onPressed: () => _apply(c),
                    ),
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              border: Border.all(color: tokens.line),
              borderRadius: BorderRadius.circular(
                tokens.radius(Radii.composer + 4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: widget.onAttach != null
                        ? 'Add a picture or command'
                        : 'Add a command',
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.surfaceOverlay,
                      foregroundColor: tokens.textPrimary,
                      shape: circle,
                      fixedSize: const Size(36, 36),
                      minimumSize: const Size(36, 36),
                    ),
                    iconSize: 18,
                    icon: const Icon(Icons.add),
                    onPressed: () => unawaited(_showMenu()),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.tab):
                            _complete,
                        // Computers: Enter sends, Shift+Enter starts a new
                        // line. Phones use the keyboard's Send key.
                        if (desktop) ...{
                          for (final (key, style) in [
                            (LogicalKeyboardKey.keyB, MircStyle.bold),
                            (LogicalKeyboardKey.keyI, MircStyle.italic),
                            (LogicalKeyboardKey.keyU, MircStyle.underline),
                          ])
                            SingleActivator(
                              key,
                              meta: mac,
                              control: !mac,
                            ): () =>
                                _format((v) => applyStyle(v, style)),
                          const SingleActivator(LogicalKeyboardKey.enter):
                              _send,
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            shift: true,
                          ): _newLine,
                        },
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        minLines: 1,
                        maxLines: 5,
                        style: TypeScale.body.copyWith(
                          color: tokens.textPrimary,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: reply == null
                              ? widget.hint
                              : 'Reply to $reply',
                          hintStyle: TypeScale.body.copyWith(
                            color: tokens.textMuted,
                          ),
                          hintMaxLines: 1,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Format text',
                    color: tokens.textMuted,
                    iconSize: 20,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(36, 36),
                      minimumSize: const Size(36, 36),
                    ),
                    icon: const Icon(Icons.text_format),
                    onPressed: () => unawaited(_showFormat()),
                  ),
                  IconButton(
                    tooltip: 'Send',
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.accent,
                      foregroundColor: tokens.onAccent,
                      shape: circle,
                      fixedSize: const Size(36, 36),
                      minimumSize: const Size(36, 36),
                    ),
                    iconSize: 18,
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
