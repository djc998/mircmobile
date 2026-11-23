/// Sending and saving short-lived, encrypted files in a private chat.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/file_link.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A file the user picked: its name and bytes.
typedef PickedFile = ({String name, Uint8List bytes});

/// Opens the system file picker; null when cancelled.
typedef FilePicker = Future<PickedFile?> Function();

/// Saves [bytes] as [name] the platform's way; returns where (for the
/// message), or null when the user cancelled.
typedef FileSaver = Future<String?> Function(
  BuildContext context,
  String name,
  Uint8List bytes,
);

/// The picker and saver the app uses; tests replace them.
final filePickerProvider = Provider<FilePicker>((ref) => _pickFile);
final fileSaverProvider = Provider<FileSaver>((ref) => _saveFile);

Future<PickedFile?> _pickFile() async {
  final file = await openFile();
  if (file == null) return null;
  return (name: file.name, bytes: await file.readAsBytes());
}

/// Mac: a save dialog. iPhone and Android: the share sheet, which has
/// "Save to Files" (or Drive, Downloads…) and other apps.
Future<String?> _saveFile(
  BuildContext context,
  String name,
  Uint8List bytes,
) async {
  if (Platform.isMacOS) {
    final where = await getSaveLocation(suggestedName: name);
    if (where == null) return null;
    await File(where.path).writeAsBytes(bytes);
    return where.path;
  }
  final dir = await getTemporaryDirectory();
  final temp = File('${dir.path}/$name');
  await temp.writeAsBytes(bytes);
  final box = context.mounted ? context.findRenderObject() : null;
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(temp.path, name: name)],
      sharePositionOrigin: box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    ),
  );
  return result.status == ShareResultStatus.dismissed ? null : name;
}

/// Picks a file, asks how long it should last, then sends it.
Future<void> sendFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!ref.read(pictureServiceProvider).isConfigured) {
    messenger.showSnackBar(
      const SnackBar(content: Text("File sharing isn't set up yet.")),
    );
    return;
  }
  final PickedFile? chosen;
  try {
    chosen = await ref.read(filePickerProvider)();
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open your files.")),
    );
    return;
  }
  final picked = chosen;
  if (picked == null || !context.mounted) return;
  if (picked.bytes.length > maxFileBytes) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${safeFileName(picked.name)} is '
          '${formatFileSize(picked.bytes.length)}. Files can be 25 MB at '
          'most.',
        ),
      ),
    );
    return;
  }
  final expiry = await showModalBottomSheet<PictureExpiry>(
    context: context,
    showDragHandle: true,
    builder: (_) => _SendFileSheet(
      name: safeFileName(picked.name),
      size: picked.bytes.length,
    ),
  );
  if (expiry == null) return;
  final error = await ref
      .read(chatControllerProvider.notifier)
      .sendFile(picked.bytes, name: picked.name, expiry: expiry);
  if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
}

class _SendFileSheet extends StatefulWidget {
  const _SendFileSheet({required this.name, required this.size});

  final String name;
  final int size;

  @override
  State<_SendFileSheet> createState() => _SendFileSheetState();
}

class _SendFileSheetState extends State<_SendFileSheet> {
  PictureExpiry _expiry = PictureExpiry.fourHours;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Send a file',
              style: TypeScale.title.copyWith(color: tokens.textPrimary),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(widget.name),
              subtitle: Text(formatFileSize(widget.size)),
            ),
            Text(
              'Encrypted on this device. The link stops working after:',
              style: TypeScale.body.copyWith(color: tokens.textMuted),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final e in PictureExpiry.values)
                  ChoiceChip(
                    label: Text(e.label),
                    selected: _expiry == e,
                    onSelected: (_) => setState(() => _expiry = e),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send file'),
              onPressed: () => Navigator.pop(context, _expiry),
            ),
          ],
        ),
      ),
    );
  }
}

/// A file in the chat: its name and size, and Save (download, decrypt,
/// then save the platform's way).
class FileBubble extends ConsumerStatefulWidget {
  const FileBubble({
    required this.link,
    required this.sender,
    required this.isOwn,
    this.indent = 48,
    super.key,
  });

  final FileLink link;
  final String sender;
  final bool isOwn;

  /// Space on the leading side, to line up under the message text.
  final double indent;

  @override
  ConsumerState<FileBubble> createState() => _FileBubbleState();
}

class _FileBubbleState extends ConsumerState<FileBubble> {
  bool _busy = false;

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await ref
          .read(pictureServiceProvider)
          .downloadFile(widget.link);
      if (!mounted) return;
      final where = await ref.read(fileSaverProvider)(
        context,
        widget.link.name,
        bytes,
      );
      if (where != null) {
        messenger.showSnackBar(
          SnackBar(content: Text('Saved ${widget.link.name}.')),
        );
      }
    } on PictureException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't save ${widget.link.name}.")),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final link = widget.link;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: widget.indent, top: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Material(
            color: tokens.surfaceRaised,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: tokens.line),
              borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined, color: tokens.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          link.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.body.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          widget.isOwn
                              ? '${formatFileSize(link.size)} · sent'
                              : '${formatFileSize(link.size)} · from '
                                    '${widget.sender}',
                          style: TypeScale.meta.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  else
                    TextButton(
                      onPressed: _save,
                      child: Text('Save', semanticsLabel: 'Save ${link.name}'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
