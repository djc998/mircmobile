import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/links/open_link.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/links/data/link_media_service.dart';
import 'package:material_ui/material_ui.dart';

class _Transport implements IrcTransport {
  final StreamController<String> incoming =
      StreamController<String>.broadcast();

  @override
  Future<void> connect() async {}

  @override
  Stream<String> get lines => incoming.stream;

  @override
  void writeLine(String line) {}

  @override
  Future<void> close() async {}
}

final Uint8List _png = img.encodePng(img.Image(width: 4, height: 4));

/// Answers image requests: `/a.png` is an image, `/page.png` is a web page,
/// `/big.png` is too big.
MockClient _web(List<Uri> asked) => MockClient((request) async {
  asked.add(request.url);
  return switch (request.url.path) {
    '/a.png' => http.Response.bytes(
      _png,
      200,
      headers: {'content-type': 'image/png'},
    ),
    '/page.png' => http.Response(
      '<html></html>',
      200,
      headers: {'content-type': 'text/html'},
    ),
    '/big.png' => http.Response.bytes(
      Uint8List(LinkMediaService.maxBytes + 1),
      200,
      headers: {'content-type': 'image/png'},
    ),
    _ => http.Response('', 404),
  };
});

void main() {
  group('LinkMediaService', () {
    test('loads an image once, then from memory', () async {
      final asked = <Uri>[];
      final service = LinkMediaService(client: _web(asked));
      final uri = Uri.parse('https://pics.test/a.png');
      expect(await service.fetchImage(uri), _png);
      expect(await service.fetchImage(uri), _png);
      expect(service.cached(uri), _png);
      expect(asked, hasLength(1));
    });

    test('refuses web pages, big files, errors and http', () async {
      final service = LinkMediaService(client: _web([]));
      Future<String> why(String url) => service
          .fetchImage(Uri.parse(url))
          .then((_) => 'loaded', onError: (Object e) => '$e');
      expect(
        await why('https://pics.test/page.png'),
        "That link isn't an image.",
      );
      expect(
        await why('https://pics.test/big.png'),
        'The image is too big to preview.',
      );
      expect(
        await why('https://pics.test/gone.png'),
        "Couldn't load the image (error 404).",
      );
      expect(
        await why('http://pics.test/a.png'),
        'Only secure (https) links are shown.',
      );
    });
  });

  group('in a chat', () {
    late List<Uri> asked;
    late List<Uri> opened;
    late _Transport transport;

    setUp(() {
      asked = [];
      opened = [];
      linkOpener = (uri) async {
        opened.add(uri);
        return true;
      };
    });

    tearDown(() => linkOpener = (_) async => false);

    Future<void> openChat(
      WidgetTester tester, {
      Map<String, String> settings = const {},
    }) async {
      transport = _Transport();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(
              MemoryKeyValueStore(settings),
            ),
            linkMediaServiceProvider.overrideWithValue(
              LinkMediaService(client: _web(asked)),
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
      await tester.ensureVisible(find.text('Libera.Chat'));
      await tester.tap(find.text('Libera.Chat'));
      await tester.pumpAndSettle();
      transport.incoming
        ..add(':s 001 me :Welcome')
        ..add(':bob!b@h PRIVMSG me :look https://pics.test/a.png!');
      await tester.pumpAndSettle();
      ProviderScope.containerOf(tester.element(find.byType(IrcApp)))
          .read(chatControllerProvider.notifier)
          .selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// Lets the (mock) download finish, then draws the result.
    Future<void> settleDownload(WidgetTester tester) async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('an image link waits for a tap: nothing loads until then', (
      tester,
    ) async {
      await openChat(tester);
      expect(find.text('Show image from pics.test'), findsOneWidget);
      expect(asked, isEmpty);

      await tester.tap(find.text('Show image from pics.test'));
      await tester.pump();
      await settleDownload(tester);
      expect(asked, [Uri.parse('https://pics.test/a.png')]);
      expect(find.text('Show image from pics.test'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp('Image from pics.test, linked by bob')),
        findsOneWidget,
      );
    });

    testWidgets('with the setting on, images load by themselves', (
      tester,
    ) async {
      await openChat(
        tester,
        settings: {'appearance': '{"version":2,"autoLinkImages":true}'},
      );
      await settleDownload(tester);
      expect(asked, [Uri.parse('https://pics.test/a.png')]);
      expect(find.text('Show image from pics.test'), findsNothing);
    });

    testWidgets('Open in browser from the preview menu', (tester) async {
      await openChat(tester);
      await tester.tap(find.byTooltip('Link options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open in browser'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://pics.test/a.png')]);
      expect(asked, isEmpty);
    });
  });
}
