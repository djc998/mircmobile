/// The terms of use: agreed to once before using the app (route `/terms`),
/// and readable later from Settings → About.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:irc_client/app/legal.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/features/safety/application/safety_controller.dart';
import 'package:material_ui/material_ui.dart';

class TermsScreen extends ConsumerWidget {
  /// With [readOnly], there's no Agree button (opened from Settings).
  const TermsScreen({super.key, this.readOnly = false});

  final bool readOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final agree = !readOnly && !ref.watch(safetyProvider).agreedToTerms;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of use'),
        automaticallyImplyLeading: !agree,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    children: [
                      if (agree) ...[
                        Text(
                          'Before you start, please read and agree to these '
                          'terms.',
                          style: TypeScale.body.copyWith(
                            color: tokens.textMuted,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (final s in termsSections) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          header: true,
                          child: Text(
                            s.title,
                            style: TypeScale.heading.copyWith(
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          s.body,
                          style: TypeScale.body.copyWith(
                            color: tokens.textPrimary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (agree)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: tokens.line)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                      child: FilledButton(
                        onPressed: () {
                          ref.read(safetyProvider.notifier).agreeToTerms();
                          context.go('/');
                        },
                        child: const Text('Agree and continue'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
