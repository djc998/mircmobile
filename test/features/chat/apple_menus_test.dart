import 'dart:async';

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoActionSheet;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:material_ui/material_ui.dart';

class _Transport implements IrcTransport {
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

Finder _chatText(String text) => find.descendant(
  of: find.byType(ChatScreen),
  matching: find.textContaining(text, findRichText: true),
);

Future<void> _inRoom(WidgetTester tester, Size size) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transport = _Transport();
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
    ..add(':s 001 me :Welcome')
    ..add(':me!u@h JOIN #chat')
    ..add(':s 353 me = #chat :me bob')
    ..add(':s 366 me #chat :End')
    ..add(':bob!b@h PRIVMSG #chat :hello from bob');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Mac: right-click a message for Reply, Copy and Report', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _inRoom(tester, const Size(1200, 800));
      await tester.tap(_chatText('hello from bob'), buttons: kSecondaryButton);
      await tester.pumpAndSettle();
      // The text's own Mac menu, with the message's actions added.
      expect(find.text('Reply to bob'), findsOneWidget);
      expect(find.text('Report message'), findsOneWidget);
      await tester.tap(find.text('Reply to bob'));
      await tester.pumpAndSettle();
      expect(find.text('Report message'), findsNothing);
      expect(find.textContaining('Replying to bob'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('iPhone: long-press a message for an action sheet', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _inRoom(tester, const Size(390, 844));
      await tester.longPress(_chatText('hello from bob'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('Copy message'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
