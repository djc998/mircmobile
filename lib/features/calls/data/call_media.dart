/// Camera, microphone and the peer-to-peer connection for a call (WebRTC).
///
/// Behind an interface so the call logic can be tested without real devices.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:irc_client/features/calls/data/call_api.dart';
import 'package:material_ui/material_ui.dart';

enum CallMediaState { connecting, connected, failed }

abstract interface class CallMedia {
  /// Turns on the microphone (and camera for [video]) and prepares the
  /// connection. With [relayOnly] traffic always goes through the relay,
  /// so the other person never learns this device's IP address.
  Future<void> open({
    required bool video,
    required List<Map<String, Object?>> iceServers,
    required bool relayOnly,
  });

  /// Local connection candidates to send to the other side.
  Stream<Map<String, Object?>> get candidates;
  Stream<CallMediaState> get states;

  Future<Map<String, Object?>> createOffer();
  Future<Map<String, Object?>> answer(Map<String, Object?> offer);
  Future<void> acceptAnswer(Map<String, Object?> answer);
  Future<void> addCandidate(Map<String, Object?> candidate);

  void setMuted({required bool muted});
  void setCameraOn({required bool on});
  Future<void> switchCamera();
  Future<void> setSpeaker({required bool on});

  /// Video views; empty boxes for voice calls.
  Widget localView();
  Widget remoteView();

  Future<void> close();
}

typedef CallMediaFactory = CallMedia Function();

final callMediaFactoryProvider = Provider<CallMediaFactory>(
  (ref) => WebRtcCallMedia.new,
);

class WebRtcCallMedia implements CallMedia {
  RTCPeerConnection? _pc;
  MediaStream? _local;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;
  final _candidates = StreamController<Map<String, Object?>>.broadcast();
  final _states = StreamController<CallMediaState>.broadcast();
  // Candidates that arrive before the other side's description.
  final _early = <RTCIceCandidate>[];
  bool _haveRemote = false;

  @override
  Stream<Map<String, Object?>> get candidates => _candidates.stream;

  @override
  Stream<CallMediaState> get states => _states.stream;

  @override
  Future<void> open({
    required bool video,
    required List<Map<String, Object?>> iceServers,
    required bool relayOnly,
  }) async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
    _renderersReady = true;
    try {
      _local = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': video ? {'facingMode': 'user'} : false,
      });
    } on Object {
      throw DevicesBlockedException(video: video);
    }
    _localRenderer.srcObject = _local;
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      if (relayOnly) 'iceTransportPolicy': 'relay',
    });
    _pc = pc;
    for (final track in _local!.getTracks()) {
      await pc.addTrack(track, _local!);
    }
    pc
      ..onIceCandidate = (c) {
        if (c.candidate == null) return;
        _candidates.add({
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        });
      }
      ..onTrack = (event) {
        if (event.streams.isNotEmpty) {
          _remoteRenderer.srcObject = event.streams.first;
        }
      }
      ..onConnectionState = (s) {
        if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _states.add(CallMediaState.connected);
        } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _states.add(CallMediaState.failed);
        }
      };
  }

  RTCPeerConnection get _peer {
    final pc = _pc;
    if (pc == null) throw StateError('Call media is not open');
    return pc;
  }

  static Map<String, Object?> _description(RTCSessionDescription d) => {
    'type': d.type,
    'sdp': d.sdp,
  };

  static RTCSessionDescription _toDescription(Map<String, Object?> m) =>
      RTCSessionDescription(m['sdp'] as String?, m['type'] as String?);

  Future<void> _remoteSet() async {
    _haveRemote = true;
    for (final c in _early) {
      await _peer.addCandidate(c);
    }
    _early.clear();
  }

  @override
  Future<Map<String, Object?>> createOffer() async {
    final offer = await _peer.createOffer();
    await _peer.setLocalDescription(offer);
    return _description(offer);
  }

  @override
  Future<Map<String, Object?>> answer(Map<String, Object?> offer) async {
    await _peer.setRemoteDescription(_toDescription(offer));
    await _remoteSet();
    final answer = await _peer.createAnswer();
    await _peer.setLocalDescription(answer);
    return _description(answer);
  }

  @override
  Future<void> acceptAnswer(Map<String, Object?> answer) async {
    await _peer.setRemoteDescription(_toDescription(answer));
    await _remoteSet();
  }

  @override
  Future<void> addCandidate(Map<String, Object?> candidate) async {
    final c = RTCIceCandidate(
      candidate['candidate'] as String?,
      candidate['sdpMid'] as String?,
      (candidate['sdpMLineIndex'] as num?)?.toInt(),
    );
    if (_haveRemote) {
      await _peer.addCandidate(c);
    } else {
      _early.add(c);
    }
  }

  @override
  void setMuted({required bool muted}) {
    for (final t in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
  }

  @override
  void setCameraOn({required bool on}) {
    for (final t in _local?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = on;
    }
  }

  @override
  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? const <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } on Object {
      // Only one camera (e.g. on a Mac).
    }
  }

  @override
  Future<void> setSpeaker({required bool on}) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } on Object {
      // Not available on this platform (e.g. macOS).
    }
  }

  @override
  Widget localView() => _renderersReady
      ? RTCVideoView(
          _localRenderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        )
      : const SizedBox.shrink();

  @override
  Widget remoteView() =>
      _renderersReady ? RTCVideoView(_remoteRenderer) : const SizedBox.shrink();

  @override
  Future<void> close() async {
    for (final t in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _local?.dispose();
    _local = null;
    await _pc?.close();
    _pc = null;
    if (_renderersReady) {
      _localRenderer.srcObject = null;
      _remoteRenderer.srcObject = null;
      await _localRenderer.dispose();
      await _remoteRenderer.dispose();
      _renderersReady = false;
    }
    await _candidates.close();
    await _states.close();
  }
}
