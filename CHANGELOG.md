# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Phones: the back arrow in a chat shows how many other chats have new
  messages (coral `@` when one mentions you), so activity in a room shows
  while you're in a private chat.
- App Store preparation: an iOS privacy manifest (`PrivacyInfo.xcprivacy`),
  the signing team on the iOS app so `flutter build ipa` makes an App Store
  build, the store listing, privacy answers, age rating and reviewer notes
  (`docs/app-store.md`), and iPhone and iPad screenshots taken against a
  pretend demo network (`tool/demo_ircd.py`).

## [1.0.2] - 2026-11-24

### Fixed
- Undernet couldn't connect ("Connection timed out" on port 6697):
  Undernet has no encrypted port, so it now connects on 6667 without
  encryption, and the network list says so.

### Added
- Links in messages are tappable and open in your browser.
- A link to an image or video gets a preview under the message: tap to
  show the image (full screen with zoom) or play the video. Nothing loads
  until you tap, since loading lets the website see your IP address;
  Appearance → **Show images from links automatically** turns that off for
  images. Videos play in the app on iPhone, iPad, Android and Mac, and
  open in the browser on Windows and Linux.
- ircage.com/.well-known/security.txt says where to report security
  problems (support@ircage.com).

### Changed
- ircage.com no longer tells Mac users to click **Open Anyway**: the Mac
  download is signed and notarized by Apple since 1.0.1.

## [1.0.1] - 2026-11-24

### Added
- The Mac download is **signed with a Developer ID and notarized by Apple**
  when the repository has the signing secrets, so it opens without the
  "Apple could not verify" warning (`tool/macos_release.sh`, used by the
  release workflow). The release workflow can also be run by hand as a test
  that doesn't publish.
- **The ircage.com website** (`website/`, for Netlify): home page, privacy
  policy, terms of use, support and a 404 page, in the app's colours with
  light and dark mode. The privacy policy and support page are the URLs the
  App Store and Google Play ask for.
  A **Download** section links to the Mac, Windows and Linux apps on GitHub
  releases (always the latest), with how to open them the first time.

