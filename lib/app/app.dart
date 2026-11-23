import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/core/safety/content_filter.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/features/calls/presentation/call_widgets.dart';
import 'package:irc_client/features/chat/presentation/chat_shell.dart';
import 'package:irc_client/features/connection/presentation/network_picker_screen.dart';
import 'package:irc_client/features/discovery/presentation/room_browser_screen.dart';
import 'package:irc_client/features/safety/application/safety_controller.dart';
import 'package:irc_client/features/safety/presentation/terms_screen.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:irc_client/features/settings/presentation/appearance_screen.dart';
import 'package:irc_client/features/settings/presentation/settings_screen.dart';
import 'package:material_ui/material_ui.dart';

/// The app's name, shown in the task switcher and window title.
const String appName = 'IRCage';

final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    // The terms come first, once (and again when they change).
    redirect: (context, state) {
      if (ref.read(safetyProvider).agreedToTerms) return null;
      return state.matchedLocation == '/terms' ? null : '/terms';
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const NetworkPickerScreen(),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, state) =>
            TermsScreen(readOnly: state.uri.queryParameters['read'] == '1'),
      ),
      GoRoute(
        path: '/appearance',
        builder: (context, state) => const AppearanceScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatShell(),
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
    final appearance = ref.watch(appearanceProvider);
    return MaterialApp.router(
      title: appName,
      theme: AppTheme.build(
        appearance.preset,
        Brightness.light,
        accent: appearance.accent,
      ),
      darkTheme: AppTheme.build(
        appearance.preset,
        Brightness.dark,
        accent: appearance.accent,
      ),
      themeMode: switch (appearance.mode) {
        AppearanceMode.system => ThemeMode.system,
        AppearanceMode.light => ThemeMode.light,
        AppearanceMode.dark => ThemeMode.dark,
      },
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(
            MediaQuery.textScalerOf(context).scale(appearance.textScale),
          ),
        ),
        child: ContentFilter(
          enabled: ref.watch(safetyProvider.select((s) => s.filterWords)),
          child: CallOverlay(child: child!),
        ),
      ),
    );
  }
}
