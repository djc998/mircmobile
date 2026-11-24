/// "IRCage 1.1.0 is available" across the top of the app, with Download
/// and Later. Starts the update checks; does nothing in builds that don't
/// check (see `updatesSupported`).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/updates/update_checker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a release page in the browser; tests replace it.
final openUpdatePageProvider = Provider<Future<void> Function(Uri page)>(
  (ref) =>
      (page) => launchUrl(page, mode: LaunchMode.externalApplication),
);

class UpdateBannerHost extends ConsumerStatefulWidget {
  const UpdateBannerHost({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<UpdateBannerHost> createState() => _UpdateBannerHostState();
}

class _UpdateBannerHostState extends ConsumerState<UpdateBannerHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(updateProvider.notifier).start();
    });
  }

  @override
  Widget build(BuildContext context) {
    final update = ref.watch(updateProvider);
    final available = update.available;
    if (!update.showBanner || available == null) return widget.child;
    final tokens = AppTokens.of(context);
    return Column(
      children: [
        Material(
          color: Color.alphaBlend(tokens.accentSoft, tokens.surface),
          child: SafeArea(
            bottom: false,
            child: Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                child: Row(
                  children: [
                    Icon(Icons.system_update_alt, color: tokens.onAccentSoft),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'IRCage ${available.version} is available.',
                        style: TypeScale.body.copyWith(
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: ref.read(updateProvider.notifier).later,
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => unawaited(
                        ref.read(openUpdatePageProvider)(available.page),
                      ),
                      child: const Text('Download'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Expanded(
          // The banner took the top inset; the app below shouldn't add it.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
