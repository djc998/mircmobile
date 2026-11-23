# Accessibility

IRCage aims for WCAG AA on iOS, Android and macOS. Phase 5 of the
[UI redesign](design/ui-redesign.md) added an automated audit.

## What's checked automatically

`test/accessibility/a11y_test.dart` opens the welcome screen, a room, Rooms
home, Room info, a profile card, Settings and Appearance, in light and dark,
and checks Flutter's guidelines:

- **Tap targets:** at least 48×48 (Android) and 44×44 (iOS).
- **Labels:** every tappable thing has a screen-reader label.
- **Text contrast:** 4.5:1 for text (3:1 for large text).

Each screen is also opened at **twice the text size** and must not
overflow, and a room is checked for text contrast in Classic mIRC,
Midnight, Solarized and High contrast.

Other tests check every theme's colours (`test/core/theme`), component
contrast and sizes (`test/core/ui`), and Reduce Motion.

## What the audit found and fixed (Phase 5)

- The welcome's "Choose a network" heading and **Connect to all** didn't fit
  side by side at large text; the button now wraps under the heading.
- Room and person names on Room info, profile cards and room previews were
  selectable text, which screen readers treat as a small text field; they
  are plain headings now.
- The incoming call card's labels weren't part of its buttons; now the
  whole circle-and-label is one button.

## Built in

- Screen-reader labels on messages ("alice, 10:42, message, mentions
  you"), rows, badges, avatars, pills and dividers (headings).
- Custom actions instead of gestures: Reply on a message, Mute / Favorite /
  Leave on a chat row.
- Reduce Motion: new messages appear without fading, the jump to latest and
  panels don't animate.
- Text size: the app's setting on top of the device's, everywhere.

## Checking by hand

Turn on VoiceOver (iOS, macOS) or TalkBack (Android) and go through:
welcome → connect → Discover → join → send → reply → profile card → Room
info → Settings. Also try the largest text size and Reduce Motion.
