# IRCade UI redesign

Approved by Dennis on 2026-11-22. Plan doc:
https://claude.ai/artifact/5B3RkEVtxrvEWr5XrJfPbd. Clickable mockup:
https://claude.ai/artifact/SgvnSzqUnBcY89aH4mtT2m (source in
[`mockup/`](mockup/)).

IRCade keeps IRC's speed (fast text, nick colors, rooms found in seconds) with
the look of a modern messenger. Every phase ships on **iOS, Android and macOS
together** and updates `docs/features/` and `CHANGELOG.md`.

## Decisions

| Question | Decision |
| --- | --- |
| App name | **IRCade** (display name, welcome screen, About) |
| Accent | Electric Indigo `#5B5BF0` light / `#8B8BFF` dark |
| Default message style | **Comfortable**: avatars, grouped messages |
| Private chats | **Bubbles**: own on the right in accent, others left on `surfaceOverlay` |
| Classic look | Kept as a theme + "Compact" density for IRC veterans |

## Design tokens

Put these in `lib/core/theme/tokens.dart` and feed `AppTheme` from them. Keep
the existing `ChatColors` nick palettes and the WCAG contrast test; extend the
test to every token pair below.

| Token | Light | Dark | Used for |
| --- | --- | --- | --- |
| `surface` | `#FFFFFF` | `#0F1117` | Chat background |
| `surfaceRaised` | `#F5F6FA` | `#171A23` | Side panels, composer, cards |
| `surfaceOverlay` | `#ECEEF5` | `#232838` | Sheets, menus, other-person bubbles, icon buttons |
| `line` | `#E3E6EE` | `#262B37` | Dividers, borders |
| `textPrimary` | `#14161C` | `#E8EAF2` | Messages |
| `textMuted` | `#5F6474` | `#8E94A6` | Timestamps, events, labels |
| `accent` | `#5B5BF0` | `#8B8BFF` | Buttons, links, unread badge, own bubbles, active tab |
| `onAccent` | `#FFFFFF` | `#0F1117` | Text on accent |
| `accentSoft` | accent at 12% | accent at 16% | Selected row, room avatars |
| `mention` | `#C8372A` (badge) / `#FF6B5B` (bar) | `#FF8A7D` | Mention badge, bar, unread divider |
| `mentionSoft` | `#FF6B5B` at 10% | `#FF8A7D` at 12% | Mentioned row background |
| `success` | `#1FA971` | `#3DD68C` | Online dot, call accept |
| `op` | `#A86A00` | `#F5C15C` | Operator badge and ring |

Themes: **Default (Indigo)** (new default), **Classic mIRC** (navy seed,
square corners, line mode), **Midnight**, **Solarized**, **High contrast**,
plus an accent picker (8 swatches that pass 4.5:1).

Type: system fonts (SF Pro / Roboto), optional JetBrains Mono for line mode.
Title 22/28 semibold, Heading 17/22 semibold, Body 15/21, Meta 12/16, Code 14/20.
All scale with the existing text-size setting and OS text size.

