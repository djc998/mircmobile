# Pinned side panels

On wide screens (900 points or wider: Mac windows, iPads, tablets) the chat
screen can keep two panels open at the sides:

- **Left: servers and chats.** Every network with its rooms and private
  chats. The button at the far left of the top bar shows or hides it
  (**Hide servers and chats** / **Show servers and chats**).
- **Right: people in the room.** The room's member list, operators first.
  The **People** button in the top bar shows or hides it (**Hide people** /
  **Show people**). Clicking a name opens the same menu as before
  (private message, reply, whois, invite, …).

Both panels are pinned by default, and the choice is remembered between
launches (`pinChatsPanel` and `pinPeoplePanel` in local settings).

On phones and narrow windows the panels slide out instead, as before: the
menu button for servers and chats, **People** for the member list.

## Code

- `lib/features/chat/application/panel_prefs.dart`: `PanelPrefs` and
  `panelPrefsProvider` (pinned or not, saved), `pinnedPanelsMinWidth`.
- `lib/features/chat/presentation/chat_screen.dart`: shows the panels in
  the body row on wide screens and as drawers otherwise.

## Tests

`test/features/chat/pinned_panels_test.dart`: both panels pinned on a wide
screen, hiding and showing them, remembering the choice, and drawers on a
phone-sized screen.
