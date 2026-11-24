import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/dcc.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
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

void main() {
  late _Transport transport;
  late ProviderContainer container;
  final saved = <String, Uint8List>{};
  final bytes = Uint8List.fromList(List.generate(70000, (i) => i % 251));

  Future<void> start(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    saved.clear();
    transport = _Transport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          filePickerProvider.overrideWithValue(
            () async => (name: 'photo album.zip', bytes: bytes),
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
    container = ProviderScope.containerOf(tester.element(find.byType(IrcApp)));
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.ensureVisible(find.text('Libera.Chat'));
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming.add(':s 001 me :Welcome');
    await tester.pumpAndSettle();
  }

  /// Lets real socket and file work run until [done] or a few seconds.
  Future<void> settleReal(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 50 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      // Timers started by the app run on the test's clock.
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('accept a direct file, then save it', (tester) async {
    await start(tester);
    // bob offers a file from a socket on this machine.
    final dir = Directory.systemTemp.createTempSync('dcc_flow');
    addTearDown(() => dir.deleteSync(recursive: true));
    final source = File('${dir.path}/album.zip')..writeAsBytesSync(bytes);
    final listener = (await tester.runAsync(DccListener.open))!;
    late Future<void> sending;
    await tester.runAsync(() async {
      sending = sendDcc(listener, source);
    });
    final args = dccSendArgs(
      'album.zip',
      listener.address,
      listener.port,
      bytes.length,
    );
    transport.incoming.add(':bob!b@h PRIVMSG me :\x01DCC $args\x01');
    await tester.pumpAndSettle();
    container
        .read(chatControllerProvider.notifier)
        .selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
    await tester.pumpAndSettle();

    expect(find.textContaining('album.zip · 68 KB'), findsOneWidget);
    expect(find.textContaining('will see your IP address'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Accept album.zip'));
    await settleReal(tester, () => find.text('Received').evaluate().isNotEmpty);
    await tester.runAsync(() => sending);
    expect(find.text('Received'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Save album.zip'));
    await settleReal(tester, () => saved.isNotEmpty);
    expect(saved['album.zip'], bytes);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('decline, and offers from ignored people are dropped', (
    tester,
  ) async {
    await start(tester);
    final controller = container.read(chatControllerProvider.notifier)
      ..blockUser('troll');
    transport.incoming
      ..add(':troll!t@h PRIVMSG me :\x01DCC SEND x.exe 2130706433 9 5\x01')
      ..add(':bob!b@h PRIVMSG me :\x01DCC SEND a.txt 2130706433 9 5\x01');
    await tester.pumpAndSettle();
    final state = container.read(chatControllerProvider);
    expect(
      state.buffers.containsKey(
        ChatState.bufferKey('irc.libera.chat', 'troll'),
      ),
      isFalse,
    );
    controller.selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Decline a.txt'));
    await tester.pumpAndSettle();
    expect(find.text('Declined'), findsOneWidget);
    // No reply goes out on decline (DCC has no standard "no").
    expect(transport.written.where((l) => l.contains('DCC')), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('send directly: offer goes out, they connect, it is sent', (
    tester,
  ) async {
    await start(tester);
    transport.incoming.add(':bob!b@h PRIVMSG me :hi');
    await tester.pumpAndSettle();
    container
        .read(chatControllerProvider.notifier)
        .selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add a photo or command'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send a file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Directly (DCC)'));
    await tester.pumpAndSettle();
    // No expiry for direct sends.
    expect(find.text('1 hour'), findsNothing);
    await tester.tap(find.text('Send file'));
    await settleReal(
      tester,
      () => transport.written.any((l) => l.contains('DCC SEND')),
    );
    final offerLine = transport.written.singleWhere(
      (l) => l.contains('DCC SEND'),
    );
    expect(
      offerLine,
      startsWith('PRIVMSG bob :\x01DCC SEND "photo album.zip" '),
    );
    expect(find.textContaining('Waiting for bob to accept'), findsOneWidget);

    // bob's client connects and reads the file.
    final offer = DccOffer.parse(
      offerLine.substring(offerLine.indexOf('DCC ') + 4).replaceAll('\x01', ''),
    )!;
    final dir = Directory.systemTemp.createTempSync('dcc_send');
    addTearDown(() => dir.deleteSync(recursive: true));
    final into = File('${dir.path}/got.zip');
    late Future<void> receiving;
    await tester.runAsync(() async {
      receiving = receiveDcc(offer, into);
    });
    await settleReal(tester, () => find.text('Sent').evaluate().isNotEmpty);
    await tester.runAsync(() => receiving);
    expect(into.readAsBytesSync(), bytes);
    expect(find.text('Sent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
