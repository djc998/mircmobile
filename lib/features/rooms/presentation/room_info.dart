/// Room info: one page with everything about a room, instead of sheets on
/// top of sheets.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/core/ui/mirc_text.dart';
import 'package:irc_client/features/chat/application/chat_controller.dart';
import 'package:irc_client/features/favorites/application/room_prefs_controller.dart';
import 'package:irc_client/features/rooms/presentation/room_dialogs.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Opens Room info for [channel]: a page on phones, a panel on the right on
/// wider screens. [onPeople] opens the member list (phones and tablets,
/// where it isn't pinned).
Future<void> showRoomInfo(
  BuildContext context, {
  required String networkId,
  required String channel,
  VoidCallback? onPeople,
}) {
  final screen = RoomInfoScreen(
    networkId: networkId,
    channel: channel,
    onPeople: onPeople,
  );
  if (MediaQuery.sizeOf(context).width < 600) {
    return Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => screen));
  }
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close room info',
    barrierColor: Colors.black38,
    transitionDuration: Motion.of(context),
    pageBuilder: (dialog, _, _) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: 440,
        height: double.infinity,
        child: Material(elevation: 8, child: screen),
      ),
    ),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Motion.curve)).animate(animation),
      child: child,
    ),
  );
}

class RoomInfoScreen extends ConsumerWidget {
  const RoomInfoScreen({
    required this.networkId,
    required this.channel,
    this.onPeople,
    super.key,
  });

  final String networkId;
  final String channel;
  final VoidCallback? onPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider);
    final controller = ref.read(chatControllerProvider.notifier);
    final prefs = ref.watch(roomPrefsProvider);
    final notifier = ref.read(roomPrefsProvider.notifier);
    final tokens = AppTokens.of(context);
    final net = state.networks[networkId];
    final chan = net?.client.channel(channel);
    final key = ChatState.bufferKey(networkId, channel);
    final favorite = prefs.isFavorite(networkId, channel);
    final muted = prefs.isMuted(networkId, channel);
    final people = chan?.members.length ?? 0;
    final topic = chan?.topic.trim() ?? '';

    void leave() {
      Navigator.pop(context);
      controller.closeBuffer(key);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Room info'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Close room info',
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Center(child: RoomAvatar(name: channel, size: 72)),
            const SizedBox(height: 12),
            Center(
              child: Text(
                channel,
                textAlign: TextAlign.center,
                style: TypeScale.title.copyWith(color: tokens.textPrimary),
              ),
            ),
            if (net != null)
              Center(
                child: Text(
                  '$people ${people == 1 ? 'person' : 'people'} · '
                  '${net.label}',
                  style: TypeScale.meta.copyWith(color: tokens.textMuted),
                ),
              ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                border: Border.all(color: tokens.line),
                borderRadius: BorderRadius.circular(tokens.radius(Radii.card)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Topic',
                    style: TypeScale.meta.copyWith(
                      color: tokens.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      style: TypeScale.body.copyWith(color: tokens.textPrimary),
                      children: topic.isEmpty
                          ? const [TextSpan(text: 'No topic set.')]
                          : mircSpans(
                              topic,
                              tokens: tokens,
                              background: tokens.surfaceRaised,
                              textColor: tokens.textPrimary,
                              colours: ref.watch(appearanceProvider).ircColours,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(favorite ? Icons.star : Icons.star_border),
              title: Text(
                favorite ? 'Remove from favorites' : 'Add to favorites',
              ),
              onTap: () => notifier.toggleFavorite(networkId, channel),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_outlined,
              ),
              title: const Text('Mute'),
              subtitle: const Text(
                "Unread counts turn grey and don't add to Mentions. "
                'Messages that mention you still stand out.',
              ),
              value: muted,
              onChanged: (_) => notifier.toggleMute(networkId, channel),
            ),
            if (onPeople != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline),
                title: Text('People ($people)'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(context);
                  onPeople!();
                },
              ),
            const Divider(height: 32),
            RoomSettingsSheet(
              networkId: networkId,
              channel: channel,
              embedded: true,
            ),
            const Divider(height: 32),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Clear history'),
              onTap: () => unawaited(controller.clearHistory(key)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.logout,
                color: tokens.readable(tokens.mention),
              ),
              title: Text(
                'Leave room',
                style: TextStyle(color: tokens.readable(tokens.mention)),
              ),
              onTap: leave,
            ),
          ],
        ),
      ),
    );
  }
}
