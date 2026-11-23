# Platform feel

The app is one Flutter codebase with a Material design system, but menus,
alerts and gestures follow each platform's habits.

## What the user sees

| | iPhone / iPad | Mac | Android |
|---|---|---|---|
| Menus (a chat, a message, **+**, the photo chooser) | iOS action sheet with **Cancel**; Leave, Close and Report in red | Right-click: a menu at the pointer | Material bottom sheet |
| A message's text | — | Right-click the text: Copy / Select All plus **Reply** and **Report message** | — |
| Confirmations (Delete saved history) | iOS alert | Mac-style alert | Material dialog |
| Spinners | iOS activity indicator | Mac activity indicator | Material |
| Haptics | Long-press menus; swipe to reply | — | Swipe to reply |

Already native before this: switches (`SwitchListTile.adaptive`), page
transitions and back-swipe on iOS, the Mac menu bar and shortcuts, and
pull to refresh in Discover (`RefreshIndicator.adaptive`).

Forms (create a room, report with reasons, add a network) stay Material
dialogs and sheets on every platform: they need more than an alert holds.

## Code

- `lib/core/ui/adaptive.dart`: `isApple`, `MenuAction`, `showActionMenu`
  (iOS action sheet, Mac context menu when given a pointer `position`,
  Material sheet otherwise) and `confirmAction` (`AlertDialog.adaptive`).
- Used by `showConversationMenu` (`chat_shell.dart`), `_showLineActions`
  and the selectable text's `_lineContextMenu` (`chat_screen.dart`), the
  composer's **+** menu, `sendPicture`, and Delete saved history.
- `cupertino_ui` is a direct dependency for the iOS widgets.

## Tests

`test/core/ui/adaptive_test.dart` (menus and confirmations on iOS, macOS
and Android) and `test/features/chat/apple_menus_test.dart` (right-click a
message on a Mac, long-press one on an iPhone).
