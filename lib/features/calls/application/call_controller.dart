/// Runs one voice or video call at a time: ringing, connecting, the call
/// itself and hanging up.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/calls/data/call_api.dart';
import 'package:irc_client/features/calls/data/call_media.dart';
import 'package:irc_client/features/calls/domain/call_link.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';

enum CallPhase {
  idle,

  /// Someone is calling us; Accept / Decline.
  incoming,

  /// We are calling someone and waiting for them to answer.
  outgoing,

  /// Both sides are in; audio and video are being connected.
  connecting,
  active,

  /// The call is over; [CallState.endedReason] says why.
  ended,
}

class CallState {
  const CallState({
    this.phase = CallPhase.idle,
    this.link,
    this.peer = '',
    this.networkId,
    this.video = false,
    this.muted = false,
    this.cameraOn = true,
    this.speakerOn = true,
    this.startedAt,
    this.endedReason,
    this.relayOnly = true,
    this.ipHidden = false,
  });

  final CallPhase phase;
  final CallLink? link;

  /// The other person's nick.
  final String peer;
  final String? networkId;
  final bool video;
  final bool muted;
  final bool cameraOn;
  final bool speakerOn;

  /// When both sides were connected, for the call timer.
  final DateTime? startedAt;
  final String? endedReason;

  /// "Hide my IP on calls": always go through the relay.
  final bool relayOnly;

  /// This call goes through the relay, so the other person can't see our
  /// IP address. False when the setting is off or no relay is set up.
  final bool ipHidden;

  bool get inCall =>
      phase == CallPhase.outgoing ||
      phase == CallPhase.connecting ||
      phase == CallPhase.active;

  CallState copyWith({
    CallPhase? phase,
    bool? muted,
    bool? cameraOn,
    bool? speakerOn,
    DateTime? startedAt,
    String? endedReason,
    bool? relayOnly,
    bool? ipHidden,
  }) => CallState(
    phase: phase ?? this.phase,
    link: link,
    peer: peer,
    networkId: networkId,
    video: video,
    muted: muted ?? this.muted,
    cameraOn: cameraOn ?? this.cameraOn,
    speakerOn: speakerOn ?? this.speakerOn,
    startedAt: startedAt ?? this.startedAt,
    endedReason: endedReason ?? this.endedReason,
    relayOnly: relayOnly ?? this.relayOnly,
    ipHidden: ipHidden ?? this.ipHidden,
  );
}

final callControllerProvider = NotifierProvider<CallController, CallState>(
  CallController.new,
);

class CallController extends Notifier<CallState> {
  static const _relayKey = 'callsRelayOnly';

  CallMedia? _media;
  CallSignaling? _signaling;
  final _subs = <StreamSubscription<Object?>>[];
  // Signaling messages are handled one at a time, in order.
  Future<void> _queue = Future.value();
  // Bumped for every call so late callbacks from an old call are ignored.
  int _generation = 0;

  CallApi get _api => ref.read(callApiProvider);
  KeyValueStore get _store => ref.read(keyValueStoreProvider);

  @override
  CallState build() {
    ref.onDispose(() => unawaited(_teardown()));
    return CallState(relayOnly: _store.getString(_relayKey) != 'false');
  }

  Future<void> setRelayOnly({required bool enabled}) async {
    state = state.copyWith(relayOnly: enabled);
    await _store.setString(_relayKey, '$enabled');
  }

  /// Calls the person in the open private chat. Returns a message to show
  /// when it can't.
  Future<String?> startCall({required bool video}) async {
    if (state.inCall || state.phase == CallPhase.incoming) {
      return "You're already in a call.";
    }
    final chat = ref.read(chatControllerProvider);
    final session = chat.activeNetwork;
    final buffer = chat.activeBuffer;
    if (session == null ||
        buffer == null ||
        buffer.isStatus ||
        buffer.isChannel) {
      return 'Open a private chat to call someone.';
    }
    if (!_api.isConfigured) return "Calls aren't set up yet.";
    final generation = ++_generation;
    final peer = buffer.name;
    try {
      final link = await _api.create(video: video);
      if (generation != _generation) return null;
      state = CallState(
        phase: CallPhase.outgoing,
        link: link,
        peer: peer,
        networkId: session.id,
        video: video,
        cameraOn: video,
        speakerOn: video,
        relayOnly: state.relayOnly,
      );
      await _openMedia(link, video: video);
      await _connect(link, generation);
      final sent = ref
          .read(chatControllerProvider.notifier)
          .sendPrivateText(session.id, peer, link.message(session.nick));
      if (!sent) {
        await _end('Not connected to ${session.label}.');
        return 'Not connected to ${session.label}.';
      }
      return null;
    } on CallException catch (e) {
      if (generation == _generation) await _end(e.message);
      return e.message;
    }
  }

