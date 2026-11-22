# Roadmap

## v1 (MVP)
- [x] IRC core: TLS, CAP/SASL, registration, channels, messages, commands
- [x] Network picker and basic chat screen
- [x] Room browser: search and sort LIST results, one-tap join
- [x] Several networks at once; room browser and favorites across them
- [ ] mIRC colour and style rendering
- [x] Favorites and recent rooms; saved networks and nick (shared_preferences)
- [x] Passwords in flutter_secure_storage
- [x] Saved chat history on the device
- [x] Private rooms without commands: create, settings, invite/kick/ban,
      keep permanently (ChanServ)
- [x] Share temporary, end-to-end encrypted pictures in private chats
      (own Cloudflare Worker + R2)
- [~] App Store safety: block and report pictures done; content filter,
      blocked-people list and terms on first launch still to do
- [ ] Adaptive Cupertino touches on iOS/macOS
- [ ] App name and icon (working name "mIRC Mobile"; "mIRC" is a trademark)

## v2
- [ ] Bouncer support (soju/ZNC) and push notifications
- [ ] IRCv3 chathistory
- [ ] Android foreground service option
- [ ] Themes, including a classic mIRC skin
