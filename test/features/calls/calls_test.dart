import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/platform/privacy_settings.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/calls/application/call_controller.dart';
import 'package:irc_client/features/calls/data/call_api.dart';
import 'package:irc_client/features/calls/data/call_media.dart';
import 'package:irc_client/features/calls/domain/call_link.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:material_ui/material_ui.dart';

class FakeTransport implements IrcTransport {
  final StreamController<String> incoming = StreamController<String>();
  final List<String> written = [];

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) => written.add(line);

  @override
  Future<void> close() async {}
}

class FakeSignaling implements CallSignaling {
  final _messages = StreamController<Map<String, Object?>>.broadcast();
  final sent = <Map<String, Object?>>[];
  bool closed = false;

  void receive(Map<String, Object?> msg) => _messages.add(msg);

  @override
  Stream<Map<String, Object?>> get messages => _messages.stream;

  @override
  void send(Map<String, Object?> message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await _messages.close();
  }
}

class FakePrivacySettings implements PrivacySettings {
  FakePrivacySettings({this.separatePages = true});

  @override
  final bool separatePages;
  final opened = <PrivacyPage>[];

  @override
  Future<bool> open(PrivacyPage page) async {
    opened.add(page);
    return true;
  }
}

/// Media whose camera and microphone are blocked by the system.
bool blockDevices = false;

class FakeMedia implements CallMedia {
  final _candidates = StreamController<Map<String, Object?>>.broadcast();
  final _states = StreamController<CallMediaState>.broadcast();
  bool? openedVideo;
  bool? relayOnly;
  bool muted = false;
  bool cameraOn = true;
  bool closed = false;
  Map<String, Object?>? remoteAnswer;
  final added = <Map<String, Object?>>[];

  void connect() => _states.add(CallMediaState.connected);
  void candidate(Map<String, Object?> c) => _candidates.add(c);

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
    if (blockDevices) throw DevicesBlockedException(video: video);
    openedVideo = video;
    this.relayOnly = relayOnly;
  }

  @override
  Future<Map<String, Object?>> createOffer() async => {
    'type': 'offer',
    'sdp': 'offer-sdp',
  };

  @override
  Future<Map<String, Object?>> answer(Map<String, Object?> offer) async => {
    'type': 'answer',
    'sdp': 'answer-to-${offer['sdp']}',
  };

  @override
  Future<void> acceptAnswer(Map<String, Object?> answer) async =>
      remoteAnswer = answer;

  @override
  Future<void> addCandidate(Map<String, Object?> candidate) async =>
      added.add(candidate);

  @override
  void setMuted({required bool muted}) => this.muted = muted;

  @override
  void setCameraOn({required bool on}) => cameraOn = on;

  @override
  Future<void> switchCamera() async {}

  @override
  Future<void> setSpeaker({required bool on}) async {}

  @override
  Widget localView() => const SizedBox(key: Key('local-video'));

  @override
  Widget remoteView() => const SizedBox(key: Key('remote-video'));

  @override
  Future<void> close() async => closed = true;
}

const _id = 'abcdefghijklmnopqrstuv';

