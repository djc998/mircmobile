import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(PrefsKeyValueStore(prefs)),
        secretStoreProvider.overrideWithValue(SecureSecretStore()),
      ],
      child: const IrcApp(),
    ),
  );
}