  /// Someone sent us a call link in a private chat.
  void ring(CallLink link, {required String from, required String networkId}) {
    if (state.inCall || state.phase == CallPhase.incoming) {
      // Busy: let the caller know rather than ringing over a call.
      if (state.link != link) unawaited(_api.decline(link));
      return;
    }
    _generation++;
    state = CallState(
      phase: CallPhase.incoming,
      link: link,
      peer: from,
      networkId: networkId,
      video: link.video,
      cameraOn: link.video,
      speakerOn: link.video,
      relayOnly: state.relayOnly,
    );
  }

  Future<void> accept() async {
    final link = state.link;
    if (state.phase != CallPhase.incoming || link == null) return;
    final generation = ++_generation;
    state = state.copyWith(phase: CallPhase.connecting);
    try {
      await _openMedia(link, video: link.video);
      await _connect(link, generation);
    } on CallException catch (e) {
      if (generation == _generation) await _end(e.message);
    }
  }

  Future<void> decline() async {
    final link = state.link;
    if (state.phase != CallPhase.incoming || link == null) return;
    _generation++;
    state = CallState(relayOnly: state.relayOnly);
    await _api.decline(link);
  }

  Future<void> hangUp() async {
    if (!state.inCall) return;
    _signaling?.send(const {'type': 'bye'});
    await _end('Call ended');
  }

  /// Clears the "call ended" screen.
  void dismiss() {
    if (state.phase == CallPhase.ended) {
      state = CallState(relayOnly: state.relayOnly);
    }
  }

  void toggleMute() {
    final muted = !state.muted;
    _media?.setMuted(muted: muted);
    state = state.copyWith(muted: muted);
  }

  void toggleCamera() {
    if (!state.video) return;
    final on = !state.cameraOn;
    _media?.setCameraOn(on: on);
    state = state.copyWith(cameraOn: on);
  }

  Future<void> switchCamera() async => await _media?.switchCamera();

  Future<void> toggleSpeaker() async {
    final on = !state.speakerOn;
    state = state.copyWith(speakerOn: on);
    await _media?.setSpeaker(on: on);
  }

  CallMedia? get media => _media;

  Future<void> _openMedia(CallLink link, {required bool video}) async {
    final ice = await _api.ice(link);
    final media = ref.read(callMediaFactoryProvider)();
    _media = media;
    final hidden = state.relayOnly && ice.relay;
    await media.open(video: video, iceServers: ice.servers, relayOnly: hidden);
    state = state.copyWith(ipHidden: hidden);
    await media.setSpeaker(on: state.speakerOn);
    _subs
      ..add(
        media.candidates.listen(
          (c) => _signaling?.send({'type': 'ice', 'candidate': c}),
        ),
      )
      ..add(
        media.states.listen((s) {
          switch (s) {
            case CallMediaState.connected:
              if (state.phase == CallPhase.connecting) {
                state = state.copyWith(
                  phase: CallPhase.active,
                  startedAt: DateTime.now(),
                );
              }
            case CallMediaState.failed:
              unawaited(_end("The call couldn't connect."));
            case CallMediaState.connecting:
              break;
          }
        }),
      );
  }

  Future<void> _connect(CallLink link, int generation) async {
    final signaling = await ref.read(callSignalingFactoryProvider)(link);
    if (generation != _generation) {
      await signaling.close();
      return;
    }
    _signaling = signaling;
    _subs.add(
      signaling.messages.listen((msg) {
        _queue = _queue.then((_) async {
          if (generation != _generation) return;
          try {
            await _handle(msg);
          } on Object {
            await _end("The call couldn't connect.");
          }
        });
      }),
    );
  }

  Future<void> _handle(Map<String, Object?> msg) async {
    final media = _media;
    if (media == null) return;
    switch (msg['type']) {
      case 'joined':
        // The other person picked up: we make the offer.
        state = state.copyWith(phase: CallPhase.connecting);
        _signaling?.send({
          'type': 'offer',
          'description': await media.createOffer(),
        });
      case 'offer':
        final offer = msg['description'];
        if (offer is Map<String, Object?>) {
          _signaling?.send({
            'type': 'answer',
            'description': await media.answer(offer),
          });
        }
      case 'answer':
        final answer = msg['description'];
        if (answer is Map<String, Object?>) await media.acceptAnswer(answer);
      case 'ice':
        final candidate = msg['candidate'];
        if (candidate is Map<String, Object?>) {
          await media.addCandidate(candidate);
        }
      case 'declined':
        await _end('${state.peer} declined the call');
      case 'timeout':
        await _end('No answer');
      case 'bye' || 'closed':
        await _end('Call ended');
    }
  }

  Future<void> _end(String reason) async {
    if (state.phase == CallPhase.ended || state.phase == CallPhase.idle) {
      await _teardown();
      return;
    }
    _generation++;
    state = state.copyWith(phase: CallPhase.ended, endedReason: reason);
    await _teardown();
  }

  Future<void> _teardown() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    final signaling = _signaling;
    _signaling = null;
    final media = _media;
    _media = null;
    await signaling?.close();
    await media?.close();
  }
}