void main() {
  group('CallLink', () {
    test('finds voice and video links and builds their addresses', () {
      final video = CallLink.find(
        '🎥 Video call from bob: https://pics.test/c/$_id#video',
      )!;
      expect(video.video, isTrue);
      expect(video.id, _id);
      expect('$video', 'https://pics.test/c/$_id#video');
      expect(video.socket, Uri.parse('wss://pics.test/c/$_id/ws'));
      expect(video.ice, Uri.parse('https://pics.test/c/$_id/ice'));
      expect(video.decline, Uri.parse('https://pics.test/c/$_id/decline'));
      expect(
        video.message('dennis'),
        '🎥 Video call from dennis: https://pics.test/c/$_id#video',
      );

      final voice = CallLink.find('call me https://pics.test/c/$_id#voice')!;
      expect(voice.video, isFalse);
      expect(
        voice.message('dennis'),
        '📞 Voice call from dennis: https://pics.test/c/$_id#voice',
      );
    });

    test('ignores other links', () {
      expect(CallLink.find('https://pics.test/c/$_id'), isNull);
      expect(CallLink.find('https://pics.test/p/$_id#k=x'), isNull);
      expect(CallLink.find('https://pics.test/c/short#video'), isNull);
    });
  });

  group('calls', () {
    late FakeTransport transport;
    late FakeSignaling signaling;
    late FakeMedia media;
    late List<http.Request> requests;
    late ProviderContainer container;
    late FakePrivacySettings privacy;

    Future<void> pumpApp(
      WidgetTester tester, {
      bool relay = true,
      bool separatePages = true,
    }) async {
      privacy = FakePrivacySettings(separatePages: separatePages);
      transport = FakeTransport();
      signaling = FakeSignaling();
      media = FakeMedia();
      requests = [];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/call') {
          final video = (jsonDecode(req.body) as Map)['video'] == true;
          return http.Response(
            jsonEncode({
              'id': _id,
              'url': 'https://pics.test/c/$_id#${video ? 'video' : 'voice'}',
            }),
            201,
          );
        }
        if (req.url.path == '/c/$_id/ice') {
          return http.Response(
            jsonEncode({
              'iceServers': [
                {'urls': 'turn:relay.test'},
              ],
              'relay': relay,
            }),
            200,
          );
        }
        if (req.url.path == '/c/$_id/decline') {
          return http.Response('{"ok":true}', 200);
        }
        return http.Response('', 404);
      });
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
            privacySettingsProvider.overrideWithValue(privacy),
            callApiProvider.overrideWithValue(
              CallApi(host: 'https://pics.test', client: client),
            ),
            // A fresh pair for every call; the latest is the one in use.
            callSignalingFactoryProvider.overrideWithValue(
              (link) async => signaling = FakeSignaling(),
            ),
            callMediaFactoryProvider.overrideWithValue(
              () => media = FakeMedia(),
            ),
            transportFactoryProvider.overrideWithValue(
              (host, port, {required useTls, trustedFingerprints = const {}}) =>
                  transport,
            ),
          ],
          child: const IrcApp(),
        ),
      );
      await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
      await tester.tap(find.text('Libera.Chat'));
      await tester.pumpAndSettle();
      transport.incoming
        ..add(':s 001 me :Welcome')
        ..add(':me!u@h JOIN #chat');
      await tester.pumpAndSettle();
      container = ProviderScope.containerOf(
        tester.element(find.byType(IrcApp)),
      );
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('call someone from a private chat', (tester) async {
      await pumpApp(tester);
      // No call buttons in rooms.
      expect(find.byTooltip('Video call'), findsNothing);
      container.read(chatControllerProvider.notifier).openPrivateChat('bob');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Video call'));
      await settle(tester);

      // The link goes to bob as a private message.
      expect(
        transport.written.last,
        'PRIVMSG bob :🎥 Video call from me: https://pics.test/c/$_id#video',
      );
      expect(media.openedVideo, isTrue);
      // "Hide my IP" is on by default and the server offers a relay.
      expect(media.relayOnly, isTrue);
      expect(find.text('Calling bob…'), findsOneWidget);

      // Bob picks up: we send the offer and our candidates.
      signaling.receive({'type': 'joined'});
      await settle(tester);
      expect(signaling.sent.last, {
        'type': 'offer',
        'description': {'type': 'offer', 'sdp': 'offer-sdp'},
      });
      media.candidate({'candidate': 'c1'});
      await settle(tester);
      expect(signaling.sent.last, {
        'type': 'ice',
        'candidate': {'candidate': 'c1'},
      });
      signaling
        ..receive({
          'type': 'answer',
          'description': {'type': 'answer', 'sdp': 'a'},
        })
        ..receive({
          'type': 'ice',
          'candidate': {'candidate': 'c2'},
        });
      await settle(tester);
      expect(media.remoteAnswer, {'type': 'answer', 'sdp': 'a'});
      expect(media.added, [
        {'candidate': 'c2'},
      ]);

      media.connect();
      await settle(tester);
      expect(find.byKey(const Key('remote-video')), findsOneWidget);
      expect(find.byKey(const Key('local-video')), findsOneWidget);

      await tester.tap(find.byTooltip('Mute'));
      await tester.pump();
      expect(media.muted, isTrue);
      await tester.tap(find.byTooltip('Turn camera off'));
      await tester.pump();
      expect(media.cameraOn, isFalse);

      await tester.tap(find.byTooltip('Hang up'));
      await settle(tester);
      expect(signaling.sent.last, {'type': 'bye'});
      expect(media.closed, isTrue);
      expect(signaling.closed, isTrue);
      expect(find.text('Call ended'), findsWidgets);

      // The note closes on its own.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(container.read(callControllerProvider).phase, CallPhase.idle);
    });

    testWidgets('an incoming call rings and can be accepted', (tester) async {
      await pumpApp(tester);
      transport.incoming.add(
        ':bob!b@h PRIVMSG me :📞 Voice call from bob: '
        'https://pics.test/c/$_id#voice',
      );
      await tester.pumpAndSettle();
      expect(find.text('bob is calling you (voice)'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await settle(tester);
      expect(media.openedVideo, isFalse);
      expect(find.text('Connecting…'), findsOneWidget);

      signaling.receive({
        'type': 'offer',
        'description': {'type': 'offer', 'sdp': 'o'},
      });
      await settle(tester);
      expect(signaling.sent.last, {
        'type': 'answer',
        'description': {'type': 'answer', 'sdp': 'answer-to-o'},
      });
      media.connect();
      await settle(tester);
      expect(find.text('00:00'), findsOneWidget);

      // Back to chat shrinks the call to a green pill; tapping it returns.
      await tester.tap(find.byTooltip('Back to chat'));
      await settle(tester);
      expect(find.byTooltip('Hang up'), findsNothing);
      expect(find.text('bob · 00:00'), findsOneWidget);
      await tester.tap(find.text('bob · 00:00'));
      await settle(tester);
      expect(find.byTooltip('Hang up'), findsOneWidget);

      // Bob hangs up.
      signaling.receive({'type': 'bye'});
      await settle(tester);
      expect(find.text('Call ended'), findsWidgets);
      expect(media.closed, isTrue);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('declining tells the server; old links do not ring', (
      tester,
    ) async {
      await pumpApp(tester);
      // A call link from history (server-time hours ago) doesn't ring.
      transport.incoming.add(
        '@time=2020-01-01T00:00:00.000Z :bob!b@h PRIVMSG me :📞 Voice call '
        'from bob: https://pics.test/c/$_id#voice',
      );
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsNothing);
      // Links posted in rooms don't ring either.
      transport.incoming.add(
        ':bob!b@h PRIVMSG #chat :https://pics.test/c/$_id#voice',
      );
      await tester.pumpAndSettle();
      expect(find.text('Accept'), findsNothing);

      transport.incoming.add(
        ':bob!b@h PRIVMSG me :🎥 Video call from bob: '
        'https://pics.test/c/$_id#video',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Decline'));
      await settle(tester);
      expect(requests.last.url.path, '/c/$_id/decline');
      expect(find.text('Accept'), findsNothing);
      expect(container.read(callControllerProvider).phase, CallPhase.idle);
    });

    testWidgets('the caller hears when nobody answers or bob declines', (
      tester,
    ) async {
      await pumpApp(tester, relay: false);
      container.read(chatControllerProvider.notifier).openPrivateChat('bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voice call'));
      await settle(tester);
      // Without a relay on the server, calls connect directly.
      expect(media.relayOnly, isFalse);
      expect(find.textContaining("relay isn't set up"), findsOneWidget);
      signaling.receive({'type': 'declined'});
      await settle(tester);
      expect(find.text('bob declined the call'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Voice call'));
      await settle(tester);
      signaling.receive({'type': 'timeout'});
      await settle(tester);
      expect(find.text('No answer'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets('blocked camera and microphone: open the right settings', (
      tester,
    ) async {
      blockDevices = true;
      addTearDown(() => blockDevices = false);
      await pumpApp(tester);
      container.read(chatControllerProvider.notifier).openPrivateChat('bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Video call'));
      await settle(tester);
      expect(find.text('The camera or microphone is blocked.'), findsWidgets);
      // On a Mac: one button per settings page, and the note stays up.
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.text('Open Camera settings'));
      await tester.tap(find.text('Open Microphone settings'));
      await tester.pump();
      expect(privacy.opened, [PrivacyPage.camera, PrivacyPage.microphone]);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(container.read(callControllerProvider).phase, CallPhase.idle);
    });

    testWidgets('on phones one button opens the app settings', (tester) async {
      blockDevices = true;
      addTearDown(() => blockDevices = false);
      await pumpApp(tester, separatePages: false);
      container.read(chatControllerProvider.notifier).openPrivateChat('bob');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voice call'));
      await settle(tester);
      expect(find.text('The microphone is blocked.'), findsWidgets);
      expect(find.text('Open Camera settings'), findsNothing);
      await tester.tap(find.text('Open Settings'));
      await tester.pump();
      expect(privacy.opened, isNotEmpty);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('"Hide my IP" can be turned off and is remembered', (
      tester,
    ) async {
      await pumpApp(tester);
      final calls = container.read(callControllerProvider.notifier);
      expect(container.read(callControllerProvider).relayOnly, isTrue);
      await calls.setRelayOnly(enabled: false);
      expect(container.read(callControllerProvider).relayOnly, isFalse);
      expect(
        container.read(keyValueStoreProvider).getString('callsRelayOnly'),
        'false',
      );
    });
  });
}
