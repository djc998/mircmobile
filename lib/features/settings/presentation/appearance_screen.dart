import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Light/dark mode, colour theme and text size, with live previews.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final controller = ref.read(appearanceProvider.notifier);
    final theme = Theme.of(context);
    final brightness = theme.brightness;

    return Scaffold(
      appBar: AppBar(title: const Text('Appearance')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Mode', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<AppearanceMode>(
              segments: const [
                ButtonSegment(
                  value: AppearanceMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: AppearanceMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: AppearanceMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {appearance.mode},
              onSelectionChanged: (s) => controller.setMode(s.first),
            ),
            const SizedBox(height: 24),
            Text('Theme', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final preset in ThemePreset.values)
              _ThemeCard(
                preset: preset,
                brightness: brightness,
                selected: appearance.preset == preset,
                onTap: () => controller.setPreset(preset),
              ),
            const SizedBox(height: 24),
            Text('Text size', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<double>(
              segments: [
                for (final MapEntry(:key, :value) in textSizes.entries)
                  ButtonSegment(value: value, label: Text(key)),
              ],
              selected: {appearance.textScale},
              onSelectionChanged: (s) => controller.setTextScale(s.first),
            ),
            const SizedBox(height: 8),
            Text(
              'All chat colours are checked to be easy to read on their '
              'background in both light and dark mode.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// A theme choice with a small chat preview drawn in that theme.
class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.brightness,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final Brightness brightness;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.build(preset, brightness);
    final chat = preview.extension<ChatColors>()!;
    final scheme = preview.colorScheme;
    final style = preview.textTheme.bodyMedium!.copyWith(
      color: scheme.onSurface,
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outlineVariant,
          width: selected ? 3 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(preset.label),
              subtitle: Text(preset.description),
              trailing: selected
                  ? Icon(
                      Icons.check_circle,
                      color: Theme.of(context).colorScheme.primary,
                    )
                  : null,
            ),
            Container(
              color: scheme.surface,
              padding: const EdgeInsets.all(12),
              child: DefaultTextStyle(
                style: style,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '<alice> ',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: chat.nickColor('alice'),
                            ),
                          ),
                          const TextSpan(text: 'hi everyone!'),
                        ],
                      ),
                    ),
                    Text('• bob joined', style: TextStyle(color: chat.event)),
                    Text(
                      '-ChanServ- Welcome to #chat',
                      style: TextStyle(color: chat.notice),
                    ),
                    Text(
                      '* carol waves',
                      style: TextStyle(
                        color: chat.action,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    Text(
                      '⚠ Cannot send to channel',
                      style: TextStyle(color: scheme.error),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
