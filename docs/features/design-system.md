# Design system

Available on iOS, Android and macOS (shared Flutter code). Phase 1 of the
[IRCade UI redesign](../design/ui-redesign.md).

## What the user sees

- **Default theme** (new default): clean white or near-black backgrounds
  with an Electric Indigo accent. Pick another **accent colour** in
  **Appearance**: Indigo, Blue, Teal, Green, Orange, Red, Pink or Purple.
- **Classic mIRC** theme: mIRC navy, square corners on cards, buttons,
  avatars and badges. Picking it also switches to **Compact**.
- **Density** in **Appearance**:
  - **Comfortable** (default): rooms in the chat list show a room avatar
    (first letter on a soft accent square), private chats and the people
    list show a person avatar (initials on their nick colour). Operators
    have a gold ring, voiced people an accent ring.
  - **Compact**: no avatars, the icons and lines IRC veterans know.
- **Unread badges**: accent pill with the count (99+ past 99), or a coral
  `@ n` when one of the messages mentions you.

Phase 4 adds `RoomCard`, `EmptyState` and `SkeletonList` for Discover
([room-browser.md](room-browser.md)). Phase 2 adds the chat components: grouped messages, bubbles, dividers,
the jump pill and the composer. See [chat-screen.md](chat-screen.md).

## Tokens

`lib/core/theme/tokens.dart`. Widgets read colours with
`AppTokens.of(context)`; every theme provides them.

| Token | Light | Dark | Used for |
| --- | --- | --- | --- |
| `surface` | `#FFFFFF` | `#0F1117` | Chat background |
| `surfaceRaised` | `#F5F6FA` | `#171A23` | Side panels, composer, cards |
| `surfaceOverlay` | `#ECEEF5` | `#232838` | Sheets, menus, other-person bubbles |
| `line` | `#E3E6EE` | `#262B37` | Dividers, borders |
| `textPrimary` | `#14161C` | `#E8EAF2` | Messages |
| `textMuted` | `#5F6474` | `#8E94A6` | Timestamps, events, labels |
| `accent` | `#5B5BF0` | `#8B8BFF` | Buttons, links, unread badge |
| `onAccent` | `#FFFFFF` | `#0F1117` | Text on accent |
| `accentSoft` | accent 12% | accent 16% | Selected row, room avatars |
| `onAccentSoft` | derived | derived | Text on `accentSoft` |
| `mention` / `onMention` | `#C8372A` / white | `#FF8A7D` / `#0F1117` | Mention badge |
| `mentionBar` | `#FF6B5B`, nudged to 3:1 | `#FF8A7D` | Mention bar, unread divider |
| `mentionSoft` | `#FF6B5B` 10% | `#FF8A7D` 12% | Mentioned row |
| `success` | `#1FA971` | `#3DD68C` | Online dot, call accept |
| `op` / `opText` | `#A86A00` / derived | `#F5C15C` | Operator ring / badge text |

**Where values differ from the spec, and why.** Every text pair must read
at 4.5:1 and every non-text mark (dot, ring, bar) at 3:1. Four spec values
fall just short, so a derived colour is used where they're drawn:

- Indigo text on `accentSoft` is 4.25:1 → `onAccentSoft` is the accent
  darkened (light) or lightened (dark) just enough.
- `op` gold on white is 4.44:1 as text → `opText`; the ring keeps `op`.
- The light mention bar `#FF6B5B` is 2.8:1 on white → slightly darker.
- `success` is 3.0:1 on Default's white (unchanged) but below 3:1 on the
  tinted backgrounds of Classic mIRC, Midnight and Solarized → nudged
  there.

`AppTokens.readableOn(color, background, brightness, ratio:)` does the
nudging; it returns the colour unchanged when it already passes.

Other themes (Classic mIRC, Midnight, Solarized, High contrast) get their
tokens from their colour scheme (`AppTokens.derive`).

Also in `tokens.dart`:

- `AccentColor`: the 8 accents, light and dark.
- `Insets`: 4, 8, 12, 16, 24, 32.
- `Radii`: chip 8, card 12, composer 18, bubble 20 (tail 6). Read through
  `tokens.radius(r)` so Classic mIRC squares them (2).
- `TypeScale`: Title 22/28 semibold, Heading 17/22 semibold, Body 15/21,
  Meta 12/16, Code 14/20 mono. Applied to the theme's `titleLarge`,
  `titleMedium`, `bodyLarge`, `bodyMedium`, `bodySmall`; they scale with
  the text-size setting and the device's text size.
- `Motion`: 150/200/250 ms ease-out; `Motion.of(context)` is zero with
  reduce motion on.

## Components

`lib/core/ui/`.

- `NickAvatar(nick:, size: 36, role:, away:)`: up to two initials
  (`dark_star` → DS, `DarkStar` → DS, `alice` → A) on the nick colour at
  12% (light) / 20% (dark), text in the nick colour adjusted to 4.5:1.
  `NickRole.op` gold ring, `NickRole.voiced` accent ring, `away` 50%
  opacity. Screen readers hear "alice, operator, away".
- `RoomAvatar(name:, size: 36)`: first letter or digit after `#`
  (`##chat` → C) on `accentSoft`, radius size/3 (12 at 36), 2 in Classic.
  Screen readers hear "Room #linux".
- `UnreadBadge(count:, mention:)`: nothing at 0; accent pill, or coral
  `@ n` for mentions; "3 unread messages, mentions you".

Avatars keep their size at large text sizes (the name is in the semantics
label); the badge grows with the text.

## Where they're used in Phase 1

- Conversation lists (`ConversationRow` in `core/ui/conversation_row.dart`): `RoomAvatar` for rooms,
  `NickAvatar` for private chats (Comfortable), `UnreadBadge` for unread
  counts (both densities). Favorites keep a star.
- People list (`_NickList`): `NickAvatar` with role rings (Comfortable).

## Tests

- `test/core/theme/tokens_test.dart`: Default tokens match the spec; every
  token pair for every accent and every theme in light and dark (4.5:1
  text, 3:1 marks); nick avatar text for every nick colour; Classic square
  corners; type scale; `readableOn`; reduced motion.
- `test/core/ui/components_test.dart`: initials, room letters, colours,
  rings, away, semantics labels, badge text and colours, largest text size.
- `test/goldens/components_golden_test.dart`: light and dark goldens for
  each component in Default and Classic mIRC (`test/goldens/*.png`). They
  run on macOS only: Linux draws circle edges and scaled text 2-3%
  differently, so CI (Linux) skips them and relies on the widget tests
  above. The comparator in `test/goldens/flutter_test_config.dart` allows
  0.5%. Update on a Mac with `flutter test test/goldens --update-goldens`.
- `test/features/settings/appearance_test.dart`: saved settings and their
  move from the old default, accent and density pick and persistence,
  accent disabled for other themes, avatars in Comfortable but not Compact.
