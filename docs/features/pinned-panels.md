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

## Phone layout

On phones held upright (narrower than 600 points, `compactTitleBarMaxWidth`)
each action lives where it belongs, so the room or person's name isn't cut
off:

- **Top bar:** ☰, the chat's name, and only the buttons for this chat:
  **People** in a room, **Voice call** and **Video call** in a private chat.
  There is no ⋮ menu.
- **Tap the name (Chat info):** a sheet with the full name and topic and
  what you can do here:
  - Room: **Add to / Remove from favorites**, **People (n)**, **Room
    settings**, **Clear history**, **Leave room**.
  - Private chat: **Who is this? (whois)**, **Clear history**, **Close
    chat**.
  - Server messages: **Change nickname**, **Disconnect** / **Reconnect**,
    **Close** the network.
- **☰ drawer:** **Browse**, **Message** (new private message) and **Join**
  at the top; a ⋮ on each network for **Disconnect** / **Reconnect** and
  **Close**; **Create a room**, **Add a network** and **Appearance** at the
  bottom.

Wider screens keep the top-bar buttons and ⋮ menu; tapping the name opens
the same Chat info sheet there too.

## Code

- `lib/features/chat/application/panel_prefs.dart`: `PanelPrefs` and
  `panelPrefsProvider` (pinned or not, saved), `pinnedPanelsMinWidth`,
  `compactTitleBarMaxWidth`.
- `chat_screen.dart`: `_showChatInfo` (the sheet from the name) and
  `_ListActions` (the phone drawer's extra actions).
- `lib/features/chat/presentation/chat_screen.dart`: shows the panels in
  the body row on wide screens and as drawers otherwise.

## Tests

`test/features/chat/pinned_panels_test.dart`: both panels pinned on a wide
screen, hiding and showing them, remembering the choice, and drawers on a
phone-sized screen.
