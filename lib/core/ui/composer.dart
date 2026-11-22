/// Where messages are written: a rounded field with a + button and Send,
/// completion chips for `@nick`, `/command` and `#room`, and the reply and
/// upload notes above it.
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:irc_client/core/irc/completions.dart';
import 'package:irc_client/core/irc/formatting.dart';
import 'package:irc_client/core/theme/tokens.dart';
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
  final _controller = TextEditingController();
  final _focus = FocusNode();
  List<Completion> _completions = const [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateCompletions);
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
                  const SizedBox(width: 6),
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
