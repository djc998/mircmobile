import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/file_link.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:irc_client/features/pictures/presentation/file_widgets.dart';
import 'package:material_ui/material_ui.dart';

class _Transport implements IrcTransport {
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

/// A stand-in for the file server: keeps uploads and serves them back.
MockClient _server(Map<String, Uint8List> store, List<http.Request> seen) =>
    MockClient((req) async {
      seen.add(req);
      if (req.url.path == '/upload') {
        final id = 'A' * 21 + '${store.length}';
        store[id] = req.bodyBytes;
        return http.Response(
          jsonEncode({'id': id, 'url': 'https://pics.test/f/$id'}),
          201,
        );
      }
      final m = RegExp(r'^/f/([^/]+)/raw$').firstMatch(req.url.path);
      final bytes = m == null ? null : store[m[1]];
      return bytes == null
          ? http.Response('{"error":"gone"}', 404)
          : http.Response.bytes(bytes, 200);
    });

const _key = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';

void main() {
  group('file links', () {
    test('round trip, with the name and size after #', () {
      final link = FileLink(
        page: Uri.parse('https://pics.test/f/${'B' * 22}'),
        key: _key,
        name: 'notes & plans.pdf',
        size: 1258291,
      );
      final text = link.message('dennis');
      expect(
        text,
        startsWith('📎 File from dennis: notes & plans.pdf (1.2 MB) https://'),
      );
      expect(text, contains('#k=$_key&n=notes%20%26%20plans.pdf&s=1258291'));
      expect(FileLink.find(text), link);
      expect(link.raw.path, '/f/${'B' * 22}/raw');
    });

    test('not a file link', () {
      expect(FileLink.find('https://pics.test/p/${'B' * 22}#k=$_key'), isNull);
      expect(
        FileLink.find('https://pics.test/f/${'B' * 22}#k=$_key&n=%E0&s=1'),
        isNull,
      );
    });

    test('names are made safe', () {
      expect(safeFileName('../../etc/passwd'), 'passwd');
      expect(safeFileName(r'C:\Users\me\a:b?.txt'), 'a_b_.txt');
      expect(safeFileName('.hidden'), 'hidden');
      expect(safeFileName(''), 'file');
      final long = safeFileName('${'x' * 200}.tar.gz');
      expect(long.length, 120);
      expect(long, endsWith('.gz'));
    });

    test('sizes for people', () {
      expect(formatFileSize(820), '820 bytes');
      expect(formatFileSize(14 * 1024), '14 KB');
      expect(formatFileSize(1258291), '1.2 MB');
      expect(formatFileSize(24 * 1024 * 1024), '24 MB');
    });
  });

  test('uploads encrypted with X-Kind: file, downloads and decrypts', () async {
    final store = <String, Uint8List>{};
    final seen = <http.Request>[];
    final service = PictureService(
      host: 'https://pics.test',
      client: _server(store, seen),
    );
    final bytes = Uint8List.fromList(utf8.encode('hello, file'));
    final link = await service.uploadFile(
      bytes,
      name: 'hello.txt',
      expiry: PictureExpiry.hour,
    );
    expect(seen.single.headers['x-kind'], 'file');
    expect(seen.single.headers['x-expires-in'], '3600');
    // The server only ever sees scrambled bytes.
    expect(
      utf8.decode(store.values.single, allowMalformed: true),
      isNot(contains('hello')),
    );
    expect(link.name, 'hello.txt');
    expect(link.size, bytes.length);
    expect(await service.downloadFile(link), bytes);

    await expectLater(
      service.uploadFile(
        Uint8List(maxFileBytes + 1),
        name: 'big.bin',
        expiry: PictureExpiry.hour,
      ),
      throwsA(
        isA<PictureException>().having(
          (e) => e.message,
          'message',
          contains('25 MB'),
        ),
      ),
    );
  });

  testWidgets('send a file from the + menu, and save one you got', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = <String, Uint8List>{};
    final saved = <String, Uint8List>{};
    final transport = _Transport();
    final service = PictureService(
      host: 'https://pics.test',
      client: _server(store, []),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pictureServiceProvider.overrideWithValue(service),
          filePickerProvider.overrideWithValue(
            () async =>
                (name: 'report.pdf', bytes: Uint8List.fromList([1, 2, 3])),
          ),
          fileSaverProvider.overrideWithValue((context, name, file) async {
            saved[name] = file.readAsBytesSync();
            return name;
          }),
          transportFactoryProvider.overrideWithValue(
            (host, port, {required useTls, trustedFingerprints = const {}}) =>
                transport,
          ),
        ],
        child: const IrcApp(),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IrcApp)),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.ensureVisible(find.text('Libera.Chat'));
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s 001 me :Welcome')
      ..add(':bob!b@h PRIVMSG me :hi');
    await tester.pumpAndSettle();
    container
        .read(chatControllerProvider.notifier)
        .selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add a photo or command'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send a file'));
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('3 bytes'), findsOneWidget);
    await tester.tap(find.text('Send file'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    final sent = transport.written.last;
    expect(
      sent,
      startsWith('PRIVMSG bob :📎 File from me: report.pdf (3 bytes)'),
    );

    // bob sends one back: a card with Save.
    final link = FileLink.find(sent)!;
    final theirs = FileLink(
      page: link.page,
      key: link.key,
      name: 'reply.pdf',
      size: 3,
    );
    transport.incoming.add(':bob!b@h PRIVMSG me :${theirs.message('bob')}');
    await tester.pumpAndSettle();
    expect(find.text('3 bytes · from bob'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Save reply.pdf'));
    // Download, decrypt and write a temporary file: real I/O.
    for (var i = 0; i < 10 && saved.isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(saved['reply.pdf'], [1, 2, 3]);
    expect(find.text('Saved reply.pdf.'), findsOneWidget);

    // Rooms don't offer files, like photos.
    await tester.pumpWidget(const SizedBox());
  });
}
