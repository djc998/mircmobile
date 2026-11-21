import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:irc_client/features/pictures/data/picture_crypto.dart';
import 'package:irc_client/features/pictures/data/picture_prep.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';

const _key = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _id = 'abcdefghijklmnopqrstuv';

void main() {
  group('PictureLink', () {
    test('finds a link in a message and keeps its parts', () {
      final link = PictureLink.find(
        '📷 Picture (disappears in 1 day): https://pics.test/p/$_id#k=$_key',
      )!;
      expect(link.page, Uri.parse('https://pics.test/p/$_id'));
      expect(link.key, _key);
      expect(link.viewOnce, isFalse);
      expect(link.id, _id);
      expect(link.raw, Uri.parse('https://pics.test/p/$_id/raw'));
      expect('$link', 'https://pics.test/p/$_id#k=$_key');
    });

    test('view-once links round trip', () {
      const text = 'https://pics.test/p/$_id#k=$_key&o=1';
      final link = PictureLink.find(text)!;
      expect(link.viewOnce, isTrue);
      expect('$link', text);
      expect(
        link.message(PictureExpiry.hour),
        '📷 Picture (view once, disappears in 1 hour): $text',
      );
    });

    test('ignores ordinary links and links without a key', () {
      expect(PictureLink.find('see https://example.com/p/x'), isNull);
      expect(PictureLink.find('https://pics.test/p/$_id'), isNull);
      expect(PictureLink.find('http://pics.test/p/$_id#k=$_key'), isNull);
    });
  });

  group('encryption', () {
    test('seals and opens a picture', () async {
      final plain = Uint8List.fromList(List.generate(5000, (i) => i % 256));
      final (:sealed, :key) = await sealPicture(plain);
      expect(key, hasLength(43));
      expect(sealed.length, plain.length + 12 + 16);
      expect(sealed.sublist(12, 40), isNot(plain.sublist(0, 28)));
      expect(await openPicture(sealed, key), plain);
    });

    test('a wrong key or changed bytes fail', () async {
      final (:sealed, :key) = await sealPicture(Uint8List(100));
      final other = (await sealPicture(Uint8List(1))).key;
      expect(() => openPicture(sealed, other), throwsA(anything));
      sealed[20] ^= 1;
      expect(() => openPicture(sealed, key), throwsA(anything));
    });
  });

  group('preparing a photo', () {
    test('shrinks it, keeps it upright and removes location data', () {
      final photo = img.Image(width: 4000, height: 3000)
        ..exif.imageIfd['Orientation'] =
            6 // Rotated 90° by the camera.
        ..exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(40, 1)
        ..exif.imageIfd['Make'] = 'PhoneCo';
      final prepared = preparePictureSync(img.encodeJpg(photo));
      final out = img.decodeJpg(prepared)!;
      // Rotated to portrait and shrunk to 2048 on the long side.
      expect(out.width, 1536);
      expect(out.height, 2048);
      expect(out.exif.isEmpty, isTrue);
      expect(out.exif.gpsIfd.isEmpty, isTrue);
    });

    test('refuses files that are not pictures', () {
      expect(
        () => preparePictureSync(Uint8List.fromList(utf8.encode('hello'))),
        throwsFormatException,
      );
    });
  });

  group('PictureService', () {
    test('uploads encrypted bytes and downloads them again', () async {
      Uint8List? stored;
      late http.Request upload;
      final client = MockClient((req) async {
        if (req.method == 'POST' && req.url.path == '/upload') {
          upload = req;
          stored = req.bodyBytes;
          return http.Response(
            jsonEncode({'id': _id, 'url': 'https://pics.test/p/$_id'}),
            201,
          );
        }
        if (req.url.path == '/p/$_id/raw') {
          return http.Response.bytes(stored!, 200);
        }
        return http.Response('', 404);
      });
      final picture = Uint8List.fromList([1, 2, 3, 4, 5]);
      final sender = PictureService(
        host: 'https://pics.test',
        client: client,
        prepare: (b) async => b,
      );
      final link = await sender.upload(
        picture,
        expiry: PictureExpiry.halfDay,
        viewOnce: true,
      );
      expect(upload.headers['x-expires-in'], '43200');
      expect(upload.headers['x-view-once'], '1');
      expect(stored, isNot(contains(picture)));
      expect(link.viewOnce, isTrue);
      expect(sender.cached(link), picture);

      // Someone else, without the cache, downloads and decrypts it.
      final receiver = PictureService(host: '', client: client);
      expect(receiver.isConfigured, isFalse);
      expect(await receiver.download(link), picture);
    });

    test('a missing picture reads as expired', () async {
      final service = PictureService(
        host: '',
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      final link = PictureLink.find('https://pics.test/p/$_id#k=$_key')!;
      await expectLater(
        service.download(link),
        throwsA(isA<PictureGoneException>()),
      );
    });

    test('upload errors from the server are shown as is', () async {
      final service = PictureService(
        host: 'https://pics.test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'error': 'Too many uploads. Try again in a minute.'}),
            429,
          ),
        ),
        prepare: (b) async => b,
      );
      await expectLater(
        service.upload(Uint8List(4), expiry: PictureExpiry.day),
        throwsA(
          isA<PictureException>().having(
            (e) => e.message,
            'message',
            contains('Too many uploads'),
          ),
        ),
      );
    });

    test('reports go to the server that holds the picture', () async {
      late http.Request sent;
      final service = PictureService(
        host: '',
        client: MockClient((req) async {
          sent = req;
          return http.Response('{"ok":true}', 201);
        }),
      );
      final link = PictureLink.find('https://pics.test/p/$_id#k=$_key')!;
      await service.report(
        link,
        sender: 'troll',
        network: 'irc.libera.chat',
        reason: 'Spam or scam',
      );
      expect(sent.url, Uri.parse('https://pics.test/report'));
      final body = jsonDecode(sent.body) as Map<String, Object?>;
      expect(body['link'], '$link');
      expect(body['sender'], 'troll');
      expect(body['reason'], 'Spam or scam');
    });
  });
}
