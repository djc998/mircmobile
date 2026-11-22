import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/core/ui/composer.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/chat/data/chat_history_store.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/pictures/data/picture_crypto.dart';
import 'package:irc_client/features/pictures/data/picture_service.dart';
import 'package:irc_client/features/pictures/domain/picture_link.dart';
import 'package:irc_client/features/pictures/presentation/picture_widgets.dart';
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

/// The message field (other screens can have a search field too).
final Finder composerField = find.descendant(
  of: find.byType(Composer),
  matching: find.byType(TextField),
);

/// Text in the open chat (rows in the lists show previews of it too).
Finder chatText(String text) => find.descendant(
  of: find.byType(ChatScreen),
  matching: find.textContaining(text, findRichText: true),
);

/// Picks a place on the rail (small tablets) or tab bar (phones).
Future<void> showTab(WidgetTester tester, String label) async {
  final rail = find.descendant(
    of: find.byType(NavigationRail),
    matching: find.text(label),
  );
  await tester.tap(
    rail.evaluate().isNotEmpty
        ? rail
        : find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
  );
  await tester.pumpAndSettle();
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
            trustedFingerprints = const {},
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
    expect(find.widgetWithText(AppBar, '#flutter'), findsOneWidget);
    // The header counts people; the topic is in Chat info.
    expect(find.textContaining('2 people · '), findsOneWidget);
    expect(chatText('hi me!'), findsOneWidget);

    await tester.enterText(composerField, 'hello alice');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'PRIVMSG #flutter :hello alice');
    expect(chatText('hello alice'), findsOneWidget);

    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    expect(find.text('2 people in #flutter'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);

    // Dispose the app so the client's timers are cancelled.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('browse rooms, search and join with one tap', (tester) async {
    final transport = FakeTransport();
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
    await tester.tap(find.text('OFTC'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s CAP * LS :server-time')
      ..add(':s CAP * ACK :server-time')
      ..add(':s 001 me :Welcome')
      ..add(':s 005 me NETWORK=OFTC ELIST=U :are supported');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Browse rooms'));
    // The progress bar animates forever, so pump a fixed time, not settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Rooms on OFTC'), findsOneWidget);
    expect(transport.written.last, 'LIST');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    transport.incoming
      ..add(':s 321 me Channel :Users Name')
      ..add(':s 322 me #debian 1200 :[+nt] Debian help')
      ..add(':s 322 me #tor 800 :Tor project')
      ..add(':s 322 me #quiet 3 :Shh')
      ..add(':s 323 me :End of /LIST');
    await tester.pumpAndSettle();

    expect(find.text('3 of 3 rooms'), findsOneWidget);
    expect(find.text('#debian'), findsOneWidget);
    expect(find.text('Debian help'), findsOneWidget);
    expect(find.text('1.2k'), findsOneWidget);

    await tester.tap(find.text('10+ people'));
    await tester.pumpAndSettle();
    expect(find.text('#quiet'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search rooms and topics'),
      'tor',
    );
    await tester.pumpAndSettle();
    expect(find.text('#debian'), findsNothing);
    expect(find.text('1 of 3 rooms'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'JOIN #tor');
    expect(find.text('Rooms on OFTC'), findsNothing);

    transport.incoming.add(':me!u@h JOIN #tor');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '#tor'), findsOneWidget);

    // Opening the browser again reuses the cached list.
    final sent = transport.written.length;
    await tester.tap(find.byTooltip('Browse rooms'));
    await tester.pumpAndSettle();
    expect(transport.written.length, sent);
    expect(find.text('3 of 3 rooms'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('favorites and recents are remembered for the next launch', (
    tester,
  ) async {
    // A tall phone screen so the whole start form fits.
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    final secrets = MemorySecretStore();
    var transport = FakeTransport();

    Future<void> launch() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(store),
            secretStoreProvider.overrideWithValue(secrets),
            transportFactoryProvider.overrideWithValue(
              (host, port, {required useTls, trustedFingerprints = const {}}) =>
                  transport,
            ),
          ],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    // First launch: log in with an account and join two rooms.
    await launch();
    expect(find.textContaining('Continue on'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.tap(find.text('Log in with a registered account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Account name'),
      'meacct',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Password'), 'pw1');
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #first')
      ..add(':me!u@h JOIN #second');
    await tester.pumpAndSettle();

    // Star #second (the open room) from Chat info.
    expect(find.widgetWithText(AppBar, '#second'), findsOneWidget);
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.text('Remove from favorites'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Password went to the secret store, not plain settings.
    expect(secrets.values.values, contains('pw1'));
    expect(store.values.values.join(), isNot(contains('pw1')));

    // Second launch: settings are prefilled and Continue rejoins favorites.
    transport = FakeTransport();
    await launch();
    expect(find.text('Continue on Libera.Chat'), findsOneWidget);
    expect(find.textContaining('rejoins #second'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'me'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'meacct'), findsOneWidget);

    await tester.tap(find.text('Continue on Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s CAP * LS :sasl')
      ..add(':s CAP * ACK :sasl')
      ..add('AUTHENTICATE +')
      ..add(':s 903 me :SASL authentication successful')
      ..add(':s 001 me :Welcome');
    await tester.pumpAndSettle();
    // Favorites first, then the other rooms that were open last time.
    expect(transport.written, contains('JOIN #second,#first'));
    expect(
      transport.written.where((l) => l.startsWith('AUTHENTICATE ')).length,
      2,
    );

    // The room browser shows recent rooms as quick-join chips.
    await tester.tap(find.byTooltip('Browse rooms'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Recent:'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '#first'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, '#first'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(transport.written.last, 'JOIN #first');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('untrusted certificate: trust once, then connect', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    final calls = <({bool tls, int port, Set<String> trusted})>[];
    final good = FakeTransport();
    final cert = CertificateInfo(
      subject: 'CN=irc.choopa.net',
      issuer: 'CN=irc.choopa.net',
      validUntil: DateTime(2100),
      sha256: 'AB:CD:EF',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          transportFactoryProvider.overrideWithValue((
            host,
            port, {
            required useTls,
            trustedFingerprints = const {},
          }) {
            calls.add((tls: useTls, port: port, trusted: trustedFingerprints));
            if (!trustedFingerprints.contains('AB:CD:EF')) {
              return _FailingTransport(
                UntrustedCertificateException(host, cert),
              );
            }
            return good;
          }),
        ],
        child: const IrcApp(),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.tap(find.text('EFnet'));
    await tester.pumpAndSettle();

    expect(find.textContaining('self-signed'), findsWidgets);
    expect(find.textContaining('AB:CD:EF'), findsOneWidget);
    await tester.tap(find.text('Trust and connect'));
    // Closing the old connection completes outside the fake clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    good.incoming.add(':s 001 me :Welcome');
    await tester.pumpAndSettle();

    expect(calls.length, 2);
    expect(calls.last.trusted, contains('AB:CD:EF'));
    expect(find.text('Trust and connect'), findsNothing);
    expect(store.values['trustedCertificates'], contains('AB:CD:EF'));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('secure connection fails: offer unencrypted fallback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final calls = <({bool tls, int port})>[];
    final plain = FakeTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transportFactoryProvider.overrideWithValue((
            host,
            port, {
            required useTls,
            trustedFingerprints = const {},
          }) {
            calls.add((tls: useTls, port: port));
            return useTls
                ? _FailingTransport(const SocketException('timed out'))
                : plain;
          }),
        ],
        child: const IrcApp(),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.tap(find.text('OFTC'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Connect without encryption'), findsOneWidget);
    await tester.tap(find.text('Connect without encryption'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
    expect(calls.last, (tls: false, port: 6667));
    expect(plain.written, contains('NICK me'));
    expect(find.textContaining('NOT encrypted'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 10));
  });
  testWidgets('start a private message from the people list or button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeTransport();
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
      ..add(':me!u@h JOIN #chat')
      ..add(':s 353 me = #chat :@alice me')
      ..add(':s 366 me #chat :End');
    await tester.pumpAndSettle();

    // People list -> alice -> Send private message.
    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('@alice'));
    await tester.pumpAndSettle();
    expect(find.text('Send private message'), findsOneWidget);
    await tester.tap(find.text('Send private message'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'alice'), findsOneWidget);

    await tester.enterText(composerField, 'hi alice');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'PRIVMSG alice :hi alice');

    // The New private message button opens a chat by nickname.
    await tester.tap(find.byTooltip('New private message'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nickname').last,
      'bob',
    );
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'bob'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('whois replies appear in the open conversation', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeTransport();
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
      ..add(':me!u@h JOIN #chat')
      ..add(':s 353 me = #chat :alice me')
      ..add(':s 366 me #chat :End');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Who is this? (whois)'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'WHOIS alice');

    transport.incoming
      ..add(':s 311 me alice ~a host.example * :Alice Example')
      ..add(':s 318 me alice :End of /WHOIS list.')
      ..add(':s 372 me :- MOTD line');
    await tester.pumpAndSettle();
    expect(chatText('alice ~a host.example * Alice Example'), findsOneWidget);
    // Unrelated server lines still go to the server tab.
    expect(chatText('MOTD line'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('stay on several networks; rooms and favorites span them all', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transports = <String, FakeTransport>{};
    final store = MemoryKeyValueStore(
      // #fav is a favorite on OFTC from an earlier launch.
      {'roomPrefs': '{"favorites":{"irc.oftc.net":["#fav"]},"recents":{}}'},
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          transportFactoryProvider.overrideWithValue(
            (host, port, {required useTls, trustedFingerprints = const {}}) =>
                transports[host] = FakeTransport(),
          ),
        ],
        child: const IrcApp(),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.tap(
      find.widgetWithText(SwitchListTile, 'Rejoin my favorite rooms'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transports['irc.libera.chat']!.incoming
      ..add(':s 001 me :Welcome')
      ..add(':s 005 me NETWORK=Libera.Chat :are supported')
      ..add(':me!u@h JOIN #lib')
      ..add(':bob!b@h PRIVMSG #lib :hello from libera');
    await tester.pumpAndSettle();

    // Add a second network from You; the first stays connected.
    await showTab(tester, 'You');
    await tester.tap(find.text('Add a network'));
    await tester.pumpAndSettle();
    expect(find.text('Add a network'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Connected'), findsOneWidget);
    await tester.tap(find.text('OFTC'));
    await tester.pumpAndSettle();
    final oftc = transports['irc.oftc.net']!;
    oftc.incoming
      ..add(':s 001 me :Welcome')
      ..add(':s 005 me NETWORK=OFTC :are supported');
    await tester.pumpAndSettle();
    expect(
      transports['irc.libera.chat']!.written,
      isNot(contains(startsWith('QUIT'))),
    );

    // Rooms lists both networks' chats and OFTC's favorite.
    await showTab(tester, 'Rooms');
    expect(find.text('#lib'), findsOneWidget);
    expect(find.text('Libera'), findsWidgets); // network chips
    expect(find.text('#fav'), findsOneWidget);
    await tester.tap(find.text('#fav'));
    await tester.pumpAndSettle();
    expect(oftc.written.last, 'JOIN #fav');
    oftc.incoming.add(':me!u@h JOIN #fav');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '#fav'), findsOneWidget);

    // The room browser asks both networks and labels each room.
    await tester.tap(find.byTooltip('Browse rooms'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Rooms on 2 networks'), findsOneWidget);
    expect(transports['irc.libera.chat']!.written.last, 'LIST');
    expect(oftc.written.last, 'LIST');
    transports['irc.libera.chat']!.incoming
      ..add(':s 322 me #libroom 50 :Libera room')
      ..add(':s 323 me :End');
    oftc.incoming
      ..add(':s 322 me #oftcroom 40 :OFTC room')
      ..add(':s 323 me :End');
    await tester.pumpAndSettle();
    expect(find.text('2 of 2 rooms'), findsOneWidget);
    expect(
      find.textContaining('OFTC · OFTC room', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Libera.Chat'));
    await tester.pumpAndSettle();
    expect(find.text('#oftcroom'), findsNothing);
    expect(find.text('1 of 1 rooms'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'All networks'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('#oftcroom'));
    await tester.pumpAndSettle();
    expect(oftc.written.last, 'JOIN #oftcroom');

    // Disconnecting and reconnecting keeps the conversation.
    await tester.tap(find.text('#lib'));
    await tester.pumpAndSettle();
    await showTab(tester, 'You');
    await tester.tap(find.byTooltip('Options for Libera.Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect from Libera.Chat'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(
      transports['irc.libera.chat']!.written,
      contains(startsWith('QUIT')),
    );
    await tester.tap(find.byTooltip('Options for Libera.Chat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect to Libera.Chat'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(transports['irc.libera.chat']!.written, contains('NICK me'));
    expect(chatText('hello from libera'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('chat history survives disconnects and app restarts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    final history = MemoryChatHistoryStore();
    var transport = FakeTransport();

    Future<void> launch() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            keyValueStoreProvider.overrideWithValue(store),
            chatHistoryStoreProvider.overrideWithValue(history),
            transportFactoryProvider.overrideWithValue(
              (host, port, {required useTls, trustedFingerprints = const {}}) =>
                  transport,
            ),
          ],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    await launch();
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'me');
    await tester.tap(find.text('Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming
      ..add(':s 001 me :Welcome')
      ..add(':me!u@h JOIN #room')
      ..add(':bob!b@h PRIVMSG #room :remember this')
      ..add(':bob!b@h JOIN #room')
      ..add(':alice!a@h PRIVMSG me :secret hello');
    await tester.pumpAndSettle();
    expect(history.conversations.keys, {
      'irc.libera.chat/#room',
      'irc.libera.chat/alice',
    });
    // Join/quit noise isn't saved.
    expect(history.conversations['irc.libera.chat/#room']!.length, 1);

    // Next launch: Continue rejoins #room and reopens the chat with alice,
    // both with their saved messages.
    transport = FakeTransport();
    await launch();
    await tester.tap(find.text('Continue on Libera.Chat'));
    await tester.pumpAndSettle();
    transport.incoming.add(':s 001 me :Welcome');
    await tester.pumpAndSettle();
    expect(transport.written, contains('JOIN #room'));
    transport.incoming.add(':me!u@h JOIN #room');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, '#room'), findsOneWidget);
    // In the chat (and as the row's preview in Rooms).
    expect(
      find.descendant(
        of: find.byType(ChatScreen),
        matching: chatText('remember this'),
      ),
      findsOneWidget,
    );
    expect(chatText('Saved messages above'), findsOneWidget);

    await tester.tap(find.text('alice'));
    await tester.pumpAndSettle();
    expect(chatText('secret hello'), findsOneWidget);

    // Clear history (in Chat info) removes it on screen and on the device.
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear history'));
    await tester.pumpAndSettle();
    expect(chatText('secret hello'), findsNothing);
    expect(history.conversations.containsKey('irc.libera.chat/alice'), false);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('create a private room, change its settings and keep it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeTransport();
    // Flood control (which uses the real clock) spaces out lines after a
    // burst of five, so let real time pass before checking what was sent.
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
    transport.incoming.add(':s 001 me :Welcome');
    await tester.pumpAndSettle();

    // Create a room with a password, private and hidden by default.
    await showTab(tester, 'You');
    await tester.tap(find.text('Create a room'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Room name'),
      'friends',
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'Password'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Room password'),
      'pw',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'JOIN #friends pw');

    // The server makes us its operator; the app applies the settings.
    transport.incoming
      ..add(':me!u@h JOIN #friends')
      ..add(':s 353 me = #friends :@me')
      ..add(':s 366 me #friends :End')
      ..add(':s 324 me #friends +n');
    await tester.pumpAndSettle();
    expect(transport.written, contains('MODE #friends'));
    expect(transport.written.last, 'MODE #friends +istk pw');
    expect(find.widgetWithText(AppBar, '#friends'), findsOneWidget);
    expect(chatText('You created #friends'), findsOneWidget);
    transport.incoming.add(':me!u@h MODE #friends +istk pw');
    await tester.pumpAndSettle();
    expect(chatText('invite only on'), findsOneWidget);

    // Room settings (in Chat info): turn Private off, invite bob, keep it.
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Room settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('You run this room'), findsOneWidget);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Private'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'MODE #friends -i');

    // The settings sheet is long now; scroll to the invite box.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Invite'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Nickname'), 'bob');
    await tester.tap(find.widgetWithText(FilledButton, 'Invite'));
    // Opening the settings also asked for the ban list, so flood control
    // may hold this line back for a moment.
    await flush();
    expect(transport.written.last, 'INVITE bob #friends');

    // Let the "Invited bob" snack bar go away.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Keep this room').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Keep this room'));
    await flush();
    expect(transport.written.last, 'PRIVMSG ChanServ :REGISTER #friends');
    expect(find.widgetWithText(AppBar, 'ChanServ'), findsOneWidget);

    // Someone invites us: a banner offers Join.
    transport.incoming.add(':alice!a@h INVITE me #club');
    await tester.pumpAndSettle();
    expect(find.text('alice invited you to #club.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Join'));
    await flush();
    expect(transport.written.last, 'JOIN #club');
    expect(find.text('alice invited you to #club.'), findsNothing);

    // Creating a room someone else already runs changes nothing.
    await showTab(tester, 'You');
    await tester.tap(find.text('Create a room'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Room name'),
      'taken',
    );
    await tester.tap(find.text('Create'));
    await flush();
    expect(transport.written.last, 'JOIN #taken');
    transport.incoming
      ..add(':me!u@h JOIN #taken')
      ..add(':s 353 me = #taken :@carol me')
      ..add(':s 366 me #taken :End')
      ..add(':s 324 me #taken +nt');
    await flush();
    expect(transport.written.last, 'MODE #taken');
    expect(chatText('someone else runs it'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('reply to someone so they are notified', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final transport = FakeTransport();
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
      ..add(':me!u@h JOIN #chat')
      ..add(':s 353 me = #chat :alice bob me')
      ..add(':s 366 me #chat :End')
      ..add(':alice!a@h PRIVMSG #chat :anyone tried the beta?')
      ..add(':bob!b@h PRIVMSG #chat :me: look at this');
    await tester.pumpAndSettle();

    // Long-press alice's line (phones) and pick Reply.
    await tester.longPress(chatText('anyone tried the beta?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply to alice'));
    await tester.pumpAndSettle();
    expect(chatText('Replying to alice'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reply to alice'),
      'yes, it works',
    );
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'PRIVMSG #chat :alice: yes, it works');
    expect(chatText('Replying to'), findsNothing);

    // Swiping a line right also replies; the X cancels.
    await tester.drag(chatText('look at this'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(chatText('Replying to bob'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pumpAndSettle();
    expect(chatText('Replying to'), findsNothing);

    // The name menu offers Reply too.
    await tester.tap(find.byTooltip('People'));
    await tester.pumpAndSettle();
    // bob's name is also on his messages; tap it in the people list.
    await tester.tap(
      find.descendant(of: find.byType(Drawer), matching: find.text('bob')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply to bob here'));
    await tester.pumpAndSettle();
    expect(chatText('Replying to bob: me: look at this'), findsOneWidget);
    await tester.tap(find.byTooltip('Cancel reply'));
    await tester.pumpAndSettle();

    // Tab completes a name, addressed at the start of the line.
    await tester.enterText(composerField, 'al');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'alice: '), findsOneWidget);

    // Your own line can't be replied to; private chats have no reply button.
    expect(find.byTooltip('Reply to me'), findsNothing);
    transport.incoming.add(':carol!c@h PRIVMSG me :hello there');
    await tester.pumpAndSettle();
    await tester.tap(find.text('carol'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Reply to carol'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('appearance: pick dark mode, a theme and text size', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    Future<void> launch() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ProviderScope(
          overrides: [keyValueStoreProvider.overrideWithValue(store)],
          child: const IrcApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    await launch();
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High contrast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large'));
    await tester.pumpAndSettle();

    BuildContext ctx() => tester.element(find.byType(Scaffold).last);
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    expect(Theme.of(ctx()).colorScheme.surface, Colors.black);
    expect(MediaQuery.textScalerOf(ctx()).scale(10), closeTo(11.5, 0.01));

    // Remembered on the next launch.
    await launch();
    expect(Theme.of(ctx()).brightness, Brightness.dark);
    expect(Theme.of(ctx()).colorScheme.surface, Colors.black);
  });

  testWidgets('change nickname from You', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    final transport = FakeTransport();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
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
      ..add(':me!u@h JOIN #chat');
    await tester.pumpAndSettle();

    // Your nickname is on each network's row in You.
    Future<void> openDialog() async {
      await showTab(tester, 'You');
      await tester.tap(
        find.byWidgetPredicate(
          (w) =>
              w is ActionChip &&
              (w.tooltip ?? '').startsWith('Change nickname on'),
        ),
      );
      await tester.pumpAndSettle();
    }

    // A bad name is refused in the dialog.
    await openDialog();
    await tester.enterText(
      find.widgetWithText(TextField, 'New nickname'),
      '9 lives',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await tester.pumpAndSettle();
    expect(find.textContaining('starting with a letter'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'New nickname'),
      'newme',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await tester.pumpAndSettle();
    expect(transport.written.last, 'NICK newme');
    expect(store.values['savedConnection'], contains('"nick":"newme"'));
    transport.incoming.add(':me!u@h NICK :newme');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chat info'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Connected as newme'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(chatText('me is now known as newme'), findsOneWidget);

    // A taken name keeps the old one and says so.
    await openDialog();
    await tester.enterText(
      find.widgetWithText(TextField, 'New nickname'),
      'bob',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Change'));
    await tester.pumpAndSettle();
    transport.incoming.add(':s 433 newme bob :Nickname is already in use');
    await tester.pumpAndSettle();
    expect(
      find.textContaining(
        "Couldn't change your nickname: Nickname is already in use. "
        "You're still newme.",
        findRichText: true,
      ),
      findsOneWidget,
    );

    // You also opens Appearance.
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Appearance'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pictures in a private chat: show, send, report and block', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryKeyValueStore();
    final transport = FakeTransport();
    const id = 'abcdefghijklmnopqrstuv';
    final picture = img.encodePng(img.Image(width: 120, height: 90));
    final (:sealed, :key) = (await tester.runAsync(
      () => sealPicture(picture),
    ))!;
    final reports = <Map<String, Object?>>[];
    final client = MockClient((req) async {
      if (req.url.path == '/p/$id/raw') return http.Response.bytes(sealed, 200);
      if (req.url.path == '/upload') {
        return http.Response(
          '{"id":"$id","url":"https://pics.test/p/$id"}',
          201,
        );
      }
      if (req.url.path == '/report') {
        reports.add(jsonDecode(req.body) as Map<String, Object?>);
        return http.Response('{"ok":true}', 201);
      }
      return http.Response('', 404);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          pictureServiceProvider.overrideWithValue(
            PictureService(
              host: 'https://pics.test',
              client: client,
              prepare: (b) async => b,
            ),
          ),
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
      ..add(':me!u@h JOIN #chat');
    await tester.pumpAndSettle();
    // No pictures in rooms: + only offers commands.
    expect(find.byTooltip('Add a command'), findsOneWidget);
    expect(find.byTooltip('Add a picture or command'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(IrcApp)),
    );
    final controller = container.read(chatControllerProvider.notifier);
    final link = 'https://pics.test/p/$id#k=$key';
    transport.incoming.add(':bob!b@h PRIVMSG me :📷 Photo from bob: $link');
    await tester.pumpAndSettle();
    controller.selectBuffer(ChatState.bufferKey('irc.libera.chat', 'bob'));
    await tester.pumpAndSettle();

    // From someone you haven't written to: hidden until tapped.
    expect(find.byTooltip('Add a picture or command'), findsOneWidget);
    expect(find.text('Show photo from bob'), findsOneWidget);
    await tester.tap(find.text('Show photo from bob'));
    await tester.pump();
    // Download and decrypt run on real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Show photo from bob'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Picture from bob')), findsOneWidget);

    // Tap for full size (after the image has decoded and has a size).
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.byType(PictureBubble),
        matching: find.byType(Image),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('From bob'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    // Sending: the link goes out as a private message.
    final error = await tester.runAsync(
      () => controller.sendPicture(
        Uint8List.fromList(picture),
        expiry: PictureExpiry.hour,
      ),
    );
    expect(error, isNull);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1600)),
    );
    await tester.pumpAndSettle();
    expect(transport.written.last, startsWith('PRIVMSG bob :📷 Photo from '));
    expect(transport.written.last, contains(': https://pics.test/p/$id#k='));
    expect(transport.written.last, isNot(contains('disappears')));
    expect(transport.written.last, endsWith('&o=1'));

    // Report: sent with the full link, and bob is blocked.
    await tester.tap(find.byTooltip('Picture options').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report picture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam or scam'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Report'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
    expect(reports.single['link'], link);
    expect(reports.single['sender'], 'bob');
    expect(controller.isBlocked('BOB'), isTrue);
    expect(store.values['blockedNicks'], '["bob"]');
    expect(find.text('Picture reported'), findsOneWidget);

    // Blocked: new messages from bob don't show up.
    transport.incoming.add(':bob!b@h PRIVMSG me :are you there?');
    await tester.pumpAndSettle();
    expect(chatText('are you there?'), findsNothing);
    controller.unblockUser('bob');
    transport.incoming.add(':bob!b@h PRIVMSG me :hello again');
    await tester.pumpAndSettle();
    expect(chatText('hello again'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}

class _FailingTransport implements IrcTransport {
  _FailingTransport(this.error);

  final Exception error;

  @override
  Future<void> connect() async => throw error;

  @override
  Stream<String> get lines => const Stream.empty();

  @override
  void writeLine(String line) {}

  @override
  Future<void> close() async {}
}
