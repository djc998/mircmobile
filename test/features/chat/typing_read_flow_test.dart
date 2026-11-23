import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/ui/composer.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/safety/application/safety_controller.dart';
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

const _caps = 'batch server-time message-tags draft/read-marker';

void main() {
  late _Transport transport;
  late ProviderContainer container;

  Finder field() => find.descendant(
    of: find.byType(Composer),
    matching: find.byType(TextField),
  );

  Future<void> start(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    transport = _Transport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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
    transport.incoming
      ..add(':s CAP * LS :$_caps')
      ..add(':s CAP * ACK :$_caps')
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #chat');
    await tester.pumpAndSettle();
  }

  ChatController controller() =>
      container.read(chatControllerProvider.notifier);
  ChatBuffer buffer(String name) => container
      .read(chatControllerProvider)
      .buffers[ChatState.bufferKey('irc.libera.chat', name)]!;

  testWidgets('who is typing shows above the message box, then goes', (
    tester,
  ) async {
    await start(tester);
    transport.incoming.add('@+typing=active :bob!b@h TAGMSG #chat');
    await tester.pumpAndSettle();
    expect(find.text('bob is typing…'), findsOneWidget);
    transport.incoming.add('@+typing=active :ann!a@h TAGMSG #chat');
    await tester.pumpAndSettle();
    expect(find.text('bob and ann are typing…'), findsOneWidget);

    // A message from bob ends his typing; ann's runs out after 6 seconds.
    transport.incoming.add(':bob!b@h PRIVMSG #chat :done now');
    await tester.pumpAndSettle();
    expect(find.text('ann is typing…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.textContaining('typing'), findsNothing);
  });

  testWidgets('typing is sent at most every 3 seconds, then done', (
    tester,
  ) async {
    await start(tester);
    List<String> typing() =>
        transport.written.where((l) => l.contains('TAGMSG')).toList();
    await tester.enterText(field(), 'h');
    await tester.enterText(field(), 'he');
    await tester.enterText(field(), 'hey');
    expect(typing(), ['@+typing=active TAGMSG #chat']);
    await tester.pump(const Duration(seconds: 4));
    await tester.enterText(field(), 'hey t');
    expect(typing(), hasLength(2));
    await tester.enterText(field(), '');
    expect(typing().last, '@+typing=done TAGMSG #chat');
    // Commands aren't typing.
    await tester.enterText(field(), '/join #x');
    expect(typing(), hasLength(3));

    // Turned off in Settings: nothing is sent.
    container.read(safetyProvider.notifier).setSendTyping(enabled: false);
    await tester.enterText(field(), 'secret');
    expect(typing(), hasLength(3));
  });

  testWidgets('read on another device: unread counts follow', (tester) async {
    await start(tester);
    // Whole milliseconds, as IRC timestamps are.
    final now = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    String at(int minutesAgo) =>
        now.subtract(Duration(minutes: minutesAgo)).toIso8601String();
    // #other gets three messages while #chat is open.
    transport.incoming.add(':me!u@h JOIN #other');
    await tester.pumpAndSettle();
    controller().selectBuffer(ChatState.bufferKey('irc.libera.chat', '#chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add('@time=${at(3)} :bob!b@h PRIVMSG #other :one')
      ..add('@time=${at(2)} :bob!b@h PRIVMSG #other :two me')
      ..add('@time=${at(1)} :bob!b@h PRIVMSG #other :three');
    await tester.pumpAndSettle();
    expect(buffer('#other').unread, 3);
    expect(buffer('#other').mentioned, isTrue);

    // Read up to "two" elsewhere: only "three" is left, and no mention.
    transport.incoming.add(':s MARKREAD #other timestamp=${at(2)}');
    await tester.pumpAndSettle();
    expect(buffer('#other').unread, 1);
    expect(buffer('#other').firstUnread!.text, 'three');
    expect(buffer('#other').mentioned, isFalse);

    // Opening it here tells the server, shortly after.
    controller().selectBuffer(ChatState.bufferKey('irc.libera.chat', '#other'));
    await tester.pump(const Duration(seconds: 1));
    expect(
      transport.written.where((l) => l.startsWith('MARKREAD #other')).single,
      'MARKREAD #other timestamp=${at(1)}',
    );
  });

  test('the typing line words', () {
    expect(TypingLine.text(const []), '');
    expect(
      TypingLine.text(const ['a', 'b', 'c']),
      'Several people are typing…',
    );
  });
}
