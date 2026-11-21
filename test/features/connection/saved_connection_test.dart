import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/connection/data/saved_connection.dart';

void main() {
  test('remembers every open network and forgets closed ones', () async {
    final repo = SavedConnectionRepository(
      MemoryKeyValueStore(),
      MemorySecretStore(),
    );
    await repo.save(
      const SavedConnection(
        nick: 'me',
        networkHost: 'irc.libera.chat',
        networkHosts: ['irc.libera.chat', 'irc.oftc.net'],
      ),
    );
    expect(repo.load()!.openNetworks, ['irc.libera.chat', 'irc.oftc.net']);

    await repo.removeNetwork('IRC.OFTC.NET');
    expect(repo.load()!.openNetworks, ['irc.libera.chat']);
  });

  test('older saves fall back to the last network', () {
    const old = SavedConnection(nick: 'me', networkHost: 'irc.efnet.org');
    expect(old.openNetworks, ['irc.efnet.org']);
  });

  test('an empty password keeps the saved one', () async {
    final secrets = MemorySecretStore();
    final repo = SavedConnectionRepository(MemoryKeyValueStore(), secrets);
    const conn = SavedConnection(
      nick: 'me',
      networkHost: 'irc.libera.chat',
      account: 'acct',
    );
    await repo.save(conn, password: 'pw');
    await repo.save(conn, password: '');
    expect(await repo.loadPassword('irc.libera.chat', 'acct'), 'pw');

    await repo.save(
      const SavedConnection(
        nick: 'me',
        networkHost: 'irc.libera.chat',
        account: 'acct',
        rememberPassword: false,
      ),
    );
    expect(await repo.loadPassword('irc.libera.chat', 'acct'), isNull);
  });
}
