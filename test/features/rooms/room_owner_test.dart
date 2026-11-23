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
  testWidgets('a room owner can describe, moderate, limit and manage bans', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeTransport();
    // Flood control (which uses the real clock) spaces out lines after a
    // burst, so let real time pass before checking what was sent.
    Future<void> flush() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1600)),
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    }

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
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #friends')
      ..add(':s 332 me #friends :Old topic')
      ..add(':s 353 me = #friends :@me bob')
      ..add(':s 366 me #friends :End')
      ..add(':s 324 me #friends +nt');
    await flush();

    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Room settings'));
    await flush();
    // Opening the settings asks for the ban list.
    expect(transport.written, contains('MODE #friends +b'));

    // Description: prefilled with the topic, saved as the new topic.
    expect(find.widgetWithText(TextField, 'Old topic'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Old topic'),
      'Friends of the show',
    );
    await tester.tap(find.text('Save description'));
    await flush();
    expect(transport.written.last, 'TOPIC #friends :Friends of the show');

    // Moderated and outside messages.
    await tester.ensureVisible(
      find.widgetWithText(SwitchListTile, 'Moderated'),
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Moderated'));
    await flush();
    expect(transport.written.last, 'MODE #friends +m');
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'No messages from outside'),
    );
    await flush();
    expect(transport.written.last, 'MODE #friends -n');

    // Room size.
    await tester.enterText(find.widgetWithText(TextField, 'Most people'), '25');
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Set').first);
    await tester.tap(find.widgetWithText(FilledButton, 'Set').first);
    await flush();
    expect(transport.written.last, 'MODE #friends +l 25');
    transport.incoming.add(':me!u@h MODE #friends +l 25');
    await flush();
    expect(find.text('At most 25 people can be in the room.'), findsOneWidget);

    // Bans arrive and can be lifted.
    expect(find.text('Loading…'), findsOneWidget);
    transport.incoming
      ..add(':s 367 me #friends troll!*@* me 1700000000')
      ..add(':s 368 me #friends :End of Channel Ban List');
    await flush();
    expect(find.text('troll!*@*'), findsOneWidget);
    await tester.ensureVisible(find.text('Unban'));
    await tester.tap(find.text('Unban'));
    await flush();
    expect(transport.written.last, 'MODE #friends -b troll!*@*');
    transport.incoming.add(':me!u@h MODE #friends -b troll!*@*');
    await flush();
    expect(find.text('Nobody is banned.'), findsOneWidget);

    // Close the sheet; give bob a voice from the people menu.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(IrcApp)),
    );
    final net = container.read(chatControllerProvider).activeNetwork!;
    expect(net.client.channel('#friends')!.topic, 'Old topic');
    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Give voice'));
    await flush();
    expect(transport.written.last, 'MODE #friends +v bob');

    // Once bob is an operator, the menu offers to remove that.
    transport.incoming.add(':me!u@h MODE #friends +o bob');
    await flush();
    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@bob'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove operator of #friends'));
    await flush();
    expect(transport.written.last, 'MODE #friends -o bob');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
