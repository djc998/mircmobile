/// Sending and saving short-lived, encrypted files in a private chat.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/temp_files.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/dcc_transfer.dart';
import 'package:irc_client/features/pictures/domain/file_link.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

/// A file the user picked: its name and bytes.
typedef PickedFile = ({String name, Uint8List bytes});

/// Opens the system file picker; null when cancelled.
typedef FilePicker = Future<PickedFile?> Function();

/// Saves [file] as [name] the platform's way; returns where (for the
/// message), or null when the user cancelled.
typedef FileSaver = Future<String?> Function(
  BuildContext context,
  String name,
  File file,
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
Future<String?> _saveFile(BuildContext context, String name, File file) async {
  if (Platform.isMacOS) {
    final where = await getSaveLocation(suggestedName: name);
    if (where == null) return null;
    await file.copy(where.path);
    return where.path;
  }
  final box = context.mounted ? context.findRenderObject() : null;
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, name: name)],
      sharePositionOrigin: box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    ),
  );
  return result.status == ShareResultStatus.dismissed ? null : name;
}

/// Writes [bytes] to a fresh temporary file named [name].
Future<File> writeTempFile(String name, List<int> bytes) async {
  final dir = await tempFolder('files');
  final file = File(
    '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-${safeFileName(name)}',
  );
  return await file.writeAsBytes(bytes);
}

/// Picks a file, asks how long it should last, then sends it.
Future<void> sendFile(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
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
  final serverReady = ref.read(pictureServiceProvider).isConfigured;
  final choice = await showModalBottomSheet<_SendChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SendFileSheet(
      name: safeFileName(picked.name),
      size: picked.bytes.length,
      serverReady: serverReady,
    ),
  );
  if (choice == null) return;
  final controller = ref.read(chatControllerProvider.notifier);
  final String? error;
  if (choice.direct) {
    final file = await writeTempFile(picked.name, picked.bytes);
    error = await controller.sendDccFile(file, name: picked.name);
  } else {
    error = await controller.sendFile(
      picked.bytes,
      name: picked.name,
      expiry: choice.expiry,
    );
  }
  if (error != null) messenger.showSnackBar(SnackBar(content: Text(error)));
}

/// How to send: through the server for `expiry`, or `direct` (DCC).
typedef _SendChoice = ({bool direct, PictureExpiry expiry});

class _SendFileSheet extends StatefulWidget {
  const _SendFileSheet({
    required this.name,
    required this.size,
    required this.serverReady,
  });

  final String name;
  final int size;

  /// The file server is set up (otherwise only direct sending is offered).
  final bool serverReady;

  @override
  State<_SendFileSheet> createState() => _SendFileSheetState();
}

class _SendFileSheetState extends State<_SendFileSheet> {
  PictureExpiry _expiry = PictureExpiry.fourHours;
  late bool _direct = !widget.serverReady || widget.size > maxFileBytes;

  bool get _serverAllowed => widget.serverReady && widget.size <= maxFileBytes;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final muted = TypeScale.body.copyWith(color: tokens.textMuted);
    return SafeArea(
      child: SingleChildScrollView(
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
            RadioGroup<bool>(
              groupValue: _direct,
              onChanged: (v) => setState(() => _direct = v ?? _direct),
              child: Column(
                children: [
                  RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: false,
                    enabled: _serverAllowed,
                    title: const Text('Through the server'),
                    subtitle: Text(
                      widget.serverReady
                          ? widget.size > maxFileBytes
                                ? 'For files up to 25 MB'
                                : 'Encrypted, works on any network'
                          : "File sharing isn't set up",
                    ),
                  ),
                  const RadioListTile<bool>(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    title: Text('Directly (DCC)'),
                    subtitle: Text(
                      'Works with mIRC and HexChat. Shows them your IP '
                      'address, and usually only works on the same Wi-Fi',
                    ),
                  ),
                ],
              ),
            ),
            if (!_direct) ...[
              const SizedBox(height: 4),
              Text('The link stops working after:', style: muted),
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
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send file'),
              onPressed: () =>
                  Navigator.pop(context, (direct: _direct, expiry: _expiry)),
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
      final file = await writeTempFile(widget.link.name, bytes);
      if (!mounted) return;
      final where = await ref.read(fileSaverProvider)(
        context,
        widget.link.name,
        file,
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

/// A direct (DCC) transfer in the chat: Accept or Decline an incoming
/// offer (with what it means for your IP), progress, then Save.
class DccCard extends ConsumerWidget {
  const DccCard({required this.id, this.indent = 48, super.key});

  final String id;

  /// Space on the leading side, to line up under the message text.
  final double indent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final t = controller.transfer(id);
    final tokens = AppTokens.of(context);
    final muted = TypeScale.meta.copyWith(color: tokens.textMuted);
    if (t == null) return const SizedBox.shrink();
    final size = t.size > 0 ? formatFileSize(t.size) : 'unknown size';
    final status = switch (t.state) {
      DccState.offered => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sent directly. Accepting connects to ${t.nick}, who will see '
            'your IP address. Only accept files from people you trust.',
            style: muted,
          ),
          const SizedBox(height: 4),
          OverflowBar(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => controller.declineDcc(id),
                child: Text('Decline', semanticsLabel: 'Decline ${t.name}'),
              ),
              FilledButton(
                onPressed: () => unawaited(controller.acceptDcc(id)),
                child: Text('Accept', semanticsLabel: 'Accept ${t.name}'),
              ),
            ],
          ),
        ],
      ),
      DccState.waiting => Text(
        'Waiting for ${t.nick} to accept (2 minutes)…',
        style: muted,
      ),
      DccState.transferring => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: t.progress),
          const SizedBox(height: 4),
          Text(
            '${t.incoming ? 'Receiving' : 'Sending'} '
            '${formatFileSize(t.done)} of $size',
            style: muted,
          ),
        ],
      ),
      DccState.done when t.incoming => Row(
        children: [
          Expanded(child: Text('Received', style: muted)),
          TextButton(
            onPressed: () async {
              final file = t.file;
              if (file == null) return;
              final messenger = ScaffoldMessenger.of(context);
              final where = await ref.read(fileSaverProvider)(
                context,
                t.name,
                file,
              );
              if (where != null) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Saved ${t.name}.')),
                );
              }
            },
            child: Text('Save', semanticsLabel: 'Save ${t.name}'),
          ),
        ],
      ),
      DccState.done => Text('Sent', style: muted),
      DccState.declined => Text('Declined', style: muted),
      DccState.failed => Text(
        t.error ?? "The transfer didn't work.",
        style: muted.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    };
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, top: 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Material(
            color: tokens.surfaceRaised,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: tokens.line),
              borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.swap_horiz, color: tokens.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${t.name} · $size',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TypeScale.body.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  status,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
