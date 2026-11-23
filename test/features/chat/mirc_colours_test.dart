import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/application/conversations.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

class FakeTransport implements IrcTransport {
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

Future<(FakeTransport, ProviderContainer)> start(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transport = FakeTransport();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(MemoryKeyValueStore()),
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
    ..add(':me!u@h JOIN #chat')
    ..add(':me!u@h JOIN #other')
    ..add(':s 332 me #chat :\x0304Red\x03 topic')
    ..add(':s 353 me = #chat :me alice')
    ..add(':s 366 me #chat :End');
  await tester.pumpAndSettle();
  return (
    transport,
    ProviderScope.containerOf(tester.element(find.byType(IrcApp))),
  );
}

/// The styled span holding [text], if any.
TextSpan? spanWith(WidgetTester tester, String text) {
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    TextSpan? found;
    rich.text.visitChildren((s) {
      if (s is TextSpan && s.text == text) {
        found = s;
        return false;
      }
      return true;
    });
    if (found != null) return found;
  }
  return null;
}

void main() {
  testWidgets('colours and styles are drawn; previews stay plain', (
    tester,
  ) async {
    final (transport, container) = await start(tester);
    container
        .read(chatControllerProvider.notifier)
        .selectBuffer(ChatState.bufferKey('irc.libera.chat', '#chat'));
    transport.incoming.add(
      ':alice!a@h PRIVMSG #chat :\x02bold\x02 and \x0304,01red on black\x03',
    );
    await tester.pumpAndSettle();

    expect(spanWith(tester, 'bold')!.style!.fontWeight, FontWeight.w700);
    final red = spanWith(tester, 'red on black')!;
    expect(red.style!.backgroundColor, const Color(0xFF000000));
    // No control characters reach the screen.
    expect(find.textContaining('\x02', findRichText: true), findsNothing);
    expect(find.textContaining('\x03', findRichText: true), findsNothing);

    // The stored line keeps the codes; previews and search use plain text.
    final line = container
        .read(chatControllerProvider)
        .buffers[ChatState.bufferKey('irc.libera.chat', '#chat')]!
        .lines
        .last;
    expect(line.text, contains('\x02'));
    final chat = activeConversations(container.read(chatControllerProvider))
        .firstWhere((c) => c.name == '#chat');
    expect(chat.preview, 'alice: bold and red on black');

    // Turned off in Appearance: plain text.
    container.read(appearanceProvider.notifier).setIrcColours(show: false);
    await tester.pumpAndSettle();
    expect(spanWith(tester, 'bold'), isNull);
    expect(
      find.textContaining('bold and red on black', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a mention inside formatting still counts', (tester) async {
    final (transport, container) = await start(tester);
    // #other is open, so #chat counts unread.
    transport.incoming.add(':alice!a@h PRIVMSG #chat :\x02me\x02: look');
    await tester.pumpAndSettle();
    expect(
      container
          .read(chatControllerProvider)
          .buffers[ChatState.bufferKey('irc.libera.chat', '#chat')]!
          .mentioned,
      isTrue,
    );
  });

  testWidgets('Room info draws the topic with its colours', (tester) async {
    final (_, container) = await start(tester);
    container
        .read(chatControllerProvider.notifier)
        .selectBuffer(ChatState.bufferKey('irc.libera.chat', '#chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    final red = spanWith(tester, 'Red')!;
    expect(red.style!.color, isNotNull);
    // Shown text has no codes (the description field keeps them for
    // editing).
    expect(
      find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('\x03'),
      ),
      findsNothing,
    );
  });
}
