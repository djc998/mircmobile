# Appearance: themes, accent, density, dark mode and text size

Available on iOS, Android and macOS (shared Flutter code).

## What the user sees

Open **Appearance** from the palette button on the start screen, from
**You** ([navigation.md](navigation.md)), or with ⌘, on a Mac.

- **Mode:** System (follows the device), Light or Dark.
- **Theme:** each theme has a light and a dark version, and its card shows
  a live preview of chat lines in the current mode (with avatars in
  Comfortable).
  - **Default** (new default): clean and modern, with the accent colour
    you pick.
  - **Classic mIRC:** mIRC navy, square corners, compact lines. Picking it
    also switches density to Compact.
  - **Midnight:** deep blue, easy on the eyes at night.
  - **Solarized:** warm, low-glare colours.
  - **High contrast:** black and white with bright colours.
- **Accent colour:** Indigo (default), Blue, Teal, Green, Orange, Red, Pink
  or Purple. Applies to the Default theme; the other themes keep their own
  colours and the swatches are dimmed with a note saying so. Each swatch is
  a 48-pt target and screen readers hear "Teal accent, selected".
- **Density:** **Comfortable** (avatars next to rooms and people, grouped
  messages in rooms, bubbles in private chats) or **Compact** (no avatars,
  classic `HH:MM <nick>` lines). See [chat-screen.md](chat-screen.md).
- **Message font:** System or **Monospace** (even-width letters, for code
  and ASCII art; Menlo on Apple devices, the system monospace elsewhere).
- **Show mIRC colours and styles** (on by default): colours, bold,
  italics and underline people add to messages, kept readable on your
  theme ([mirc-formatting.md](mirc-formatting.md)).
- **Show images from links automatically** (off by default): images people
  link to load without a tap. Loading one lets that website see your IP
  address ([links.md](links.md)).
- **Text size:** Small, Normal, Large or Larger. It applies to the whole
  app, on top of the device's own text size setting.

Choices are saved on the device. Settings saved before the redesign that
had the old default (Classic) move to the new Default theme once; other
themes, mode and text size are kept.

## Readable colours

Chat colours come from the theme (`ChatColors`), with separate light and
dark versions, and every theme also provides the design tokens
(`AppTokens`). Tests check every theme in both modes: event, notice,
action, error, body text, timestamps and all nickname colours reach at
least 4.5:1 (WCAG AA) on the background, and so does every token text
pair, for every accent. Dots, rings and bars reach 3:1.

## Code

- `lib/core/theme/tokens.dart`: `AppTokens`, `AccentColor`, spacing,
  radii, type scale, motion. See [design-system.md](design-system.md).
- `lib/core/theme/app_theme.dart`: `AppearanceMode`, `ThemePreset`,
  `ChatColors`, `AppTheme.build(preset, brightness, accent:)`,
  `contrastRatio()`.
- `lib/features/settings/application/appearance_controller.dart`:
  `Appearance` (mode, preset, accent, density, text scale, `version`),
  `ChatDensity`, `appearanceProvider` (saved under `appearance`).
- `lib/features/settings/presentation/appearance_screen.dart`: route
  `/appearance`, theme cards, accent picker, density.
- `lib/app/app.dart` applies theme, accent, dark theme, mode and text
  scale.
- `chat_screen.dart` reads colours with `ChatColors.of(context)` and
  density from `appearanceProvider`.

## Tests

- `test/core/theme/app_theme_test.dart`: chat colour contrast for every
  theme and mode.
- `test/core/theme/tokens_test.dart`: token contrast for every theme and
  accent.
- `test/features/settings/appearance_test.dart`: accent, density, saving
  and the move from the old default.
- `test/features/chat_flow_test.dart`: "appearance: pick dark mode, a
  theme and text size".
