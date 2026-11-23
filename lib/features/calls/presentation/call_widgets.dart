/// The ringing banner, the call screen and the call buttons.
library;

import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/platform/privacy_settings.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
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

/// Whether the call screen is shrunk to the green pill so you can chat
/// during a call.
final callMinimizedProvider = NotifierProvider<_Minimized, bool>(
  _Minimized.new,
);

class _Minimized extends Notifier<bool> {
  @override
  bool build() {
    // A new call (or the end of one) shows the full call screen again.
    ref.listen(callControllerProvider.select((c) => c.phase), (prev, next) {
      if (next == CallPhase.ended || next == CallPhase.outgoing) {
        state = false;
      }
    });
    return false;
  }

  // A plain setter reads better than a method here.
  // ignore: use_setters_to_change_properties
  void set(bool value) => state = value;
}

class _CallLayer extends ConsumerWidget {
  const _CallLayer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(callControllerProvider);
    final minimized = ref.watch(callMinimizedProvider);
    return Stack(
      children: [
        if (call.phase == CallPhase.incoming)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(child: _IncomingCallCard(call: call)),
          ),
        if ((call.inCall && !minimized) || call.phase == CallPhase.ended)
          Positioned.fill(child: CallScreen(call: call)),
        if (call.inCall && minimized)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: _InCallPill(call: call),
              ),
            ),
          ),
      ],
    );
  }
}

/// `03:12` for a call that has been on for 3 minutes 12 seconds.
String callDuration(DateTime? startedAt, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(
    startedAt ?? now ?? DateTime.now(),
  );
  final m = (d.inMinutes % 60).toString().padLeft(2, '0');
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return '${d.inHours > 0 ? '${d.inHours}:' : ''}$m:$s';
}

/// The green pill at the top while you chat during a call; tap it to go
/// back to the call.
class _InCallPill extends ConsumerStatefulWidget {
  const _InCallPill({required this.call});

  final CallState call;

  @override
  ConsumerState<_InCallPill> createState() => _InCallPillState();
}