Spacing: 4-pt grid (4, 8, 12, 16, 24, 32). Radii: 8 chips/inputs, 12 cards and
room avatars, 18 composer, 20 bubbles (6 on the tail corner), circles for nick
avatars. Densities: Comfortable (default, 36-pt avatars) and Compact (no
avatars, today's `HH:MM <nick> text`).

Avatars: IRC has no pictures, so `NickAvatar` = up to two initials on a circle
filled with the nick color at 12% (light) / 20% (dark), text in the nick
color; ring gold for ops, accent for voiced; away = 50% opacity.
`RoomAvatar` = first letter after `#` on an accent-soft rounded square.

Motion: 150 to 250 ms ease-out; new messages fade-slide up 8 pt; all off with
reduce motion.

## Layout by width

Extends `pinnedPanelsMinWidth` (900) from `panel_prefs.dart`.

- **Under 600 pt (phones):** bottom tab bar: **Rooms**, **Discover**,
  **Mentions**, **You** (profile and settings). A room opens full screen;
  People and Room info open as sheets. Replaces the drawer and the crowded top bar.
- **600 to 899 pt:** icon rail + rooms list + chat; People as a slide-over.
- **900 pt and wider (iPad, Mac):** three columns: sidebar (Home, Discover,
  Mentions, then Favorites, Rooms, Private chats, each row with avatar,
  network chip and unread badge), chat, People (hideable, remembered).
- **Mac:** menu bar (File, Edit, View, Room, Window), Cmd+K quick switcher,
  Cmd+1..9 rooms, Cmd+F search, Enter sends, Shift+Enter new line, Tab
  completes nicks.

## Screens

See the mockup files for exact values.

1. **Rooms home** (`Rooms.html`): large "Rooms" title, search field,
   Favorites row of 60-pt tiles with badges, "Active now" list sorted by last
   activity (avatar, name, network chip, time, last-message preview, badge;
   coral `@ n` badge when it holds a mention). Swipe: Mute, Favorite, Leave.
2. **Room chat** (`Chat.html`): header = back, room avatar, name, "142 people
   · Libera.Chat", Search, People/Info. Messages from one nick within 5
   minutes group under one avatar + colored name + OP badge + time. Joins,
   parts and quits collapse to one centered muted line ("mara, kai and 3
   others joined"). Day divider and coral "New messages" divider. Mentions:
   coral 3-pt left bar + tinted row, own nick highlighted. Own messages: accent
   left bar. Floating "3 new" jump pill. Typing line above the composer.
   Keep swipe-to-reply, long-press menu, Mac hover reply.
3. **Private chat** (`Private.html`): bubbles, header shows online status
   and Voice/Video call buttons, call history shown as a centered card,
   photo bubbles keep view-once behavior, "Seen" under the last own bubble
   only if the server supports read markers.
4. **Composer** (all chats): rounded 18-pt field on `surfaceRaised` with +
   (photo, camera, commands), text field, emoji, Send in accent. Completion
   chips above it for `@nick`, `/command`, `#room`.
5. **Discover** (`Discover.html`): network chips, search ("Search N rooms"),
   category chips (Popular, Tech, Gaming, Music, Help, Social; inferred from
   name and topic), room cards (avatar, name, people count, category, "Busy
   now", 2-line topic with mIRC codes stripped, **Join** becomes **Open**).
   Tablet/Mac: 2-column card grid. Card tap opens a preview sheet.
6. **People panel**: sections Operators, Voiced, Members, Away (dimmed),
   avatar with role ring, tap opens a profile card (Message, Call, Mention,
   Ignore, Report; Kick/Ban for ops).
7. **Room info** (new): one page replacing stacked sheets: avatar, topic,
   notifications, favorite, ops settings (+i, +k, +s, topic lock), invite,
   ban list, Keep my room, Leave.
8. **Calls**: dark stage always, draggable 12-pt self-view, blurred control
   pill, red Hang up, rich incoming call card, green in-call pill in the
   header while chatting.
9. **Welcome**: three steps (nickname, network cards, first room in Discover);
   advanced options behind a disclosure. Line: "Chat rooms, the way they used
   to be. Only better."
10. **Settings**: native grouped lists; Appearance gets theme cards with a
    live chat preview, accent swatches, density, line mode, font, text size.

## Components (`lib/core/ui/`)

Each gets a widget test and light + dark golden tests.

| Component | Replaces |
| --- | --- |
| `NickAvatar`, `RoomAvatar`, `UnreadBadge` | new |
| `ConversationRow` | `ListTile` in `_BufferList` |
| `MessageGroup` / `MessageLine` (Comfortable + Compact) | `_MessageTile` |
| `MessageBubble` | new, private chats |
| `SystemEventLine` (collapsing) | event `TextSpan` |
| `DayDivider`, `UnreadDivider`, `JumpPill`, `MentionPill` | new |
| `Composer` | `_InputBar` |
| `RoomCard` | room browser `ListTile` |
| `ProfileCard` | nick bottom sheet |
| `AppSheet`, `AppDialog`, `EmptyState`, `SkeletonList` | ad hoc sheets, plain text |

## Phases (one PR each)

1. **Foundation**: tokens, Default (Indigo) + Classic mIRC themes, accent
   picker, density setting, `NickAvatar`, `RoomAvatar`, `UnreadBadge`,
   rename display name to IRCade. Docs: `docs/features/design-system.md`,
   update `appearance.md`.
2. **Chat**: grouped messages, bubbles in private chats, collapsed events,
   dividers, pills, new composer, simpler header. Docs: `chat-screen.md`.
3. **Navigation**: Rooms home, phone tabs, rail, three-column workspace, Mac
   menu and shortcuts. Docs: `navigation.md`, update `pinned-panels.md`.
4. **Discover and welcome**: room cards, categories, preview sheet, 3-step
   welcome. Docs: update `room-browser.md`, add `onboarding.md`.
5. **Polish**: Room info, profile cards, call restyle, settings, motion,
   accessibility audit.

Accessibility in every phase: 4.5:1 contrast, 44-pt iOS / 48-dp Android
targets, screen-reader labels ("alice, 10:42, message"), works at the largest
text size, reduced motion respected.
