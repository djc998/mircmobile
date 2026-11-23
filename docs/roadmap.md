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
- [x] One-to-one voice and video calls, with a browser link for other IRC apps
- [ ] Calls: ring when the app is closed (PushKit/CallKit), group calls, screen sharing
      (own Cloudflare Worker + R2)
- [~] App Store safety: block and report pictures, ignore and report people,
      ignored-people list done; content filter and terms on first launch still to do
- [ ] Adaptive Cupertino touches on iOS/macOS
- [~] App name and icon: named **IRCade** (display name on iOS, Android and macOS); icon still to do

## v2
- [ ] Bouncer support (soju/ZNC) and push notifications
- [ ] IRCv3 chathistory
- [ ] IRCv3 typing indicator and read markers ("Seen")
- [ ] Android foreground service option
- [x] Themes, including a classic mIRC skin (Classic mIRC theme + Compact density)
