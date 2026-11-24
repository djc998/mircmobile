import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irc_client/core/storage/app_storage.dart';

/// A system store that can't be reached, like Linux with no keyring.
class _Unavailable implements SecretStore {
  int calls = 0;

  Never _fail() {
    calls++;
    throw PlatformException(code: 'Libsecret error');
  }

  @override
  Future<String?> read(String key) async => _fail();

  @override
  Future<void> write(String key, String value) async => _fail();

  @override
  Future<void> delete(String key) async => _fail();
}

void main() {
  test('uses the system store while it works', () async {
    final system = MemorySecretStore();
    final store = FallbackSecretStore(system);
    await store.write('sasl:libera:me', 'hunter2');
    expect(system.values, {'sasl:libera:me': 'hunter2'});
    expect(await store.read('sasl:libera:me'), 'hunter2');
    await store.delete('sasl:libera:me');
    expect(system.values, isEmpty);
    expect(store.usingMemory, isFalse);
  });

  test('without a keyring, keeps secrets in memory', () async {
    final system = _Unavailable();
    final store = FallbackSecretStore(system);
    expect(await store.read('sasl:libera:me'), isNull);
    expect(store.usingMemory, isTrue);
    await store.write('sasl:libera:me', 'hunter2');
    expect(await store.read('sasl:libera:me'), 'hunter2');
    await store.delete('sasl:libera:me');
    expect(await store.read('sasl:libera:me'), isNull);
    // Gave up on the system store after the first failure.
    expect(system.calls, 1);
  });
}
