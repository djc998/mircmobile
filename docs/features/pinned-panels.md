# Pinned side panels

On wide screens (900 points or wider: Mac windows, iPads, tablets) the chat
keeps two panels open at the sides:

- **Left: the sidebar.** Home, Discover and Mentions, your chats in
  Favorites, Rooms and Private chats, and you at the bottom
  ([navigation.md](navigation.md)). The button at the far left of the chat's
  top bar hides or shows it (**Hide servers and chats** / **Show servers
  and chats**, or ⌃⌘S on a Mac).
- **Right: people in the room.** The room's member list, operators first.
  The **People** button in the top bar hides or shows it (**Hide people** /
  **Show people**, or ⌥⌘P). Clicking a name opens the same menu as before
  (private message, reply, whois, invite, …).

Both panels are pinned by default, and the choice is remembered between
launches (`pinChatsPanel` and `pinPeoplePanel` in local settings).

Narrower screens don't pin them: from 600 to 899 points a rail and a rooms
list sit beside the chat, and on phones the chat opens full screen from
Rooms home. People slides over from the right on both.

## The chat's top bar

Only what's about this chat, so the room or person's name isn't cut off:

- **Left:** a back arrow on phones (**Back to rooms**), the sidebar toggle
  on wide screens, nothing beside the rail.
- **Right:** **Voice call** and **Video call** in a private chat, **Search
  this chat**, and **People** in a room. There is no ⋮ menu.
- **Tap the name (Chat info):** a sheet with the full name and topic and
  what you can do here:
  - Room: **Add to / Remove from favorites**, **People (n)** (phones),
    **Room settings**, **Clear history**, **Leave room**.
  - Private chat: **Who is this? (whois)**, **Clear history**, **Close
    chat**.
  - Server messages: **Change nickname**, **Disconnect** / **Reconnect**,
    **Close** the network.

Browse, Message, Join, Create a room, Add a network, Appearance and each
network's options are in Rooms home and **You**.

## Code

- `lib/features/chat/application/panel_prefs.dart`: `PanelPrefs` and
  `panelPrefsProvider` (pinned or not, saved), `pinnedPanelsMinWidth`,
  `compactTitleBarMaxWidth`.
- `lib/features/chat/presentation/chat_shell.dart`: the sidebar and the
  layouts by width.
- `lib/features/chat/presentation/chat_screen.dart`: `ChatScreen(layout:)`
  (top-left button, People pinned or sliding over), `_showChatInfo`.

## Tests

`test/features/chat/pinned_panels_test.dart`: both panels pinned on a wide
screen, hiding and showing them, remembering the choice, People sliding
over on a phone, the phone top bar, Chat info, Rooms home and You.
