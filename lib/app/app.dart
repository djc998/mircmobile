import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/features/chat/presentation/chat_screen.dart';
import 'package:irc_client/features/connection/presentation/network_picker_screen.dart';
import 'package:irc_client/features/discovery/presentation/room_browser_screen.dart';
import 'package:material_ui/material_ui.dart';

/// Working name until the final app name is chosen.
const String appName = 'mIRC Mobile';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const NetworkPickerScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatScreen(),
        routes: [
          GoRoute(
            path: 'rooms',
            builder: (context, state) => const RoomBrowserScreen(),
          ),
        ],
      ),
    ],
  ),
);

class IrcApp extends ConsumerWidget {
  const IrcApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: appName,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
