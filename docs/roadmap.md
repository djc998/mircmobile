# Roadmap

## v1 (MVP)
- [x] IRC core: TLS, CAP/SASL, registration, channels, messages, commands
- [x] Network picker and basic chat screen
- [x] Modern chat screen: grouped messages, bubbles, dividers, composer chips
      (redesign Phase 2)
- [x] Navigation by screen size: phone tabs, tablet rail, iPad/Mac sidebar,
      Mac menu bar and shortcuts (redesign Phase 3)
- [x] Discover with room cards, categories and previews; three-step welcome
      (redesign Phase 4)
- [x] Room info, profile cards, grouped people, call restyle, Settings,
      motion and an accessibility audit (redesign Phase 5)
- [x] Room browser: search and sort LIST results, one-tap join
- [x] Several networks at once; room browser and favorites across them
- [x] mIRC colours and styles: shown readable on every theme, and written
      from the composer (format menu, Cmd/Ctrl+B/I/U)
- [x] Favorites and recent rooms; saved networks and nick (shared_preferences)
- [x] Passwords in flutter_secure_storage
- [x] Saved chat history on the device
- [x] Private rooms without commands: create, settings, invite/kick/ban,
      keep permanently (ChanServ)
- [x] Share temporary, end-to-end encrypted pictures in private chats
- [x] Send files (up to 25 MB) the same way, or directly with DCC
- [x] One-to-one voice and video calls, with a browser link for other IRC apps
- [ ] Calls: ring when the app is closed (PushKit/CallKit), group calls, screen sharing
      (own Cloudflare Worker + R2)
- [x] App Store safety: terms on first launch, a word filter and hidden
      adult rooms, report messages, photos and people, ignore people
- [x] Adaptive Cupertino touches on iOS/macOS: action sheets, alerts, Mac
      right-click menus, haptics, native spinners
- [x] App name and icon: **IRCage**, with its icon on iOS, Android (adaptive) and macOS
- [x] Windows and Linux desktop builds (CI artifacts), with the same icon,
      right-click menus, save dialogs, calls and camera as the Mac
- [x] Mac, Windows and Linux downloads from GitHub releases, with in-app
      update checks
- [ ] Signed downloads (Apple Developer ID + notarization, Windows code
      signing)
- [ ] Windows installer (MSIX) and Linux packages (Flatpak/AppImage), and
      notifications on those desktops

## v2
- [~] Bouncer support: soju's networks open on their own, with missed
      messages through chathistory; ZNC works as an ordinary server with a
      password. Still to do: push notifications (soju.im/webpush)
- [x] IRCv3 chathistory: missed messages on join and reconnect, missed
      private chats, older messages from the top of a chat
- [x] IRCv3 typing indicator and read markers (read position synced across
      your devices; IRC has no read receipts for others)
- [ ] Android foreground service option
- [x] Themes, including a classic mIRC skin (Classic mIRC theme + Compact density)
