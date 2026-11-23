/// Settings: everything that isn't about one chat, in grouped lists.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/app/app.dart';
import 'package:irc_client/app/legal.dart';
import 'package:irc_client/core/irc/irc_client.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/calls/application/call_controller.dart';
import 'package:irc_client/features/calls/presentation/call_widgets.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/safety/application/safety_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Route `/settings`.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _deleteHistory() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Delete saved history?'),
        content: const Text(
          'This deletes the saved messages of every room and private chat '
          'on this device. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(chatControllerProvider.notifier).clearAllHistory();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved history deleted.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatControllerProvider); // for ignored people
    final controller = ref.read(chatControllerProvider.notifier);
    final prefs = ref.watch(roomPrefsProvider);
    final call = ref.watch(callControllerProvider);
    final safety = ref.watch(safetyProvider);
    final tokens = AppTokens.of(context);
    final ignored = controller.blockedNicks.toList()..sort();
    final muted = [
      for (final MapEntry(key: host, value: names) in prefs.muted.entries)
        for (final name in names) (host: host, name: name),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _Group(
                  title: 'Look',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Appearance'),
                      subtitle: const Text(
                        'Theme, accent, density, font and text size',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/appearance'),
                    ),
                  ],
                ),
                _Group(
                  title: 'Safety',
                  children: [
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.filter_alt_outlined),
                      title: const Text('Hide offensive words'),
                      subtitle: const Text(
                        'Slurs and strong swearing in messages, topics and '
                        'previews show as s***',
                      ),
                      value: safety.filterWords,
                      onChanged: (v) => ref
                          .read(safetyProvider.notifier)
                          .setFilterWords(enabled: v),
                    ),
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.shield_outlined),
                      title: const Text('Hide adult rooms'),
                      subtitle: const Text(
                        'Leave rooms about sex and nudity out of Discover',
                      ),
                      value: safety.hideAdultRooms,
                      onChanged: (v) => ref
                          .read(safetyProvider.notifier)
                          .setHideAdultRooms(enabled: v),
                    ),
                  ],
                ),
                _Group(
                  title: 'Chat history',
                  children: [
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.history),
                      title: const Text('Save chat history on this device'),
                      subtitle: const Text(
                        'Rooms and private chats keep their messages after '
                        'you disconnect or close the app',
                      ),
                      value: controller.saveHistory,
                      onChanged: (v) async {
                        await controller.setSaveHistory(enabled: v);
                        if (mounted) setState(() {});
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: const Text('Delete saved history'),
                      onTap: () => unawaited(_deleteHistory()),
                    ),
                  ],
                ),
                _Group(
                  title: 'Calls',
                  children: [
                    SwitchListTile.adaptive(
                      secondary: const Icon(Icons.shield_outlined),
                      title: const Text('Hide my IP address on calls'),
                      subtitle: const Text(
                        'Calls go through a relay, so the other person '
                        'never sees your IP address',
                      ),
                      value: call.relayOnly,
                      onChanged: (v) => unawaited(
                        ref
                            .read(callControllerProvider.notifier)
                            .setRelayOnly(enabled: v),
                      ),
                    ),
                    const ListTile(
                      leading: Icon(Icons.videocam_outlined),
                      title: Text('Camera and microphone'),
                      subtitle: Text('Allow them for voice and video calls'),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: DeviceAccessHelp(),
                    ),
                  ],
                ),
                _Group(
                  title: 'Ignored people',
                  children: [
                    if (ignored.isEmpty)
                      const ListTile(
                        title: Text('Nobody'),
                        subtitle: Text(
                          'Ignore someone from their profile card (tap their '
                          'name) to hide their messages, photos and '
                          'invitations.',
                        ),
                      ),
                    for (final nick in ignored)
                      ListTile(
                        leading: const Icon(Icons.visibility_off_outlined),
                        title: Text(nick),
                        trailing: TextButton(
                          onPressed: () => controller.unblockUser(nick),
                          child: Text(
                            'Stop ignoring',
                            semanticsLabel: 'Stop ignoring $nick',
                          ),
                        ),
                      ),
                  ],
                ),
                _Group(
                  title: 'Muted chats',
                  children: [
                    if (muted.isEmpty)
                      const ListTile(
                        title: Text('None'),
                        subtitle: Text(
                          'Mute a room from Room info, or long-press a chat '
                          'in Rooms.',
                        ),
                      ),
                    for (final m in muted)
                      ListTile(
                        leading: const Icon(Icons.notifications_off_outlined),
                        title: Text(m.name),
                        subtitle: Text(m.host),
                        trailing: TextButton(
                          onPressed: () => ref
                              .read(roomPrefsProvider.notifier)
                              .toggleMute(m.host, m.name),
                          child: Text(
                            'Unmute',
                            semanticsLabel: 'Unmute ${m.name}',
                          ),
                        ),
                      ),
                  ],
                ),
                _Group(
                  title: 'About',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text(appName),
                      subtitle: Text(IrcClient.clientVersion),
                    ),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined),
                      title: const Text('Terms of use'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/terms?read=1'),
                    ),
                    const ListTile(
                      leading: Icon(Icons.mail_outline),
                      title: Text('Contact'),
                      subtitle: SelectableText(supportContact),
                    ),
                    ListTile(
                      leading: const Icon(Icons.description_outlined),
                      title: const Text('Open-source licenses'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: appName,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Chat rooms, the way they used to be. Only better.',
                  textAlign: TextAlign.center,
                  style: TypeScale.meta.copyWith(color: tokens.textMuted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled group of rows on a raised card, like the system settings.
class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: TypeScale.meta.copyWith(
                  color: tokens.textMuted,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          Material(
            color: tokens.surfaceRaised,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: tokens.line),
              borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, child) in children.indexed) ...[
                  if (i > 0) Divider(height: 1, color: tokens.line),
                  child,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
