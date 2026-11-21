# Appearance: themes, dark mode and text size

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

Open **Appearance** from the palette button on the start screen or from
the chat menu.

- **Mode:** System (follows the device), Light or Dark.
- **Theme:** each theme has a light and a dark version, and its card shows
  a live preview of chat lines in the current mode.
  - **Classic:** mIRC navy, the default.
  - **Midnight:** deep blue, easy on the eyes at night.
  - **Solarized:** warm, low-glare colours.
  - **High contrast:** black and white with bright colours.
- **Text size:** Small, Normal, Large or Larger. It applies to the whole
  app, on top of the device's own text size setting.

Choices are saved on the device.

## Readable colours

Join/part lines were a fixed green (#009300), notices a fixed dark red
(#7F0000, about 1.9:1 on dark backgrounds) and actions a fixed purple, the
same in light and dark mode. Chat colours now come from the theme
(`ChatColors`), with separate light and dark versions. A test checks every
theme in both modes: event, notice, action, error, body text, timestamps
and all nickname colours must reach a contrast ratio of at least 4.5:1
(WCAG AA) against the background.

## Code

- `lib/core/theme/app_theme.dart`: `AppearanceMode`, `ThemePreset`,
  `ChatColors` (a `ThemeExtension`: event, notice, action, nickname
  palette, `nickColor()`), `AppTheme.build(preset, brightness)`,
  `contrastRatio()`.
- `lib/features/settings/application/appearance_controller.dart`:
  `Appearance` and `appearanceProvider` (saved under `appearance`).
- `lib/features/settings/presentation/appearance_screen.dart`: route
  `/appearance`.
- `lib/app/app.dart` applies theme, dark theme, mode and text scale.
- `chat_screen.dart` reads colours with `ChatColors.of(context)`.

## Tests

- `test/core/theme/app_theme_test.dart`: contrast for every theme and mode.
- `test/features/chat_flow_test.dart`: "appearance: pick dark mode, a
  theme and text size".
