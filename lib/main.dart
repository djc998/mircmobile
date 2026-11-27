import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/core/storage/app_storage.dart';
import 'package:irc_client/features/chat/data/chat_history_store.dart';
import 'package:irc_client/features/notifications/data/message_notifier.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // App-private folder (not backed up to iCloud Documents, not user-visible).
  final support = await getApplicationSupportDirectory();
  final notifier = await LocalMessageNotifier.create();
  runApp(
    ProviderScope(
      overrides: [
        keyValueStoreProvider.overrideWithValue(PrefsKeyValueStore(prefs)),
        secretStoreProvider.overrideWithValue(
          FallbackSecretStore(SecureSecretStore()),
        ),
        messageNotifierProvider.overrideWithValue(notifier),
        chatHistoryStoreProvider.overrideWithValue(
          FileChatHistoryStore(Directory('${support.path}/history')),
        ),
      ],
      child: const IrcApp(),
    ),
  );
}
