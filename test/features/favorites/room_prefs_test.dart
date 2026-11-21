import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/connection/data/saved_connection.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';

void main() {
  group('RoomPrefsController', () {
    late MemoryKeyValueStore store;

    ProviderContainer make() => ProviderContainer(
      overrides: [keyValueStoreProvider.overrideWithValue(store)],
    );

    setUp(() => store = MemoryKeyValueStore());

    test('toggles favorites per network, case-insensitively', () {
      final c = make();
      addTearDown(c.dispose);
      final n = c.read(roomPrefsProvider.notifier)
        ..toggleFavorite('irc.libera.chat', '#Linux')
        ..toggleFavorite('irc.oftc.net', '#debian');
      var prefs = c.read(roomPrefsProvider);
      expect(prefs.favoritesFor('IRC.LIBERA.CHAT'), ['#Linux']);
      expect(prefs.isFavorite('irc.libera.chat', '#linux'), isTrue);
      expect(prefs.isFavorite('irc.libera.chat', '#debian'), isFalse);

      n.toggleFavorite('irc.libera.chat', '#linux');
      prefs = c.read(roomPrefsProvider);
      expect(prefs.favoritesFor('irc.libera.chat'), isEmpty);
      expect(prefs.favoritesFor('irc.oftc.net'), ['#debian']);
    });

    test('recents are newest first, deduplicated and capped', () {
      final c = make();
      addTearDown(c.dispose);
      final n = c.read(roomPrefsProvider.notifier);
      for (var i = 0; i < 12; i++) {
        n.addRecent('h', '#room$i');
      }
      n.addRecent('h', '#ROOM5');
      final recents = c.read(roomPrefsProvider).recentsFor('h');
      expect(recents.length, maxRecentRooms);
      expect(recents.first, '#ROOM5');
      expect(recents.where((r) => r.toLowerCase() == '#room5').length, 1);
      expect(recents, isNot(contains('#room0')));

      n.clearRecents('h');
      expect(c.read(roomPrefsProvider).recentsFor('h'), isEmpty);
    });

    test('persists across restarts and survives corrupt data', () async {
      final first = make();
      first.read(roomPrefsProvider.notifier)
        ..toggleFavorite('h', '#a')
        ..addRecent('h', '#b');
      await pumpEventQueue();
      first.dispose();

      final second = make();
      addTearDown(second.dispose);
      final prefs = second.read(roomPrefsProvider);
      expect(prefs.favoritesFor('h'), ['#a']);
      expect(prefs.recentsFor('h'), ['#b']);

      store.values['roomPrefs'] = '{not json';
      final third = make();
      addTearDown(third.dispose);
      expect(third.read(roomPrefsProvider).favorites, isEmpty);
    });
  });

  group('SavedConnectionRepository', () {
    test(
      'round-trips settings and keeps the password in the secret store',
      () async {
        final store = MemoryKeyValueStore();
        final secrets = MemorySecretStore();
        final repo = SavedConnectionRepository(store, secrets);
        expect(repo.load(), isNull);

        await repo.save(
          const SavedConnection(
            nick: 'dennis',
            networkHost: 'irc.libera.chat',
            account: 'dennis',
            rejoinFavorites: false,
          ),
          password: 'hunter2',
        );
        final loaded = repo.load()!;
        expect(loaded.nick, 'dennis');
        expect(loaded.networkHost, 'irc.libera.chat');
        expect(loaded.account, 'dennis');
        expect(loaded.rejoinFavorites, isFalse);
        expect(store.values.values.join(), isNot(contains('hunter2')));
        expect(await repo.loadPassword('irc.libera.chat', 'dennis'), 'hunter2');
      },
    );

    test('forgets the password when "remember" is off', () async {
      final secrets = MemorySecretStore();
      final repo = SavedConnectionRepository(MemoryKeyValueStore(), secrets);
      const saved = SavedConnection(
        nick: 'n',
        networkHost: 'h',
        account: 'acct',
      );
      await repo.save(saved, password: 'pw');
      expect(secrets.values, isNotEmpty);
      await repo.save(
        const SavedConnection(
          nick: 'n',
          networkHost: 'h',
          account: 'acct',
          rememberPassword: false,
        ),
        password: 'pw',
      );
      expect(secrets.values, isEmpty);
    });

    test('corrupt data loads as null', () {
      final repo = SavedConnectionRepository(
        MemoryKeyValueStore({'savedConnection': '[1,2'}),
        MemorySecretStore(),
      );
      expect(repo.load(), isNull);
    });
  });
}
