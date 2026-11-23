/// Getting a photo to send: from the photo library, or by taking one with
/// the camera. Phones use the system camera; the Mac, which the system
/// picker can't open the camera on, gets [CameraCaptureScreen].
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

/// Where a photo comes from.
enum PhotoSource { library, camera }

/// Gets a photo's bytes from [source], or null when the user cancels.
/// Throws when the library or camera can't be opened.
typedef PhotoPicker = Future<Uint8List?> Function(
  BuildContext context,
  PhotoSource source,
);

/// The [PhotoPicker] the app uses; tests replace it.
final photoPickerProvider = Provider<PhotoPicker>((ref) => pickPhoto);

/// Whether this device can take a photo in the app.
bool canTakePhotos(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.android || TargetPlatform.macOS => true,
  _ => false,
};

/// The real [PhotoPicker].
Future<Uint8List?> pickPhoto(BuildContext context, PhotoSource source) async {
  if (source == PhotoSource.camera &&
      Theme.of(context).platform == TargetPlatform.macOS) {
    return await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CameraCaptureScreen(),
      ),
    );
  }
  // The platform shrinks big photos first; the app then strips metadata.
  final file = await ImagePicker().pickImage(
    source: source == PhotoSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 90,
  );
  return await file?.readAsBytes();
}

/// A camera preview with a shutter button, then the photo with Retake and
/// Use photo. Pops with the photo's bytes, or null.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({super.key});

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  final _renderer = RTCVideoRenderer();
  MediaStream? _stream;
  Uint8List? _photo;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _renderer.initialize();
      final stream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        },
      });
      if (!mounted) {
        await _stop(stream);
        return;
      }
      _stream = stream;
      _renderer.srcObject = stream;
      setState(() {});
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              "Couldn't open the camera. Allow IRCage to use it in System "
              'Settings → Privacy & Security → Camera.',
        );
      }
    }
  }

  Future<void> _shoot() async {
    final track = _stream?.getVideoTracks().firstOrNull;
    if (track == null || _busy) return;
    setState(() => _busy = true);
    try {
      final frame = await track.captureFrame();
      if (mounted) setState(() => _photo = frame.asUint8List());
    } on Object {
      if (mounted) setState(() => _error = "Couldn't take the photo.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static Future<void> _stop(MediaStream stream) async {
    for (final t in stream.getTracks()) {
      await t.stop();
    }
    await stream.dispose();
  }

  @override
  void dispose() {
    final stream = _stream;
    if (stream != null) unawaited(_stop(stream));
    unawaited(_renderer.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo;
    final error = _error;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Take a photo'),
        leading: IconButton(
          tooltip: 'Cancel',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: error != null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      )
                    : photo != null
                    ? Image.memory(photo, fit: BoxFit.contain)
                    : _stream == null
                    ? const CircularProgressIndicator()
                    : RTCVideoView(_renderer, mirror: true),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: photo != null
                  ? OverflowBar(
                      alignment: MainAxisAlignment.center,
                      spacing: 16,
                      overflowSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white54),
                          ),
                          icon: const Icon(Icons.replay),
                          label: const Text('Retake'),
                          onPressed: () => setState(() => _photo = null),
                        ),
                        FilledButton.icon(
                          icon: const Icon(Icons.check),
                          label: const Text('Use photo'),
                          onPressed: () => Navigator.pop(context, photo),
                        ),
                      ],
                    )
                  : Semantics(
                      button: true,
                      label: 'Take photo',
                      excludeSemantics: true,
                      child: Tooltip(
                        message: 'Take photo',
                        child: InkResponse(
                          onTap: error == null && _stream != null
                              ? _shoot
                              : null,
                          radius: 40,
                          child: Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            padding: const EdgeInsets.all(5),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: error == null && _stream != null
                                    ? Colors.white
                                    : Colors.white24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
