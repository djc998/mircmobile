/// Sending and showing short-lived, encrypted pictures in a conversation.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:material_ui/material_ui.dart';

/// Picks a photo, asks how long it should last, then sends it.
Future<void> sendPicture(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!ref.read(pictureServiceProvider).isConfigured) {
    messenger.showSnackBar(
      const SnackBar(content: Text("Picture sharing isn't set up yet.")),
    );
    return;
  }
  final phone = switch (Theme.of(context).platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    _ => false,
  };
  var source = ImageSource.gallery;
  if (phone) {
    final picked = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose a photo'),
              onTap: () => Navigator.pop(sheet, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(sheet, ImageSource.camera),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    source = picked;
  }
  final XFile? file;
  try {
    // The platform shrinks big photos first; the app then strips metadata.
    file = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
  } on Object {
    messenger.showSnackBar(
      const SnackBar(content: Text("Couldn't open your photos.")),
    );
    return;
  }
  if (file == null) return;
  final bytes = await file.readAsBytes();
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<_SendChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _SendPictureSheet(picture: bytes),
  );
  if (choice == null) return;
  final error = await ref
      .read(chatControllerProvider.notifier)
      .sendPicture(bytes, expiry: choice.expiry, viewOnce: choice.viewOnce);
  if (error != null) {
    messenger.showSnackBar(SnackBar(content: Text(error)));
  }
}

class _SendChoice {
  const _SendChoice(this.expiry, {required this.viewOnce});

  final PictureExpiry expiry;
  final bool viewOnce;
}

class _SendPictureSheet extends StatefulWidget {
  const _SendPictureSheet({required this.picture});

  final Uint8List picture;

  @override
  State<_SendPictureSheet> createState() => _SendPictureSheetState();
}

class _SendPictureSheetState extends State<_SendPictureSheet> {
  PictureExpiry _expiry = PictureExpiry.fourHours;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send a picture', style: theme.textTheme.titleLarge),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: Image.memory(widget.picture, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 16),
            Text('Disappears after', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in PictureExpiry.values)
                  ChoiceChip(
                    label: Text(e.label),
                    selected: _expiry == e,
                    onSelected: (_) => setState(() => _expiry = e),
                  ),
              ],
            ),
            Text(
              'View once: the picture is deleted as soon as it has been '
              'opened, or when the time runs out. It is encrypted on this '
              'device and location data is removed. Only people with the '
              'link can see it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send picture'),
              onPressed: () =>
                  Navigator.pop(context, _SendChoice(_expiry, viewOnce: true)),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shared picture inside a message.
///
/// Pictures load straight away only when [autoShow] is true (your own, or
/// from someone you've written to). Otherwise the user taps first, because
/// loading a picture tells its server your IP address. View-once pictures
/// always wait for a tap.
class PictureBubble extends ConsumerStatefulWidget {
  const PictureBubble({
    required this.link,
    required this.sender,
    required this.networkId,
    required this.isOwn,
    required this.autoShow,
    super.key,
  });

  final PictureLink link;
  final String sender;
  final String networkId;
  final bool isOwn;
  final bool autoShow;

  @override
  ConsumerState<PictureBubble> createState() => _PictureBubbleState();
}

class _PictureBubbleState extends ConsumerState<PictureBubble> {
  Future<Uint8List>? _load;
  bool _reported = false;

  PictureService get _service => ref.read(pictureServiceProvider);

  @override
  void initState() {
    super.initState();
    final cached = _service.cached(widget.link);
    if (cached != null) {
      _load = Future.value(cached);
    } else if (widget.autoShow && !widget.link.viewOnce) {
      _load = _service.download(widget.link);
    }
  }

  void _show() {
    final load = _service.download(widget.link);
    setState(() {
      _load = load;
    });
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (_) => _ReportDialog(sender: widget.sender),
    );
    if (reason == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _reported = true);
    final error = await ref
        .read(chatControllerProvider.notifier)
        .reportPicture(
          widget.link,
          sender: widget.sender,
          networkId: widget.networkId,
          reason: reason,
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          error ??
              "Thanks, it's been reported. You won't see messages from "
                  '${widget.sender} anymore.',
        ),
      ),
    );
  }

  void _block() {
    ref.read(chatControllerProvider.notifier).blockUser(widget.sender);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("You won't see messages from ${widget.sender}.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final load = _load;
    Widget body;
    if (_reported) {
      body = _note(context, Icons.flag_outlined, 'Picture reported');
    } else if (load == null) {
      body = widget.isOwn && widget.link.viewOnce
          ? _note(context, Icons.visibility_off_outlined, 'View-once picture')
          : OutlinedButton.icon(
              icon: const Icon(Icons.image_outlined),
              label: Text(
                widget.link.viewOnce
                    ? 'Open photo from ${widget.sender}'
                    : 'Show photo from ${widget.sender}',
              ),
              onPressed: _show,
            );
    } else {
      body = FutureBuilder<Uint8List>(
        future: load,
        builder: (context, snap) {
          if (snap.hasError) {
            final error = snap.error;
            return _note(
              context,
              Icons.hide_image_outlined,
              error is PictureException
                  ? error.message
                  : "Couldn't load the picture.",
            );
          }
          final bytes = snap.data;
          if (bytes == null) {
            return const SizedBox(
              width: 160,
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) =>
                    PictureViewer(picture: bytes, sender: widget.sender),
              ),
            ),
            child: Semantics(
              label: 'Picture from ${widget.sender}. Tap to view full size.',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 240,
                    maxWidth: 320,
                  ),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
            ),
          );
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4, left: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: body),
          if (!widget.isOwn && !_reported)
            PopupMenuButton<String>(
              tooltip: 'Picture options',
              icon: Icon(Icons.more_vert, color: theme.hintColor, size: 20),
              onSelected: (v) {
                if (v == 'report') unawaited(_report());
                if (v == 'block') _block();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report picture'),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Text('Block ${widget.sender}'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _note(BuildContext context, IconData icon, String text) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: muted),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: TextStyle(color: muted)),
        ),
      ],
    );
  }
}

class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.sender});

  final String sender;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  static const _reasons = [
    'Nudity or sexual content',
    'Harassment or hate',
    'Violence',
    'Spam or scam',
    'Something else',
  ];
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Report picture'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The picture is sent for review and ${widget.sender} is '
              'blocked, so you stop seeing their messages.',
            ),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final r in _reasons)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      title: Text(r),
                      value: r,
                    ),
                ],
              ),
            ),
            TextField(
              controller: _details,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Details (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _reason == null
              ? null
              : () => Navigator.pop(
                  context,
                  [
                    _reason!,
                    _details.text.trim(),
                  ].where((s) => s.isNotEmpty).join(': '),
                ),
          child: const Text('Report'),
        ),
      ],
    );
  }
}

/// Full-screen picture with pinch to zoom.
class PictureViewer extends StatelessWidget {
  const PictureViewer({required this.picture, required this.sender, super.key});

  final Uint8List picture;
  final String sender;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('From $sender'),
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(child: Image.memory(picture)),
      ),
    );
  }
}
