import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:irc_client/core/theme/app_theme.dart';
import 'package:irc_client/core/theme/tokens.dart';
import 'package:irc_client/core/ui/avatars.dart';
import 'package:irc_client/features/settings/application/appearance_controller.dart';
import 'package:material_ui/material_ui.dart';

/// Light/dark mode, theme, accent, density and text size, with live
/// previews.
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
                accent: appearance.accent,
                density: appearance.density,
                selected: appearance.preset == preset,
                onTap: () => controller.setPreset(preset),
              ),
            const SizedBox(height: 24),
            Text('Accent colour', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _AccentPicker(
              selected: appearance.accent,
              brightness: brightness,
              enabled: appearance.accentApplies,
              onPick: controller.setAccent,
            ),
            if (!appearance.accentApplies)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Accent colours apply to the Default theme. '
                  '${appearance.preset.label} keeps its own colours.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 24),
            Text('Density', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<ChatDensity>(
              segments: [
                for (final d in ChatDensity.values)
                  ButtonSegment(value: d, label: Text(d.label)),
              ],
              selected: {appearance.density},
              onSelectionChanged: (s) => controller.setDensity(s.first),
            ),
            const SizedBox(height: 4),
            Text(
              appearance.density.description,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            Text('Message font', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<MessageFont>(
              segments: [
                for (final f in MessageFont.values)
                  ButtonSegment(
                    value: f,
                    label: Text(
                      f.label,
                      style: f == MessageFont.mono
                          ? const TextStyle(
                              fontFamilyFallback: MessageFont.monoFamilies,
                            )
                          : null,
                    ),
                  ),
              ],
              selected: {appearance.font},
              onSelectionChanged: (s) => controller.setFont(s.first),
            ),
            const SizedBox(height: 4),
            Text(appearance.font.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show mIRC colours and styles'),
              subtitle: const Text(
                'Colours, bold, italics and underline that people add to '
                'their messages. Colours are adjusted to stay readable on '
                'your theme.',
              ),
              value: appearance.ircColours,
              onChanged: (v) => controller.setIrcColours(show: v),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show images from links automatically'),
              subtitle: const Text(
                'When off, tap a link preview to load it. Loading an image '
                'lets the website it comes from see your IP address. '
                'Videos always wait for a tap.',
              ),
              value: appearance.autoLinkImages,
              onChanged: (v) => controller.setAutoLinkImages(show: v),
            ),
            const SizedBox(height: 24),
            Text('Text size', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<double>(
              // Four labels fit on a phone only without the check mark.
              showSelectedIcon: false,
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
    required this.accent,
    required this.density,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final Brightness brightness;
  final AccentColor accent;
  final ChatDensity density;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = AppTheme.build(preset, brightness, accent: accent);
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
              child: Theme(
                data: preview,
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
                      if (density == ChatDensity.comfortable) ...[
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            RoomAvatar(name: '#chat', size: 28),
                            SizedBox(width: 8),
                            NickAvatar(
                              nick: 'alice',
                              size: 24,
                              role: NickRole.op,
                            ),
                            NickAvatar(nick: 'bob', size: 24),
                            NickAvatar(nick: 'carol', size: 24, away: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Eight accent swatches. Each is a 48-pt target with a check on the one in
/// use; screen readers hear "Indigo accent, selected".
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({
    required this.selected,
    required this.brightness,
    required this.enabled,
    required this.onPick,
  });

  final AccentColor selected;
  final Brightness brightness;
  final bool enabled;
  final void Function(AccentColor) onPick;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.onSurface;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      // One row of 8 when it fits, otherwise two even rows of 4.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final oneRow = constraints.maxWidth >= 8 * 48 + 7 * 4;
          // Align lets the narrower box keep its width inside the list.
          return Align(
            alignment: AlignmentDirectional.centerStart,
            child: SizedBox(
              width: oneRow ? null : 4 * 48 + 3 * 16,
              child: Wrap(
                spacing: oneRow ? 4 : 16,
                runSpacing: 4,
                children: [
                  for (final accent in AccentColor.values)
                    Semantics(
                      button: true,
                      selected: accent == selected,
                      enabled: enabled,
                      label: '${accent.label} accent',
                      excludeSemantics: true,
                      child: Tooltip(
                        message: accent.label,
                        child: InkResponse(
                          onTap: enabled ? () => onPick(accent) : null,
                          radius: 24,
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: accent.forBrightness(brightness),
                                  shape: BoxShape.circle,
                                  border: accent == selected
                                      ? Border.all(color: outline, width: 2.5)
                                      : null,
                                ),
                                child: accent == selected
                                    ? Icon(
                                        Icons.check,
                                        size: 18,
                                        color: brightness == Brightness.dark
                                            ? const Color(0xFF0F1117)
                                            : Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