### Changed
- Photos, files and calls now go through **share.ircage.com** (the same
  server, on IRCage's own domain). The old workers.dev address keeps
  working for 1.0.0 and earlier.

## [1.0.0] - 2026-11-24

### Added
- **Downloads for Mac, Windows and Linux** from GitHub releases: pushing a
  version tag builds all three and publishes them (`release.yml`).
- **Update checks** in those downloads: on launch and daily, a banner says
  when a new version is out, with **Download** and **Later**; Settings →
  About → **Check for updates** turns it off. Store builds never check. See
  [docs/features/releases-and-updates.md](docs/features/releases-and-updates.md).
- **Windows and Linux** desktop apps, built on every pull request (CI
  artifacts `IRCage-windows-x64` and `IRCage-linux-x64`). They work like
  the Mac app: right-click menus at the pointer, a save dialog for received
  files, Ctrl shortcuts, calls, and **Take a photo** through the app's own
  camera screen. Passwords go to the Windows Credential Manager or the
  Linux keyring (libsecret); on Linux without a keyring they're kept only
  until the app quits. See the README for building and running them.
- **Direct file transfers (DCC)** with mIRC, HexChat, irssi and other apps
  (iOS, Android, macOS). Incoming offers show a card with **Accept** and
  **Decline** and a note that accepting shows the sender your IP; then
  progress and **Save**. **Send a file** now asks how: **Through the
  server** (encrypted, any network) or **Directly (DCC)**, which has no size
  limit but usually only works on the same Wi-Fi. Offers from ignored
  people are dropped. See [docs/features/dcc.md](docs/features/dcc.md).
- **Send a file** in private chats (iOS, Android, macOS), from the **+**
  menu: any file up to 25 MB, encrypted on your device and sent as a link
  that stops working after 1 or 4 hours. The other person gets a card with
  the name, size and **Save** (the share sheet on iPhone and Android, a save
  dialog on the Mac); people on other IRC apps get a download page. Needs
  the picture host redeployed. See
  [docs/features/file-sharing.md](docs/features/file-sharing.md).
- **Typing indicators** (iOS, Android, macOS): "bob is typing…" above the
  message box, and others see when you type, on servers with IRCv3 message
  tags (Ergo, soju and more). Turn yours off in Settings → Safety → **Show
  when I'm typing**.
- **Read position across your devices** (IRCv3 read markers, soju and
  Ergo): read a chat on one device and it's read on the others; unread
  counts and mentions follow. See
  [docs/features/typing-and-read-markers.md](docs/features/typing-and-read-markers.md).

### Fixed
- Timestamps sent to the server (missed-message requests, read markers)
  now have exactly milliseconds. soju refused the microseconds Dart adds,
  so asking for messages since your newest one could fail.
- **soju bouncers** (iOS, Android, macOS): add the bouncer once (Add your own
  network, with your soju username under Advanced options and your
  password as the server password) and each network on it opens as its own
  entry, logged in and bound to that network; networks added on the
  bouncer later open too. **Continue** reconnects the bouncer, which brings
  its networks back. soju's errors (FAIL replies) show in Server messages.
  See [docs/features/bouncers.md](docs/features/bouncers.md).
- **Missed and older messages** from servers and bouncers that keep them
  (IRCv3 chathistory: Ergo, soju and others), on iOS, Android and macOS.
  Joining a room or reconnecting brings back what was said while you were
  away, in time order and without repeats. Private chats that got messages
  while you were offline open with them, as unread. Scrolling to the top of
  a chat (or **Load earlier messages**) fetches older ones until there are
  none. See [docs/features/chathistory.md](docs/features/chathistory.md).
- `server/picture-host/check-reports.sh`: lists message and photo reports,
  newest first, with the last 24 hours marked NEW (asks for the admin
  token; `--json` for the raw list).
- **iPhone and Mac touches.** Android is unchanged.
  - **iPhone and iPad:** menus (long-press a chat or message, the **+**
    menu, the photo chooser) are iOS action sheets with **Cancel**, and
    long-press gives a haptic tap. Leave, Close and Report show in red.
  - **Mac:** right-click a chat in the sidebar, or a message, for a menu at
    the pointer. Right-clicking a message's text adds **Reply** and
    **Report message** to its Copy / Select All menu.
  - Confirmations (Delete saved history) are system alerts on iOS and Mac.
    Spinners are the native ones. Swiping to reply gives a haptic tick.
  See [docs/features/platform-feel.md](docs/features/platform-feel.md).
- The terms and Settings → About show **support@ircage.com** as the contact
  address.
- **App Store safety** (iOS, Android, macOS), for Apple's rules on apps
  with user-generated content:
  - **Terms of use** to agree to on first launch (and again when they
    change), readable later from Settings → About with a contact address.
  - **Hide offensive words:** slurs and strong swearing in messages,
    topics and previews show as `s***`. On by default.
  - **Hide adult rooms** in Discover, also switchable in Filters. On by
    default.
  - **Report message** on anyone else's message (long-press, or the flag
    on hover on a Mac): sent to the IRCage team for review and the sender
    ignored. The picture host now accepts message reports.
  See [docs/features/safety.md](docs/features/safety.md).
- **Take a photo** with the camera when sending a photo, on iOS, Android
  and now the Mac too: the photo button asks **Choose a photo** or **Take a
  photo**, and **Take a photo** is also in the + menu. The Mac gets its own
  camera screen with **Retake** and **Use photo**.
- **Add your own network** under the network list (iOS, Android, macOS):
  any IRC server or bouncer by address and port, with TLS on or off, an
  optional name and an optional server password (kept in the keychain).
  `host:port` and `ircs://` links fill in the port. Added networks show
  in the list with an Edit button (change or remove), and **Continue**
  reconnects them next launch. See
  [docs/features/custom-networks.md](docs/features/custom-networks.md).

### Changed
- The in-app terms now cover files and direct (DCC) transfers, and point to
  the privacy policy at ircage.com/privacy.
- Photos are called photos everywhere in the app again ("Photo options",
  "Report photo", "Photo reported", "View-once photo", "Send a photo"), and
  private chats have a visible **Send a photo** button next to **+** again.
- Tapping a room's name opens Room info instead of the Chat info sheet;
  Room settings are inside it. "Block" on a person is now **Ignore**
  (same list). The welcome's network heading wraps at large text sizes.
- The start screen's room, account, username and history options moved
  under **Advanced options**; Discover's size, sort and favorites chips
  moved into **Filters**.
