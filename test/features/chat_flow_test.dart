import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/irc/irc_transport.dart';
import 'package:irc_client/core/storage/app_storage.dart';
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
    expect(find.text('#tor'), findsOneWidget);

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

    // Star #second (the open room).
    expect(find.text('#second'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);

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
    expect(transport.written, contains('JOIN #second'));
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

    await tester.enterText(
      find.widgetWithText(TextField, 'Message or /command'),
      'hi alice',
    );
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
    expect(
      find.textContaining(
        'alice ~a host.example * Alice Example',
        findRichText: true,
      ),
      findsOneWidget,
    );
    // Unrelated server lines still go to the server tab.
    expect(find.textContaining('MOTD line', findRichText: true), findsNothing);

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

    // Add a second network from the menu; the first stays connected.
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
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

    // The conversation list groups both networks and shows OFTC's favorite.
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('Libera.Chat'), findsWidgets);
    expect(find.text('#lib'), findsOneWidget);
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
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('#lib'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
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
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reconnect to Libera.Chat'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(transports['irc.libera.chat']!.written, contains('NICK me'));
    expect(
      find.textContaining('hello from libera', findRichText: true),
      findsOneWidget,
    );

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
