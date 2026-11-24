import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/irc/dcc.dart';

void main() {
  group('offers', () {
    test('the classic form: IPv4 as one number', () {
      final o = DccOffer.parse('SEND notes.pdf 3232235777 5000 1234')!;
      expect(o.name, 'notes.pdf');
      expect(o.host.address, '192.168.1.1');
      expect((o.port, o.size, o.passive), (5000, 1234, false));
    });

    test('quoted names, IPv6, passive offers', () {
      final q = DccOffer.parse('SEND "my file.txt" 2130706433 6000 10')!;
      expect(q.name, 'my file.txt');
      expect(q.host.address, '127.0.0.1');
      final v6 = DccOffer.parse('SEND a.zip 2001:db8::1 7000 99')!;
      expect(v6.host.type, InternetAddressType.IPv6);
      final p = DccOffer.parse('SEND a.zip 3232235777 0 99 42')!;
      expect((p.passive, p.token), (true, '42'));
    });

    test('not usable', () {
      for (final bad in [
        'CHAT chat 3232235777 5000',
        'SEND a.zip nonsense 5000 1',
        'SEND a.zip 3232235777 70000 1',
        'SEND a.zip 3232235777 0 1',
        'SEND a.zip',
      ]) {
        expect(DccOffer.parse(bad), isNull, reason: bad);
      }
    });

    test('offers are written the way they are read', () {
      final args = dccSendArgs(
        'my "file".txt',
        InternetAddress('192.168.1.20'),
        5001,
        77,
      );
      expect(args, "SEND \"my 'file'.txt\" 3232235796 5001 77");
      final back = DccOffer.parse(args)!;
      expect(back.name, "my 'file'.txt");
      expect(back.host.address, '192.168.1.20');
      expect(
        dccSendArgs('a', InternetAddress('10.0.0.2'), 0, 5, token: '9'),
        endsWith(' 0 5 9'),
      );
    });
  });

  group('transfers over real sockets', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dcc_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    Uint8List data(int n) =>
        Uint8List.fromList(List.generate(n, (_) => Random().nextInt(256)));

    test('send, connect, receive with acknowledgements', () async {
      final bytes = data(1024 * 1024 + 123);
      final source = File('${dir.path}/out.bin')..writeAsBytesSync(bytes);
      final listener = await DccListener.open();
      final offer = DccOffer.parse(
        dccSendArgs('out.bin', listener.address, listener.port, bytes.length),
      )!;
      final into = File('${dir.path}/in.bin');
      var progress = 0;
      await Future.wait([
        sendDcc(listener, source),
        receiveDcc(offer, into, onProgress: (n) => progress = n),
      ]);
      expect(into.readAsBytesSync(), bytes);
      expect(progress, bytes.length);
    });

    test('passive: the receiver listens and replies with a token', () async {
      final bytes = data(50000);
      final source = File('${dir.path}/p.bin')..writeAsBytesSync(bytes);
      final offer = DccOffer.parse(
        'SEND p.bin 3232235777 0 ${bytes.length} 77',
      )!;
      final into = File('${dir.path}/p-in.bin');
      String? reply;
      final receiving = receivePassiveDcc(
        offer,
        into,
        reply: (args) => reply = args,
      );
      // The sender gets the reply and connects to it.
      while (reply == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final where = DccOffer.parse(reply!)!;
      expect(where.token, '77');
      final socket = await Socket.connect(where.host, where.port);
      socket.add(source.readAsBytesSync());
      await socket.flush();
      await receiving;
      socket.destroy();
      expect(into.readAsBytesSync(), bytes);
    });

    test('a sender that stops early is an error', () async {
      final listener = await DccListener.open();
      final offer = DccOffer.parse(
        dccSendArgs('x', listener.address, listener.port, 1000),
      )!;
      final into = File('${dir.path}/short.bin');
      final serving = listener.accept().then((s) async {
        s.add(Uint8List(10));
        await s.flush();
        await s.close();
      });
      await expectLater(
        receiveDcc(offer, into),
        throwsA(
          isA<DccException>().having(
            (e) => e.message,
            'message',
            contains('stopped before the end'),
          ),
        ),
      );
      await serving;
    });

    test('nobody listening: a clear message', () async {
      final offer = DccOffer.parse('SEND x 2130706433 1 10')!;
      await expectLater(
        receiveDcc(
          offer,
          File('${dir.path}/none.bin'),
          connectTimeout: const Duration(seconds: 2),
        ),
        throwsA(isA<DccException>()),
      );
    });
  });
}
