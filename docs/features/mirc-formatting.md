# mIRC colours and styles

Available on iOS, Android and macOS (shared Flutter code).

People on IRC add colours and styles to messages with control codes
(mIRC's Ctrl+K, Ctrl+B and so on). IRCade draws them.

## What the user sees

- **Styles:** **bold**, *italic*, underline, ~~strikethrough~~, monospace,
  and reverse (text and background swapped).
- **Colours:** the 16 classic mIRC colours, the extended colours 16–98, and
  hex colours, as text colour and background.
- **Always readable:** colours are adjusted just enough to reach 4.5:1 on
  what's behind them: your theme's background, the coral tint on a
  mention, a bubble in a private chat, or the sender's own background
  colour. Yellow on a white theme becomes a darker yellow, and white on
  white becomes readable. Every theme and mode works this way.
- **Where:** messages, actions and notices in rooms, private chats (bubbles)
  and Compact lines; server messages (MOTD art); the topic in Room info.
- **Plain where it should be:** previews in Rooms home, Mentions, search,
  **Copy message**, the reply bar and Discover's room cards show the text
  without codes. Mentions of your nick are found inside formatting too.
- **Turn it off:** Appearance → **Show mIRC colours and styles**. Messages
  then show as plain text.

Messages are kept with their codes (also in saved history), so turning the
setting back on shows them again. History saved before this change was
stored without codes.

## Codes

| Code | Meaning |
| --- | --- |
| `\x02` | bold on/off |
| `\x1D` | italic on/off |
| `\x1F` | underline on/off |
| `\x1E` | strikethrough on/off |
| `\x11` | monospace on/off |
| `\x16` | reverse on/off |
| `\x03F` / `\x03F,B` | colour (one or two digits, 0–98; 99 = default); bare `\x03` resets colours |
| `\x04RRGGBB` / `\x04RRGGBB,RRGGBB` | hex colour; bare `\x04` resets |
| `\x0F` | reset everything |

## Writing formatted messages

- **Format text** (the **A** button in the composer) opens bold, italic,
  underline, strikethrough, 16 colours and **Plain**. With text selected,
  it formats the selection; otherwise it formats what you type next
  (**Plain** goes back to normal).
- On a computer: **Cmd+B**, **Cmd+I** and **Cmd+U** on a Mac, **Ctrl** on
  others.
- In the field, each code shows as a small grey letter (**B**, **I**,
  **U**, **S**, **K04** for a colour, **O** for plain), like mIRC, so you
  can see and delete them. A **Preview** line above shows how the message
  will look.
- Colours are sent as two digits (`\x0304`) so a number typed right after
  isn't read as part of the colour.

## Code

- `lib/core/irc/mirc_compose.dart`: `MircStyle`, `applyStyle()`,
  `applyColor()`, `applyReset()`, `wrapSelection()`, `colorCode()`,
  `MircEditingController` (the markers).
- `lib/core/ui/composer.dart`: the Format text sheet, shortcuts and
  preview.

- `lib/core/irc/mirc_format.dart`: `parseMirc()` → `MircRun`s,
  `mircBaseColors`, `mircColor()`.
- `lib/core/ui/mirc_text.dart`: `mircSpans()` (styles, readable colours,
  nick highlight), `MircColours` (the setting, above the message list).
- `lib/core/irc/formatting.dart`: `stripFormatting()`; `mentions()` strips
  first.
- `lib/features/chat/application/chat_controller.dart`: messages and server
  notices keep their codes.
- `lib/features/chat/presentation/chat_screen.dart`: `_LineBody`,
  `_MessageTile`.
- `lib/features/settings/application/appearance_controller.dart`:
  `Appearance.ircColours`, `setIrcColours`.

## Tests

- `test/core/irc/mirc_compose_test.dart` and
  `test/core/ui/composer_format_test.dart`: wrapping, colours, reset,
  shortcuts, preview, markers, 48-pt targets.

- `test/core/irc/mirc_format_test.dart`: every code and edge case.
- `test/core/ui/mirc_text_test.dart`: readable colours in both modes,
  backgrounds, styles, off, nick highlight.
- `test/features/chat/mirc_colours_test.dart`: in the chat, previews stay
  plain, the setting, mentions inside formatting, Room info topic.
