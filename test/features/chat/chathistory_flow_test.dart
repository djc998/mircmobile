import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
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

Finder _chatText(String text) => find.descendant(
  of: find.byType(ChatScreen),
  matching: find.textContaining(text, findRichText: true),
);

const _caps = 'batch server-time message-tags echo-message draft/chathistory';

void main() {
  late _Transport transport;
  late ProviderContainer container;
  List<String> history() =>
      transport.written.where((l) => l.startsWith('CHATHISTORY')).toList();

  Future<void> start(WidgetTester tester, {MemoryKeyValueStore? store}) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    transport = _Transport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(
            store ?? MemoryKeyValueStore(),
          ),
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
      ..add(':s 001 me :Welcome');
    await tester.pumpAndSettle();
  }

  ChatBuffer buffer(String name) => container
      .read(chatControllerProvider)
      .buffers[ChatState.bufferKey('irc.libera.chat', name)]!;

  testWidgets('joining a room brings back what it said, without repeats', (
    tester,
  ) async {
    await start(tester);
    // Logging in asks which private chats had messages lately.
    expect(history().single, startsWith('CHATHISTORY TARGETS timestamp='));

    transport.incoming.add(':me!u@h JOIN #chat');
    await tester.pumpAndSettle();
    expect(history().last, 'CHATHISTORY LATEST #chat * 50');

    final now = DateTime.now().toUtc();
    String at(int minutesAgo) =>
        now.subtract(Duration(minutes: minutesAgo)).toIso8601String();
    transport.incoming
      ..add(':s BATCH +b1 chathistory #chat')
      ..add('@batch=b1;time=${at(30)};msgid=m1 :bob!b@h PRIVMSG #chat :first')
      ..add('@batch=b1;time=${at(20)};msgid=m2 :ann!a@h PRIVMSG #chat :second')
      // The same message twice (a bouncer replaying) is shown once.
      ..add('@batch=b1;time=${at(20)};msgid=m2 :ann!a@h PRIVMSG #chat :second')
      ..add(':s BATCH -b1');
    await tester.pumpAndSettle();
    final texts = [for (final l in buffer('#chat').lines) l.text];
    expect(texts.where((t) => t == 'second'), hasLength(1));
    // In time order, before "You joined".
    expect(texts.indexOf('first'), lessThan(texts.indexOf('second')));
    expect(
      texts.indexOf('second'),
      lessThan(texts.indexOf('You joined #chat')),
    );
    expect(_chatText('first'), findsOneWidget);
    expect(buffer('#chat').historyWant, isNull);
  });

  testWidgets('missed private chats open with their messages', (tester) async {
    await start(tester);
    final now = DateTime.now().toUtc();
    final then = now.subtract(const Duration(minutes: 5)).toIso8601String();
    transport.incoming
      ..add(':me!u@h JOIN #chat')
      ..add(':s BATCH +t1 draft/chathistory-targets')
      ..add('@batch=t1 :s CHATHISTORY TARGETS bob timestamp=$then')
      ..add('@batch=t1 :s CHATHISTORY TARGETS #chat timestamp=$then')
      ..add(':s BATCH -t1');
    await tester.pumpAndSettle();
    expect(history(), contains('CHATHISTORY LATEST bob * 50'));
    transport.incoming
      ..add(':s BATCH +b2 chathistory bob')
      ..add('@batch=b2;time=$then;msgid=p1 :bob!b@h PRIVMSG me :you there?')
      ..add(':s BATCH -b2');
    await tester.pumpAndSettle();
    final bob = buffer('bob');
    expect(bob.lines.single.text, 'you there?');
    // Missed while away: unread.
    expect(bob.unread, 1);
  });

  testWidgets('older messages load from the top until there are none', (
    tester,
  ) async {
    await start(tester);
    transport.incoming
      ..add(':me!u@h JOIN #chat')
      ..add('@msgid=x :bob!b@h PRIVMSG #chat :hello');
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s BATCH +b0 chathistory #chat')
      ..add(':s BATCH -b0');
    await tester.pumpAndSettle();

    expect(find.text('Load earlier messages'), findsOneWidget);
    await tester.tap(find.text('Load earlier messages'));
    await tester.pump();
    expect(history().last, startsWith('CHATHISTORY BEFORE #chat timestamp='));
    expect(history().last, endsWith(' 50'));
    expect(find.bySemanticsLabel('Loading earlier messages'), findsOneWidget);

    final old = DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 2))
        .toIso8601String();
    transport.incoming
      ..add(':s BATCH +b3 chathistory #chat')
      ..add('@batch=b3;time=$old;msgid=o1 :ann!a@h PRIVMSG #chat :long ago')
      ..add(':s BATCH -b3');
    await tester.pumpAndSettle();
    expect(buffer('#chat').lines.first.text, 'long ago');
    // Older messages aren't new: no unread count.
    expect(buffer('#chat').unread, 0);

    // Nothing older: the button goes away.
    await tester.tap(find.text('Load earlier messages'));
    await tester.pump();
    transport.incoming
      ..add(':s BATCH +b4 chathistory #chat')
      ..add(':s BATCH -b4');
    await tester.pumpAndSettle();
    expect(buffer('#chat').historyExhausted, isTrue);
    expect(find.text('Load earlier messages'), findsNothing);
  });

  testWidgets('servers without history: no requests, no button', (
    tester,
  ) async {
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
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.ensureVisible(find.text('Libera.Chat'));
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s CAP * LS :batch server-time')
      ..add(':s CAP * ACK :batch server-time')
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #chat')
      ..add(':bob!b@h PRIVMSG #chat :hi');
    await tester.pumpAndSettle();
    expect(history(), isEmpty);
    expect(find.text('Load earlier messages'), findsNothing);
  });
}
