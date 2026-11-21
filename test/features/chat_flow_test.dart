import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
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

void main() {
  testWidgets('pick a network, join a room and chat', (tester) async {
    final transport = FakeTransport();
    String? connectedHost;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportFactoryProvider.overrideWithValue((
            host,
            port, {
            required useTls,
          }) {
            connectedHost = host;
            return transport;
          }),
        ],
        child: const IrcApp(),
      ),
    );

    expect(find.text('Choose a network'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.enterText(
      find.widgetWithText(TextField, 'Rooms to join (optional)'),
      'flutter',
    );
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();

    expect(connectedHost, 'irc.libera.chat');
    expect(transport.written, contains('NICK me'));

    transport.incoming
      ..add(':s CAP * LS :server-time')
      ..add(':s CAP * ACK :server-time')
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #flutter')
      ..add(':s 332 me #flutter :Flutter chat')
      ..add(':s 353 me = #flutter :@alice me')
      ..add(':s 366 me #flutter :End')
      ..add(':alice!a@h PRIVMSG #flutter :hi me!');
    await tester.pumpAndSettle();

    expect(transport.written, contains('JOIN #flutter'));
    expect(find.text('#flutter'), findsOneWidget);
    expect(find.text('Flutter chat'), findsOneWidget);
    expect(find.textContaining('hi me!', findRichText: true), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Message or /command'),
      'hello alice',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'PRIVMSG #flutter :hello alice');
    expect(
      find.textContaining('hello alice', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    expect(find.text('2 people in #flutter'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);

    // Dispose the app so the client's timers are cancelled.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
