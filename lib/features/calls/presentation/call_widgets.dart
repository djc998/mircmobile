/// The ringing banner, the call screen and the call buttons.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/features/calls/application/call_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Call buttons for the app bar of a private chat.
List<Widget> callButtons(BuildContext context, WidgetRef ref) {
  Future<void> start({required bool video}) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await ref
        .read(callControllerProvider.notifier)
        .startCall(video: video);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  return [
    IconButton(
      tooltip: 'Voice call',
      icon: const Icon(Icons.call_outlined),
      onPressed: () => unawaited(start(video: false)),
    ),
    IconButton(
      tooltip: 'Video call',
      icon: const Icon(Icons.videocam_outlined),
      onPressed: () => unawaited(start(video: true)),
    ),
  ];
}

/// Puts the ringing banner and the call screen above every page. It has its
/// own [Overlay] because it sits above the app's navigator (tooltips and
/// text fields need one).
class CallOverlay extends StatefulWidget {
  const CallOverlay({required this.child, super.key});

  final Widget child;

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  final _entry = OverlayEntry(builder: (_) => const _CallLayer());

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      Positioned.fill(child: Overlay(initialEntries: [_entry])),
    ],
  );
}

class _CallLayer extends ConsumerWidget {
  const _CallLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    return Stack(
      children: [
        if (call.phase == CallPhase.incoming)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: _IncomingCallBanner(call: call)),
          ),
        if (call.inCall || call.phase == CallPhase.ended)
          Positioned.fill(child: CallScreen(call: call)),
      ],
    );
  }
}

class _IncomingCallBanner extends ConsumerWidget {
  const _IncomingCallBanner({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callControllerProvider.notifier);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: theme.colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Icon(
                call.video ? Icons.videocam : Icons.call,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${call.peer} is calling you '
                  '(${call.video ? 'video' : 'voice'})',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: () => unawaited(controller.decline()),
                child: const Text('Decline'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                icon: Icon(call.video ? Icons.videocam : Icons.call),
                label: const Text('Accept'),
                onPressed: () => unawaited(controller.accept()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The full-screen call: the other person's video (or name), your own
/// preview, and the controls.
class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({required this.call, super.key});

  final CallState call;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.call.phase == CallPhase.active) setState(() {});
    });
  }

  @override
  void didUpdateWidget(CallScreen old) {
    super.didUpdateWidget(old);
    // The "call ended" note goes away on its own.
    if (widget.call.phase == CallPhase.ended &&
        old.call.phase != CallPhase.ended) {
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted) ref.read(callControllerProvider.notifier).dismiss();
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _status {
    final call = widget.call;
    switch (call.phase) {
      case CallPhase.outgoing:
        return 'Calling ${call.peer}…';
      case CallPhase.connecting:
        return 'Connecting…';
      case CallPhase.active:
        final d = DateTime.now().difference(call.startedAt ?? DateTime.now());
        final m = d.inMinutes.toString().padLeft(2, '0');
        final s = (d.inSeconds % 60).toString().padLeft(2, '0');
        return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
      case CallPhase.ended:
        return call.endedReason ?? 'Call ended';
      case CallPhase.idle || CallPhase.incoming:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final controller = ref.read(callControllerProvider.notifier);
    final media = controller.media;
    final showRemoteVideo =
        call.video && call.phase == CallPhase.active && media != null;
    final ended = call.phase == CallPhase.ended;
    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            if (showRemoteVideo)
              Positioned.fill(child: media.remoteView())
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 48,
                      child: Text(
                        call.peer.isEmpty ? '?' : call.peer[0].toUpperCase(),
                        style: const TextStyle(fontSize: 40),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      call.peer,
                      style: const TextStyle(color: Colors.white, fontSize: 28),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Text(
                showRemoteVideo ? '${call.peer} · $_status' : _status,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ),
            if (call.relayOnly && !call.ipHidden && !ended && media != null)
              const Positioned(
                top: 44,
                left: 16,
                right: 16,
                child: Text(
                  "The call relay isn't set up yet, so this call connects "
                  'directly and the other person can see your IP address.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.amberAccent, fontSize: 13),
                ),
              ),
            if (call.video && call.cameraOn && !ended && media != null)
              Positioned(
                right: 16,
                bottom: 112,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.white10,
                    child: media.localView(),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: ended
                  ? Center(
                      child: TextButton(
                        onPressed: controller.dismiss,
                        child: const Text('Close'),
                      ),
                    )
                  : _Controls(call: call),
            ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends ConsumerWidget {
  const _Controls({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callControllerProvider.notifier);
    final mobile =
        Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        _RoundButton(
          tooltip: call.muted ? 'Unmute' : 'Mute',
          icon: call.muted ? Icons.mic_off : Icons.mic,
          selected: call.muted,
          onPressed: controller.toggleMute,
        ),
        if (call.video)
          _RoundButton(
            tooltip: call.cameraOn ? 'Turn camera off' : 'Turn camera on',
            icon: call.cameraOn ? Icons.videocam : Icons.videocam_off,
            selected: !call.cameraOn,
            onPressed: controller.toggleCamera,
          ),
        if (call.video && mobile)
          _RoundButton(
            tooltip: 'Switch camera',
            icon: Icons.cameraswitch,
            onPressed: () => unawaited(controller.switchCamera()),
          ),
        if (mobile)
          _RoundButton(
            tooltip: call.speakerOn ? 'Speaker off' : 'Speaker on',
            icon: call.speakerOn ? Icons.volume_up : Icons.hearing,
            selected: call.speakerOn,
            onPressed: () => unawaited(controller.toggleSpeaker()),
          ),
        _RoundButton(
          tooltip: 'Hang up',
          icon: Icons.call_end,
          color: Colors.red.shade700,
          onPressed: () => unawaited(controller.hangUp()),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      tooltip: tooltip,
      iconSize: 28,
      style: IconButton.styleFrom(
        fixedSize: const Size(64, 64),
        backgroundColor: color ?? (selected ? Colors.white : Colors.white24),
        foregroundColor: selected && color == null
            ? Colors.black
            : Colors.white,
      ),
      onPressed: onPressed,
      icon: Icon(icon),
    );
  }
}
