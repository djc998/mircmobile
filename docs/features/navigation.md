# Navigation

Available on iOS, Android and macOS (shared Flutter code). Phase 3 of the
[IRCade UI redesign](../design/ui-redesign.md); the open chat itself is in
[chat-screen.md](chat-screen.md).

The layout follows the window's width, so a Mac window or an iPad in split
view changes layout as it's resized.

## Phones (under 600 pt)

- **Bottom tabs:** **Rooms**, **Discover**, **Mentions** and **You**.
  Mentions has a coral badge with the number of chats that mention you; You
  shows your avatar.
- **A chat opens full screen** with a back arrow (**Back to rooms**). The
  Android back button and the iOS back swipe do the same. Joining a room,
  opening a private chat, or someone messaging you opens their chat.
  Leaving or closing the chat goes back to the tabs.
- In a chat, **People** and **Chat info** open as a slide-over and a sheet.

## Rooms home

- A large **Rooms** title with **Browse rooms**, **Join a room** and **New
  private message**.
- **Search rooms and people** filters everything below by name.
- Before you've joined anything: **Find your first room** with a
  **Discover rooms** button ([onboarding.md](onboarding.md)).
- **Favorites:** big tiles for your favorite rooms with their unread badge.
  A favorite you haven't joined yet is dimmed; tap it to join.
- **Active now:** every open room and private chat, newest activity first.
  Each row shows the avatar, name, network chip (with more than one
  network), ★ for favorites, time (`10:15`, `Yesterday`, `Nov 18`), a
  preview (`alice: does it run on the Mac?`, `You: on my way`) and the
  unread badge (coral `@ n` when it mentions you). The time is accent when
  there's something unread and coral with a mention.
- **Swipe a row right** to favorite or unfavorite a room; **swipe left** to
  leave the room or close the chat. Screen readers get the same as actions
  on the row.

## Mentions

Every message that mentions your nickname in an open chat, newest first,
with who said it, where and when. Tap one to open that chat.

## You

Your avatar and nickname and how many networks you're connected to, then
everything that isn't about one chat:

- **Browse**, **Message** and **Join** at the top.
- Each network: status dot, your nickname (tap to change it), a ⋮ to
  **Reconnect** / **Disconnect** / **Close** it, its **Server messages**,
  and favorite rooms you haven't joined yet (**Join**).
- **Create a room**, **Add a network**, **Appearance**.

## Small tablets and narrow windows (600–899 pt)

A **rail** on the left (Rooms, Discover, Mentions, You), the chosen list in
a 320-pt pane, and the open chat on the right. **Discover** fills the space
beside the rail; joining a room from it goes back to the list and opens the
room. People slides over from the right.

## iPad and Mac (900 pt and wider)

- **Sidebar** (264 pt): IRCade, a **Jump to a room or person** box (⌘K),
  **Home**, **Discover rooms** and **Mentions** (with its badge), then your
  chats in **Favorites**, **Rooms** and **Private chats**, each row with
  avatar, network chip and unread badge. You're at the bottom with your
  connection status; tap for You.
- **Home**, **Discover**, **Mentions** and **You** show in the main area;
  picking a chat shows the chat again.
- **People** is pinned on the right in rooms and can be hidden; the
  sidebar can be hidden too (☰ at the top left). Both are remembered
  ([pinned-panels.md](pinned-panels.md)).

## Mac menu bar and shortcuts

| Menu | Item | Shortcut |
| --- | --- | --- |
| IRCade | Settings… (Appearance) | ⌘, |
| File | New Private Message… | ⌘N |
| File | Join a Room… | ⌘J |
| File | Add a Network… | |
| File | Close Chat | ⌘W |
| Edit | Find in Chat… | ⌘F |
| View | Show or Hide Sidebar | ⌃⌘S |
| View | Show or Hide People | ⌥⌘P |
| View | Mentions | ⇧⌘M |
| View | Discover Rooms | ⇧⌘B |
| Room | Jump to a Room or Person… | ⌘K |
| Room | Go to Chat 1…9 | ⌘1…⌘9 |
| Window | Minimize, Zoom, Bring All to Front | |

The same shortcuts work with Ctrl on other computers. ⌘1…9 follow the
sidebar's order. **Find in Chat** (also the 🔍 button in a chat's header)
searches the open chat's messages and senders and lists matches newest
first. In the composer, **Enter** sends, **Shift+Enter** starts a new line
(each line goes out as its own message) and **Tab** completes nicknames.

## Not in this phase

- **Mute** on the swipe actions: needs per-room notification settings,
  which come with Room info in Phase 5.
- **Online dot** on private chats: IRC needs MONITOR or WATCH for this.
- People grouped into Operators, Voiced, Members and Away: Phase 5 with
  profile cards.

## Code

- `lib/features/chat/presentation/chat_shell.dart`: `ChatShell` (the
  `/chat` route; picks phone, rail or sidebar by width; opens chats when
  one is joined or picked), `HomeTab`, `RoomsHome`, `MentionsView`,
  `YouView`, `Sidebar`, `showQuickSwitcher`, `_MacMenus` (menu bar and
  shortcuts), `activityLabel()`.
- `lib/features/chat/application/conversations.dart`: `ConversationInfo`
  (last activity, preview), `activeConversations()`, `sidebarSections()`,
  `sidebarOrder()`, `mentionsIn()`, `unreadMentionChats()`,
  `shortNetworkName()`, `switcherMatches()`.
- `lib/core/ui/conversation_row.dart`: `ConversationRow`, `FavoriteTile`,
  `NetworkChip`.
- `lib/features/chat/presentation/chat_screen.dart`: `ChatScreen(layout:)`
  (back button on phones, sidebar toggle on wide screens), `NetworksPanel`
  and `NetworkActions` (in You).
- `lib/features/chat/presentation/find_in_chat.dart`: `showFindInChat`,
  `findInLines()`.
- `lib/features/discovery/presentation/room_browser_screen.dart`:
  `RoomBrowserScreen(onDone:)` for the Discover tab.

## Tests

- `test/features/chat/navigation_test.dart`: phone tabs, full-screen chats
  and back, unread after leaving, Mentions, search, swipe to favorite and
  leave, Discover, You; the tablet rail; the sidebar's sections, Home and
  You; Mac menu bar, ⌘K, ⌘2 and ⌘F; conversation helpers.
- `test/core/ui/conversation_row_test.dart`: rows, Compact icons, large
  text, target sizes, favorite tiles.
- `test/features/chat/pinned_panels_test.dart`: panels, phone header,
  Rooms home buttons, You.
- `test/goldens/components_golden_test.dart`: `conversation_row` and
  `favorite_tile` goldens (macOS only).
