import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/updates/update_banner.dart';
import 'package:irc_client/features/updates/update_checker.dart';
import 'package:material_ui/material_ui.dart';

MockClient _github(String tag, {List<Uri>? asked, int status = 200}) =>
    MockClient((req) async {
      asked?.add(req.url);
      return http.Response(
        jsonEncode({
          'tag_name': tag,
          'html_url': 'https://github.com/djc998/mircmobile/releases/tag/$tag',
        }),
        status,
      );
    });

void main() {
  test('version order', () {
    expect(compareVersions('v1.1.0', '1.0.0'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0.0+7'), 0);
    expect(compareVersions('1.0.10', '1.0.9'), greaterThan(0));
    expect(compareVersions('v0.9', '1.0.0'), lessThan(0));
    expect(compareVersions('2.0.0-beta', '1.9.9'), greaterThan(0));
  });

  test('only website downloads on computers check', () {
    bool on(TargetPlatform p, {String v = '1.0.0', String c = 'direct'}) =>
        updatesSupported(version: v, channel: c, platform: p);
    expect(on(TargetPlatform.macOS), isTrue);
    expect(on(TargetPlatform.windows), isTrue);
    expect(on(TargetPlatform.linux), isTrue);
    expect(on(TargetPlatform.iOS), isFalse);
    expect(on(TargetPlatform.android), isFalse);
    expect(on(TargetPlatform.macOS, c: ''), isFalse, reason: 'App Store');
    expect(on(TargetPlatform.macOS, v: ''), isFalse, reason: 'local build');
  });

  ProviderContainer container(
    http.Client client, {
    bool supported = true,
    KeyValueStore? store,
  }) {
    final c = ProviderContainer(
      overrides: [
        updatesSupportedProvider.overrideWithValue(supported),
        appVersionProvider.overrideWithValue('1.0.0'),
        updateHttpClientProvider.overrideWithValue(client),
        if (store != null) keyValueStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('finds a newer release on GitHub', () async {
    final asked = <Uri>[];
    final c = container(_github('v1.1.0', asked: asked));
    await c.read(updateProvider.notifier).check();
    final s = c.read(updateProvider);
    expect(asked.single, latestReleaseApi);
    expect(s.available!.version, '1.1.0');
    expect(s.available!.page.path, '/djc998/mircmobile/releases/tag/v1.1.0');
    expect(s.showBanner, isTrue);
  });

  test('same or older release, errors, or no release: nothing', () async {
    for (final client in [
      _github('v1.0.0'),
      _github('v0.9.0'),
      _github('v9.0.0', status: 404),
      MockClient((_) async => throw const SocketExceptionLike()),
    ]) {
      final c = container(client);
      await c.read(updateProvider.notifier).check();
      expect(c.read(updateProvider).available, isNull);
    }
  });

  test('builds that do not check never ask', () async {
    final asked = <Uri>[];
    final c = container(_github('v2.0.0', asked: asked), supported: false);
    c.read(updateProvider.notifier).start();
    await c.read(updateProvider.notifier).check();
    expect(asked, isEmpty);
  });

  test('Later hides it until the next version; switching off stops', () async {
    final store = MemoryKeyValueStore();
    final c = container(_github('v1.1.0'), store: store);
    final n = c.read(updateProvider.notifier);
    await n.check();
    n.later();
    expect(c.read(updateProvider).showBanner, isFalse);
    expect(
      jsonDecode(store.getString('updates')!),
      containsPair('dismissed', '1.1.0'),
    );

    // A newer one shows again.
    final c2 = container(_github('v1.2.0'), store: store);
    await c2.read(updateProvider.notifier).check();
    expect(c2.read(updateProvider).showBanner, isTrue);

    final asked = <Uri>[];
    final c3 = container(_github('v1.3.0', asked: asked), store: store);
    c3.read(updateProvider.notifier).setEnabled(enabled: false);
    await c3.read(updateProvider.notifier).check();
    expect(asked, isEmpty);
    expect(c3.read(updateProvider).available, isNull);
  });

  testWidgets('the banner: Download opens the release, Later hides it', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updatesSupportedProvider.overrideWithValue(true),
          appVersionProvider.overrideWithValue('1.0.0'),
          updateHttpClientProvider.overrideWithValue(_github('v1.4.0')),
          openUpdatePageProvider.overrideWithValue((page) async {
            opened.add(page);
          }),
        ],
        child: const IrcApp(),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(find.text('IRCage 1.4.0 is available.'), findsOneWidget);
    // The welcome screen is still there below it.
    expect(find.text('Welcome to IRCage'), findsOneWidget);

    await tester.tap(find.text('Download'));
    await tester.pump();
    expect(opened.single.path, endsWith('/v1.4.0'));
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.textContaining('is available'), findsNothing);
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
