import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/presentation/camera_capture.dart';
import 'package:material_ui/material_ui.dart';

class _Transport implements IrcTransport {
  final StreamController<String> incoming = StreamController<String>();

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) {}

  @override
  Future<void> close() async {}
}

final Uint8List _photo = img.encodePng(img.Image(width: 4, height: 4));

/// Connects, opens a private chat with bob, and returns the sources the
/// photo picker was asked for.
Future<List<PhotoSource>> _openPrivateChat(
  WidgetTester tester, {
  bool failCamera = false,
}) async {
  final asked = <PhotoSource>[];
  final transport = _Transport();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pictureServiceProvider.overrideWithValue(
          PictureService(
            host: 'https://pics.test',
            client: MockClient((_) async => http.Response('', 404)),
            prepare: (b) async => b,
          ),
        ),
        photoPickerProvider.overrideWithValue((context, source) async {
          asked.add(source);
          if (failCamera && source == PhotoSource.camera) {
            throw Exception('no camera');
          }
          return _photo;
        }),
        transportFactoryProvider.overrideWithValue(
          (host, port, {required useTls, trustedFingerprints = const {}}) =>
              transport,
        ),
      ],
      child: const IrcApp(),
    ),
  );
  await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
  await tester.ensureVisible(find.text('Libera.Chat'));
  await tester.tap(find.text('Libera.Chat'));
  await tester.pumpAndSettle();
  transport.incoming
    ..add(':s 001 me :Welcome')
    ..add(':bob!b@h PRIVMSG me :hi');
  await tester.pumpAndSettle();
  ProviderScope.containerOf(tester.element(find.byType(IrcApp)))
      .read(chatControllerProvider.notifier)
      .selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
  await tester.pumpAndSettle();
  return asked;
}

void main() {
  testWidgets('+ menu: Take a photo opens the camera, then the send sheet', (
    tester,
  ) async {
    final asked = await _openPrivateChat(tester);
    await tester.tap(find.byTooltip('Add a photo or command'));
    await tester.pumpAndSettle();
    expect(find.text('Send a photo'), findsWidgets);
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();

    expect(asked, [PhotoSource.camera]);
    // The usual send sheet: how long the photo lasts.
    expect(find.text('Send a photo'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('the photo button asks: choose or take a photo', (tester) async {
    final asked = await _openPrivateChat(tester);
    await tester.tap(find.byTooltip('Send a photo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a photo'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    await tester.tap(find.text('Choose a photo'));
    await tester.pumpAndSettle();
    expect(asked, [PhotoSource.library]);
  });

  testWidgets('the Mac also offers the camera', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _openPrivateChat(tester);
      await tester.tap(find.byTooltip('Send a photo'));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('no camera: says so', (tester) async {
    final asked = await _openPrivateChat(tester, failCamera: true);
    await tester.tap(find.byTooltip('Add a photo or command'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    expect(asked, [PhotoSource.camera]);
    expect(find.text("Couldn't open the camera."), findsOneWidget);
  });

  testWidgets('without a camera, the photo button goes straight to files', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    try {
      final asked = await _openPrivateChat(tester);
      await tester.tap(find.byTooltip('Add a photo or command'));
      await tester.pumpAndSettle();
      expect(find.text('Take a photo'), findsNothing);
      Navigator.of(tester.element(find.text('Send a photo').last)).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Send a photo'));
      await tester.pumpAndSettle();
      expect(find.text('Choose a photo'), findsNothing);
      expect(asked, [PhotoSource.library]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('which devices can take photos', () {
    expect(canTakePhotos(TargetPlatform.iOS), isTrue);
    expect(canTakePhotos(TargetPlatform.android), isTrue);
    expect(canTakePhotos(TargetPlatform.macOS), isTrue);
    expect(canTakePhotos(TargetPlatform.windows), isTrue);
    expect(canTakePhotos(TargetPlatform.linux), isTrue);
    expect(canTakePhotos(TargetPlatform.fuchsia), isFalse);
  });
}