- New navigation, Phase 3 of the redesign (iOS, Android, macOS). It
  replaces the ☰ drawer and the ⋮ menu: Browse, Message, Join, Create a
  room, Add a network, Appearance and each network's options are now in
  **Rooms** home and **You**; favorite, room settings and clear history are
  in **Chat info** (tap the chat's name). See
  [docs/features/navigation.md](docs/features/navigation.md).
- Replying on a phone is now swipe or long-press only (no faint ↩ on
  every line); screen readers get a Reply action. On a Mac the ↩ appears
  on hover.
- The app is now called **IRCage**: home screen and app switcher on iOS
  and Android, the Mac app (`IRCage.app`, menu bar and Privacy & Security
  lists), the window title, and the CTCP VERSION reply
  (`IRCage (Flutter) 0.1.0`). Bundle and application IDs are unchanged, so
  existing installs keep their settings and permissions.
- Settings saved with the old default theme move to the new Default theme
  once; other choices are kept.
- On phones the chat's top bar no longer cuts off the room or person's
  name. It keeps only **People** (rooms) or **Voice call** / **Video call**
  (private chats); there's no ⋮ menu. Tap the name for **Chat info**
  (favorite, people, room settings, clear history, leave or close, whois).
  **Browse**, **Message** and **Join** are at the top of the ☰ drawer, each
  network has a ⋮ for disconnect and close, and **Create a room** and
  **Appearance** are at the bottom. Tapping the name works on wider screens
  too. See [docs/features/pinned-panels.md](docs/features/pinned-panels.md).

### Added
- An IRCage app icon on iOS, Android (adaptive, with a legacy fallback)
  and macOS: a white chat bubble with the IRC `#` on an indigo gradient.
  It's drawn in code and regenerated with `tool/make_icons.sh`. See
  [docs/features/app-icon.md](docs/features/app-icon.md).
- Write formatted messages: **Format text** in the composer adds bold,
  italic, underline, strikethrough, 16 colours or plain to the selection
  (or what you type next), with Cmd/Ctrl+B/I/U on computers. The field
  shows the codes as small letters and a Preview line shows the result.
- mIRC colours and styles are shown in messages, server messages and Room
  info topics: bold, italic, underline, strikethrough, monospace, reverse,
  the 99 mIRC colours and hex colours. Colours are adjusted to stay
  readable on every theme; previews, search, copy and mentions use plain
  text. Turn it off in Appearance. See
  [docs/features/mirc-formatting.md](docs/features/mirc-formatting.md).
- Polish, Phase 5 of the redesign (iOS, Android, macOS). **Room info**: one
  page (a side panel on wide screens) with the topic, favorite, **Mute**,
  people, every room setting, clear history and leave. **Mute** a chat from
  Room info or by long-pressing (right-clicking) it: grey badge, out of the
  Mentions count. **Profile cards** with role and away status, Message,
  Call and Mention buttons, **Ignore** and **Report**. **People** grouped
  into Operators, Voiced, Members and Away (from IRCv3 away-notify).
  **Calls**: dark stage, draggable self-view, blurred controls, a richer
  incoming card, and **Back to chat** with a green in-call pill.
  **Settings** page (⌘, on a Mac) with history, calls, ignored people,
  muted chats and About. **Monospace** message font. New messages fade and
  slide in (off with Reduce Motion). An **accessibility audit** checks tap
  targets, labels, contrast and large text on every main screen. See
  [docs/features/room-info.md](docs/features/room-info.md),
  [docs/features/settings.md](docs/features/settings.md) and
  [docs/accessibility.md](docs/accessibility.md).
- Discover and welcome, Phase 4 of the redesign (iOS, Android, macOS).
  **Discover** shows rooms as cards (avatar, people, category, "Busy now",
  two-line topic, Join or Open) with category chips (Popular, Tech, Gaming,
  Music, Help, Social, guessed from each room's name and topic), "Search
  N rooms", a Filters sheet (favorites, size, sort), a preview sheet when
  you tap a card, and two columns on tablets and the Mac. The **welcome**
  screen says "Welcome to IRCage" and walks through three steps (nickname,
  network, first room), with the rest under **Advanced options**; Rooms
  home then offers **Find your first room**. See
  [docs/features/room-browser.md](docs/features/room-browser.md) and
  [docs/features/onboarding.md](docs/features/onboarding.md).
- Navigation by screen size, Phase 3 of the redesign (iOS, Android,
  macOS). **Phones:** bottom tabs (**Rooms**, **Discover**, **Mentions**
  with a badge, **You**) and chats full screen with a back arrow. **Rooms
  home:** search, favorite tiles, and every chat by latest activity with a
  network chip, time, preview and unread badge; swipe right to favorite,
  left to leave. **Mentions** lists every message that mentions you.
  **Tablets (600–899 pt):** a rail, the rooms list and the chat side by
  side. **iPad and Mac (900 pt+):** a sidebar with Home, Discover, Mentions
  and your chats in Favorites, Rooms and Private chats, the chat, and People.
  **Mac:** a menu bar (File, Edit, View, Room, Window), ⌘K to jump to any
  room or person, ⌘1–9 for the sidebar's chats, ⌘F to find in the chat
  (also a search button in every chat), Enter to send and Shift+Enter for a
  new line (Ctrl on other computers).
- New chat screen, Phase 2 of the redesign (iOS, Android, macOS). In
  Comfortable, room messages from one person within 5 minutes are grouped
  under one avatar, name, **OP** tag and time; mentions get a coral bar and
  tint with your nick highlighted; your own messages an accent bar. Private
  chats use bubbles. Runs of joins and leaves collapse into one line
  ("mara, kai and 3 others joined · sam left") that expands on tap. Every
  chat gets **Today / Yesterday** dividers, a coral **New messages**
  divider, and a **3 new** pill (coral with a mention) when you've scrolled
  up. The header shows the avatar and "142 people · Libera.Chat"; the
  topic is in Chat info. The new composer has a **+** menu (picture in
  private chats, common commands) and completion chips for `@nick`,
  `/command` and `#room`. Compact keeps `HH:MM <nick>` lines. See
  [docs/features/chat-screen.md](docs/features/chat-screen.md).
- IRCage design system, Phase 1 of the redesign (iOS, Android, macOS).
  A new **Default** theme (white or near-black with an Electric Indigo
  accent) is now the default, with an **accent colour** picker (Indigo,
  Blue, Teal, Green, Orange, Red, Pink, Purple) in **Appearance**.
  **Classic mIRC** keeps the navy look with square corners and switches to
  Compact. New **Density** setting: **Comfortable** shows room and person
  avatars (initials on the nick colour, gold ring for operators, accent
  ring for voice) in the chat and people lists; **Compact** keeps the
  classic icons. Unread counts use a new badge, coral `@ n` when you're
  mentioned. Design tokens, type scale, spacing, radii and motion live in
  `lib/core/theme/tokens.dart`; `NickAvatar`, `RoomAvatar` and
  `UnreadBadge` in `lib/core/ui/`. Every token pair is tested for
  contrast in every theme and accent. See
  [docs/features/design-system.md](docs/features/design-system.md).
- **Open Settings** buttons for blocked camera and microphone access: when a
  call can't use them, the call screen offers **Open Camera settings** /
  **Open Microphone settings** (Mac) or **Open Settings** (iPhone, Android),
  also under **More options → Camera and microphone**. See
  [docs/features/calls.md](docs/features/calls.md).
- More controls for rooms you run, in **Room settings**: edit the room's
  **Description** (topic), **Moderated** (only voiced people talk), **No
  messages from outside**, **Room size** (user limit), and a **Banned**
  list with **Unban**. The people menu adds **Give voice** / **Take voice**
  and **Remove operator**. See
  [docs/features/private-rooms.md](docs/features/private-rooms.md).
- Pinned side panels on wide screens (Mac, iPad, tablets): servers and
  chats stay open on the left and the people in the room on the right.
  Show or hide each from the top bar; the choice is remembered. Phones
  keep the slide-out panels. See
  [docs/features/pinned-panels.md](docs/features/pinned-panels.md).
- Voice and video calls (iOS, Android, macOS). In a private chat, tap
  **Voice call** or **Video call**. The other person gets a ringing banner
  with **Accept** / **Decline**; people on other IRC apps get a link that
  opens the call in their browser. Mute, camera on/off, switch camera,
  speaker and hang up. Calls are WebRTC, encrypted end to end, and the
  server keeps nothing after the call. **Hide my IP address on calls**
  (on by default) sends calls through Cloudflare's relay once it is set up.
  See [docs/features/calls.md](docs/features/calls.md).
- Photos are sent as `📷 Photo from <your nick>: <link>`. The message no
  longer says how long it lasts; opening an expired or already-viewed photo
  says **This photo has expired.**
- IRCage UI redesign plan and approved mockup (docs only, no app changes
  yet): design tokens, layouts for phone, iPad and Mac, screen specs and a
  five-phase rollout. See [docs/design/ui-redesign.md](docs/design/ui-redesign.md).
- Share temporary pictures in private chats (iOS, Android, macOS). Tap the
  picture button next to the message box, choose or take a photo, pick how
  long it lasts (1 hour or 4 hours). Every picture is view-once: it is
  deleted from the server as soon as it has been opened, and nothing is
  kept longer than 4 hours. The photo is shrunk to 2048 px, its location and other metadata
  are removed, and it is encrypted on the device before upload, so the
  server only stores scrambled bytes. The other person sees it in the chat;
  people on other IRC apps get a link that opens in a browser. Pictures
  from people you haven't written to stay hidden until tapped. Each
  picture has **Report picture** and **Block**; reports land on your own
  server for review as text only (no copy of the picture is kept). **Block / Unblock** is also in the people menu.
  The picture server is a small Cloudflare Worker with R2 storage in
  `server/picture-host`. See
  [docs/features/picture-sharing.md](docs/features/picture-sharing.md).
- Change your nickname without commands (iOS, Android, macOS): **Change
  nickname** in the chat menu, or tap your name on a network in the
  conversation list. Optionally change it on all networks; the new name is
  remembered. A taken name shows a clear message and keeps your current one.
  See [docs/features/change-nickname.md](docs/features/change-nickname.md).
- Appearance settings (iOS, Android, macOS): System/Light/Dark mode, four
  themes (Classic, Midnight, Solarized, High contrast) with live previews,
  and text size. Open from the palette button on the start screen or the
  chat menu. See [docs/features/appearance.md](docs/features/appearance.md).
- Reply to someone in a room (iOS, Android, macOS): a Reply button on each
  message (brighter on hover on Mac), swipe right or long-press on phones,
  and **Reply to … here** in the name menu. A "Replying to bob" bar shows
  above the message box, and sending addresses them as `bob: …` so they are
  notified. Tab completes nicknames. Lines that mention you are
  highlighted. See [docs/features/replies-and-mentions.md](docs/features/replies-and-mentions.md).
- Your own rooms without commands (iOS, Android, macOS). **Create a room**
  (chat menu, or the room browser) with Private, Hidden and Password
  switches. **Room settings** changes them, sets or removes the password and
  invites people. The people list adds **Invite to**, and for rooms you run
  **Make operator**, **Remove** and **Ban**. Invitations show a Join/Ignore
  banner. **Keep this room** registers the room with ChanServ (Libera.Chat,
  OFTC, Rizon, DALnet), with a guided nickname registration; Undernet and
  EFnet explain why they can't. Room setting changes show in words. New
  commands: `/mode`, `/invite`, `/kick`, `/ban`, `/op`, `/deop`, `/voice`,
  `/devoice`. See [docs/features/private-rooms.md](docs/features/private-rooms.md).
- Saved chat history (iOS, Android, macOS). Rooms and private chats keep
  their messages after a disconnect or an app restart, marked **Saved
  messages above**. **Continue** rejoins the rooms and reopens the private
  chats that were open. **Save chat history on this device** and **Delete
  saved history** are under **More options** on the start screen, and
  **Clear history** in the chat menu clears one conversation.
  See [docs/features/chat-history.md](docs/features/chat-history.md).
- Several networks at once (iOS, Android, macOS). Adding a network keeps the
  others connected. The conversation list is grouped by network and lists
  each network's favorite rooms for one-tap join. The room browser fetches
  and searches rooms from every connected network, labels each room with
  its network and can filter by network. **Continue** reopens every network
  that was open, and **Connect to all** opens every listed network.
  Disconnect, reconnect and close work per network, and reconnecting keeps
  that network's conversations.
  See [docs/features/multi-network.md](docs/features/multi-network.md).
- Private messages are easy to start (iOS, Android, macOS): tap a name in
  the people list, or a nickname in the chat, for **Send private message**,
  **Who is this? (whois)** and **Copy nickname**. A **New private message**
  button (envelope) in the chat top bar opens a chat with any nickname.
  Whois replies now show in the conversation you asked from instead of the
  server tab. See [docs/features/private-messages.md](docs/features/private-messages.md).

### Fixed
- Dropped connections (iOS, Android, macOS). When the network blips (for
  example after sleep or a Wi-Fi change), the app now notices straight away
  and reconnects, instead of logging "Broken pipe" / "Connection reset by
  peer" errors and waiting up to a minute for the ping timeout. Closing a
  dead connection no longer hangs. See
  [docs/features/irc-core.md](docs/features/irc-core.md).
- The chat menu was missing its **Appearance** item (it was only on the
  start screen).
- Join/part (green), notice (dark red) and action (purple) lines were hard
  to read on dark backgrounds. Chat colours now come from the theme, with
  light and dark versions that all meet a 4.5:1 contrast ratio (tested).
- Mentions now match whole words, so a short nickname like "al" is no
  longer alerted by words such as "also".
- Logging in again without retyping the password no longer deletes the
  saved password.
- The Join and New private message dialogs no longer use their text field
  after it was disposed while the dialog closes.
- EFnet (and other servers with self-signed, mismatched or expired TLS
  certificates) failed with `CERTIFICATE_VERIFY_FAILED`. The app now shows
  the certificate details and lets you **Trust and connect**. It remembers
  that exact certificate (SHA-256 fingerprint) per server, so a different
  certificate later is still refused. Verification is never turned off.
- DALnet disconnected new users as a "compromised host" (`[exp/dm]`). The
  app sent the nickname as the username and real name too, which DALnet's
  drone detector flags. It now sends `mobile` / `Mobile IRC user` by
  default, and both can be set under **More options** on the start screen.

### Added
- When a secure connection can't be opened at all (for example a server
  without TLS), the chat screen offers **Connect without encryption**
  (port 6667) with a clear warning.
- Favorites and recent rooms (iOS, Android, macOS). Star a room from the chat
  screen or the room browser; favorites are kept per network and rejoined
  automatically on connect ("Rejoin my favorite rooms"). The last 10 rooms
  you joined on each network appear as quick-join chips in the room browser,
  and a **Favorites** filter shows only starred rooms. Favorite rooms show a
  star in the conversation list.
  See [docs/features/favorites.md](docs/features/favorites.md).
- Saved connection settings: the nickname, last network and account name are
  remembered, and a **Continue on <network>** card reconnects in one tap.
  Account passwords are stored only in the iOS/macOS Keychain or Android
  encrypted storage (flutter_secure_storage), with a "Remember password"
  switch.
- Storage layer (`lib/core/storage/app_storage.dart`) wrapping
  shared_preferences and flutter_secure_storage behind interfaces, with
  in-memory versions for tests.
- Room browser (iOS, Android, macOS): tap the compass in the chat screen to
  see every room on the network. Search by name or topic, filter by size
  (any, 10+, 50+, 200+ people), sort by most people or A–Z, and join with
  one tap. The list is fetched once per connection and can be refreshed.
  See [docs/features/room-browser.md](docs/features/room-browser.md).
- A welcome line after connecting that points new users to the browser.
- `ServerInfoEvent`, so the app shows the network's real name (from
  ISUPPORT `NETWORK=`) instead of the server's host name.