class _InCallPillState extends ConsumerState<_InCallPill> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final call = widget.call;
    final time = call.phase == CallPhase.active
        ? callDuration(call.startedAt)
        : 'Connecting…';
    // Dark text on the green pill reads in both modes.
    const fg = Color(0xFF0F1117);
    final bg = Color.lerp(tokens.success, Colors.white, 0.15)!;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Semantics(
        button: true,
        label: 'In a call with ${call.peer}, $time. Back to the call',
        excludeSemantics: true,
        child: Material(
          color: bg,
          shape: const StadiumBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: () => ref.read(callMinimizedProvider.notifier).set(false),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 36),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      call.video ? Icons.videocam : Icons.call,
                      size: 16,
                      color: fg,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${call.peer} · $time',
                      style: const TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Someone is calling: their avatar and name, the kind of call, and big
/// Decline (red) and Accept (green) buttons.
class _IncomingCallCard extends ConsumerWidget {
  const _IncomingCallCard({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callControllerProvider.notifier);
    final tokens = AppTokens.of(context);
    final kind = call.video ? 'video' : 'voice';
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Semantics(
          liveRegion: true,
          label: '${call.peer} is calling you ($kind)',
          child: Material(
            elevation: 12,
            color: tokens.surfaceRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tokens.radius(20)),
              side: BorderSide(color: tokens.line),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  NickAvatar(nick: call.peer, size: 52),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${call.peer} is calling you ($kind)',
                          style: TypeScale.heading.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                        Text(
                          'Incoming ${call.video ? 'video' : 'voice'} call',
                          style: TypeScale.meta.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _AnswerButton(
                    label: 'Decline',
                    icon: Icons.call_end,
                    color: const Color(0xFFD93A3A),
                    onPressed: () => unawaited(controller.decline()),
                  ),
                  const SizedBox(width: 12),
                  _AnswerButton(
                    label: 'Accept',
                    icon: call.video ? Icons.videocam : Icons.call,
                    color: const Color(0xFF1A8F5C),
                    onPressed: () => unawaited(controller.accept()),
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

/// A round red or green button with its label under it.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // The circle and its label are one button.
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: Colors.white),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TypeScale.meta.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
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
    // The "call ended" note goes away on its own, unless it explains how
    // to allow the camera and microphone.
    if (widget.call.phase == CallPhase.ended &&
        old.call.phase != CallPhase.ended &&
        !widget.call.devicesBlocked) {
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
        return callDuration(call.startedAt);
      case CallPhase.ended:
        return call.endedReason ?? 'Call ended';
      case CallPhase.idle || CallPhase.incoming:
        return '';
    }
  }

  /// Where your own preview sits; dragged around and snapped to a corner.
  Alignment _selfCorner = Alignment.bottomRight;
  Offset? _dragOffset;

  static const _selfSize = Size(112, 152);

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final controller = ref.read(callControllerProvider.notifier);
    final media = controller.media;
    final showRemoteVideo =
        call.video && call.phase == CallPhase.active && media != null;
    final ended = call.phase == CallPhase.ended;
    // The call stage is always dark, whatever the app's mode.
    final dark = AppTheme.build(ThemePreset.indigo, Brightness.dark);
    final tokens = dark.extension<AppTokens>()!;
    return Theme(
      data: dark,
      child: Material(
        color: const Color(0xFF07080C),
        child: Stack(
          children: [
            if (showRemoteVideo)
              Positioned.fill(child: media.remoteView())
            else
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      colors: [
                        Color.alphaBlend(tokens.accentSoft, tokens.surface),
                        const Color(0xFF07080C),
                      ],
                      radius: 0.9,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        NickAvatar(nick: call.peer, size: 120),
                        const SizedBox(height: 18),
                        Text(
                          call.peer,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: Row(
                      children: [
                        if (!ended)
                          IconButton(
                            tooltip: 'Back to chat',
                            color: Colors.white,
                            icon: const Icon(Icons.keyboard_arrow_down),
                            onPressed: () => ref
                                .read(callMinimizedProvider.notifier)
                                .set(true),
                          )
                        else
                          const SizedBox(width: 48),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              showRemoteVideo
                                  ? '${call.peer} · $_status'
                                  : _status,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
                  if (call.relayOnly &&
                      !call.ipHidden &&
                      !ended &&
                      media != null)
                    const Positioned(
                      top: 60,
                      left: 16,
                      right: 16,
                      child: Text(
                        "The call relay isn't set up yet, so this call "
                        'connects directly and the other person can see '
                        'your IP address.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amberAccent,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  if (call.video && call.cameraOn && !ended && media != null)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, box) => Stack(
                          children: [_selfView(box.biggest, media.localView())],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: ended
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (call.devicesBlocked)
                                DeviceAccessHelp(video: call.video, dark: true),
                              TextButton(
                                onPressed: controller.dismiss,
                                child: const Text('Close'),
                              ),
                            ],
                          )
                        : Center(child: _Controls(call: call)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Your own camera, 12-pt corners, draggable; it snaps to the nearest
  /// corner, clear of the controls.
  Widget _selfView(Size area, Widget view) {
    const margin = 16.0;
    const controlsHeight = 120.0;
    final maxX = area.width - _selfSize.width - margin;
    final maxY = area.height - _selfSize.height - controlsHeight;
    final corner = Offset(
      _selfCorner.x < 0 ? margin : maxX,
      _selfCorner.y < 0 ? 72 : maxY,
    );
    final at = _dragOffset ?? corner;
    return AnimatedPositioned(
      duration: _dragOffset == null ? Motion.of(context) : Duration.zero,
      curve: Motion.curve,
      left: at.dx,
      top: at.dy,
      width: _selfSize.width,
      height: _selfSize.height,
      child: Semantics(
        label: 'Your camera. Drag to move it.',
        child: GestureDetector(
          onPanUpdate: (d) =>
              setState(() => _dragOffset = (_dragOffset ?? corner) + d.delta),
          onPanEnd: (_) => setState(() {
            final o = _dragOffset ?? corner;
            final centre = o + _selfSize.center(Offset.zero);
            _selfCorner = Alignment(
              centre.dx < area.width / 2 ? -1 : 1,
              centre.dy < area.height / 2 ? -1 : 1,
            );
            _dragOffset = null;
          }),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 12),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ColoredBox(color: Colors.white10, child: view),
            ),
          ),
        ),
      ),
    );
  }
}

/// Mute, camera, switch camera, speaker and the red Hang up, on a blurred
/// pill.
class _Controls extends ConsumerWidget {
  const _Controls({required this.call});

  final CallState call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(callControllerProvider.notifier);
    final mobile =
        Theme.of(context).platform == TargetPlatform.iOS ||
        Theme.of(context).platform == TargetPlatform.android;
    return ClipRRect(
      borderRadius: BorderRadius.circular(44),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(44),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
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
                color: const Color(0xFFD93A3A),
                onPressed: () => unawaited(controller.hangUp()),
              ),
            ],
          ),
        ),
      ),
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

/// Explains how to allow the camera and microphone, with buttons that open
/// the right system settings page.
class DeviceAccessHelp extends ConsumerWidget {
  const DeviceAccessHelp({this.video = true, this.dark = false, super.key});

  /// Mention the camera too (video calls).
  final bool video;

  /// Light text, for the black call screen.
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(privacySettingsProvider);
    final messenger = ScaffoldMessenger.maybeOf(context);
    Future<void> open(PrivacyPage page) async {
      final opened = await settings.open(page);
      if (!opened) {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't open Settings. Open it yourself and allow the "
              'camera and microphone for this app.',
            ),
          ),
        );
      }
    }

    final what = video ? 'camera and microphone' : 'microphone';
    final style = dark ? const TextStyle(color: Colors.white70) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            settings.separatePages
                ? 'Allow the $what for irc_client in System Settings, '
                      'then call again.'
                : 'Allow the $what for this app in Settings, then call '
                      'again.',
            textAlign: TextAlign.center,
            style: style,
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: settings.separatePages
                ? [
                    if (video)
                      FilledButton.icon(
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('Open Camera settings'),
                        onPressed: () => open(PrivacyPage.camera),
                      ),
                    FilledButton.icon(
                      icon: const Icon(Icons.mic_none),
                      label: const Text('Open Microphone settings'),
                      onPressed: () => open(PrivacyPage.microphone),
                    ),
                  ]
                : [
                    FilledButton.icon(
                      icon: const Icon(Icons.settings_outlined),
                      label: const Text('Open Settings'),
                      onPressed: () => open(PrivacyPage.camera),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}
