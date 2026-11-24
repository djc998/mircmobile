/// The preview under a message that links to an image or a video.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/links/chat_link.dart';
import 'package:irc_client/core/links/open_link.dart';
import 'package:irc_client/features/links/data/link_media_service.dart';
import 'package:irc_client/features/pictures/presentation/picture_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

/// Whether videos can play inside the app here. Windows and Linux open
/// them in the browser instead.
bool get inlineVideoSupported =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.android ||
      TargetPlatform.macOS => true,
      _ => false,
    };

/// An image or video someone linked to, under their message.
///
/// Nothing is loaded until it's tapped, unless [autoShow] (your own
/// links, or "Show images from links automatically"). Loading it lets
/// the website see your IP address, which is why that's off by default.
/// Videos always wait for a tap.
class LinkPreview extends ConsumerStatefulWidget {
  const LinkPreview({
    required this.uri,
    required this.media,
    required this.sender,
    this.autoShow = false,
    this.indent = 48,
    super.key,
  });

  final Uri uri;
  final LinkMedia media;
  final String sender;
  final bool autoShow;

  /// Space on the leading side, to line up under the message text.
  final double indent;

  @override
  ConsumerState<LinkPreview> createState() => _LinkPreviewState();
}

class _LinkPreviewState extends ConsumerState<LinkPreview> {
  Future<Uint8List>? _image;
  VideoPlayerController? _video;
  Future<void>? _videoReady;

  LinkMediaService get _service => ref.read(linkMediaServiceProvider);

  String get _host => widget.uri.host;

  @override
  void initState() {
    super.initState();
    if (widget.media == LinkMedia.image) {
      final cached = _service.cached(widget.uri);
      if (cached != null) {
        _image = Future.value(cached);
      } else if (widget.autoShow) {
        _image = _service.fetchImage(widget.uri);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_video?.dispose());
    super.dispose();
  }

  void _show() {
    switch (widget.media) {
      case LinkMedia.image:
        final load = _service.fetchImage(widget.uri);
        setState(() {
          _image = load;
        });
      case LinkMedia.video:
        if (!inlineVideoSupported) {
          unawaited(_open());
          return;
        }
        final video = VideoPlayerController.networkUrl(widget.uri);
        final ready = video.initialize().then((_) => video.play());
        setState(() {
          _video = video;
          _videoReady = ready;
        });
    }
  }

  Future<void> _open() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await openLink(widget.uri)) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open the link.")),
      );
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.uri.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Link copied')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget body;
    final image = _image;
    final video = _video;
    if (image != null) {
      body = _imageBody(image);
    } else if (video != null) {
      body = _videoBody(video);
    } else {
      final isImage = widget.media == LinkMedia.image;
      body = OutlinedButton.icon(
        icon: Icon(
          isImage
              ? Icons.image_outlined
              : inlineVideoSupported
              ? Icons.play_circle_outline
              : Icons.open_in_new,
        ),
        label: Text(
          isImage
              ? 'Show image from $_host'
              : inlineVideoSupported
              ? 'Play video from $_host'
              : 'Open video from $_host',
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: _show,
      );
    }
    return Padding(
      padding: EdgeInsetsDirectional.only(
        top: 4,
        bottom: 4,
        start: widget.indent,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(child: body),
          PopupMenuButton<String>(
            tooltip: 'Link options',
            icon: Icon(Icons.more_vert, color: theme.hintColor, size: 20),
            onSelected: (v) {
              if (v == 'open') unawaited(_open());
              if (v == 'copy') unawaited(_copy());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'open', child: Text('Open in browser')),
              PopupMenuItem(value: 'copy', child: Text('Copy link')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageBody(Future<Uint8List> load) => FutureBuilder<Uint8List>(
    future: load,
    builder: (context, snap) {
      if (snap.hasError) {
        final error = snap.error;
        return _note(
          context,
          Icons.hide_image_outlined,
          error is LinkMediaException
              ? error.message
              : "Couldn't load the image.",
        );
      }
      final bytes = snap.data;
      if (bytes == null) return _loading();
      final dpr = MediaQuery.devicePixelRatioOf(context);
      return GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => PictureViewer(
              picture: bytes,
              sender: widget.sender,
              source: _host,
            ),
          ),
        ),
        child: Semantics(
          label:
              'Image from $_host, linked by ${widget.sender}. '
              'Tap to view full size.',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                // Decode small: a huge image would use a lot of memory.
                cacheWidth: (320 * dpr).round(),
                errorBuilder: (context, _, _) => _note(
                  context,
                  Icons.hide_image_outlined,
                  "That image can't be shown.",
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _videoBody(VideoPlayerController video) => FutureBuilder<void>(
    future: _videoReady,
    builder: (context, snap) {
      if (snap.hasError) {
        return _note(
          context,
          Icons.videocam_off_outlined,
          "Couldn't play the video. Try Open in browser.",
        );
      }
      if (snap.connectionState != ConnectionState.done) return _loading();
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 400),
          child: AspectRatio(
            aspectRatio: video.value.aspectRatio,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                VideoPlayer(video),
                _PlayPause(video: video),
                VideoProgressIndicator(video, allowScrubbing: true),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _loading() => const SizedBox(
    width: 160,
    height: 120,
    child: Center(child: CircularProgressIndicator.adaptive()),
  );

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

/// Tap anywhere on the video to pause or play; the button shows while
/// paused.
class _PlayPause extends StatelessWidget {
  const _PlayPause({required this.video});

  final VideoPlayerController video;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: video,
    builder: (context, value, _) => Semantics(
      button: true,
      label: value.isPlaying ? 'Pause video' : 'Play video',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(value.isPlaying ? video.pause() : video.play()),
        child: Center(
          child: AnimatedOpacity(
            opacity: value.isPlaying ? 0 : 1,
            duration: const Duration(milliseconds: 150),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