- Flutter project for iOS, Android and macOS (`com.djc998.irc_client`),
  working display name "mIRC Mobile".
- IRC core in pure Dart (`lib/core/irc/`), identical on every platform:
  - Line parser and serializer for RFC 1459/2812 with IRCv3 message tags,
    tag escaping and `server-time`.
  - Byte-to-line decoder with UTF-8 and a Latin-1 fallback.
  - TLS socket transport (port 6697 by default) behind an `IrcTransport`
    interface, so a bouncer transport can be added later.
  - CAP LS 302 negotiation (multi-line LS, REQ/ACK/NAK, NEW/DEL) and SASL
    PLAIN with 400-byte chunking.
  - Registration with automatic nick-collision handling, PING/PONG,
    idle keepalive and ping timeout, reconnect with exponential backoff,
    and rejoining channels after a reconnect.
  - Channel and member tracking: JOIN, PART, KICK, QUIT, NICK, MODE
    (prefix modes), NAMES with `multi-prefix` and `userhost-in-names`,
    topics, and RPL_ISUPPORT (PREFIX, CHANTYPES, NETWORK, CASEMAPPING, ELIST).
  - Messages and notices, CTCP ACTION, VERSION/PING/TIME replies,
    STATUSMSG, `echo-message` support, and splitting long messages so every
    line fits in 512 bytes without breaking a character.
  - LIST with the ELIST `>n` user filter, or a local filter when the server
    lacks it.
  - Outgoing flood control (token bucket).
  - Slash commands: /join, /part, /msg, /query, /me, /notice, /nick, /topic,
    /whois, /list, /quote, /quit, and `//` to send a literal slash.
- Built-in network list: Libera.Chat, OFTC, EFnet, Undernet, DALnet, Rizon.
- First screens: network picker (nickname, rooms to join, optional account
  login) and a chat screen with a conversation list, coloured nicks, a
  nick list and a message box. Wide layouts (iPad, Mac) show the
  conversation list beside the chat.
- Android INTERNET permission and the macOS network-client entitlement.
- Unit and widget tests (92 in total), GitHub Actions CI (format, analyze,
  test).
