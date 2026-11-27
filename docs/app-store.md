# Submitting to the App Store

Everything App Store Connect asks for IRCage on iPhone and iPad, ready to
paste, and the steps to get a build there. Android (Google Play) is in
[google-play.md](google-play.md).

## Before the first submission

- [ ] `support@ircage.com` receives mail, and someone reads
      `/admin/reports` on the picture host daily: the terms promise 24 hours
      ([safety.md](features/safety.md)).
- [ ] ircage.com/privacy, /terms and /support are live (they are, from
      `website/`).
- [ ] An **Apple Distribution** certificate. Xcode makes one the first time
      you upload (Settings → Accounts → your team → Manage Certificates →
      **+** → Apple Distribution), or `flutter build ipa` makes it if Xcode
      is signed in to the team. The Developer ID certificate for the Mac
      downloads can't be used for the App Store.
- [ ] The app record in App Store Connect: **Apps → + → New App**, iOS,
      name **IRCage**, primary language English (U.S.), bundle ID
      `com.djc998.ircClient`, SKU `ircage-ios`, full access.

## Making a build and uploading it

1. Raise the build number in `pubspec.yaml` (the number after `+`); every
   upload needs a new one, even for the same version.
2. Build:

   ```sh
   flutter build ipa --release
   ```

   This archives with the team in the Xcode project (W4QQ2637KN) and
   writes `build/ios/ipa/IRCage.ipa`.
3. Upload: open `build/ios/archive/Runner.xcarchive` in Xcode (Organizer →
   **Distribute App → App Store Connect → Upload**), or drag the .ipa into
   Apple's **Transporter** app, or:

   ```sh
   xcrun altool --upload-app -t ios -f build/ios/ipa/IRCage.ipa \
     --apiKey KEY_ID --apiIssuer ISSUER_ID
   ```

   (`altool` looks for `AuthKey_KEY_ID.p8` in `~/.appstoreconnect/private_keys/`.
   It's the same API key the Mac release uses.)
4. After 5–15 minutes the build shows in **TestFlight**. Add yourself as
   an internal tester to try it before sending it for review.

## Export compliance

Each build asks about encryption. IRCage uses TLS (to IRC networks and
our server) and encrypts photos and files itself with AES-256-GCM, a
standard algorithm, so the honest answers are:

- Does your app use encryption? **Yes**
- Does it qualify for an exemption (Category 5, Part 2)? It uses standard
  encryption, not Apple's only, so choose **standard encryption
  algorithms instead of, or in addition to, using or accessing the
  encryption within Apple's operating system**.

That usually needs no documents for distribution outside France; for
France, Apple asks for a French declaration or you can leave France out.
This is a legal question, so check it if you're unsure. Once answered, the
key `ITSAppUsesNonExemptEncryption` can be added to `ios/Runner/Info.plist`
so the question isn't asked again.

## App information

| Field | Value |
|---|---|
| Name (30) | IRCage |
| Subtitle (30) | IRC chat rooms, made easy |
| Category | Social Networking (secondary: Utilities) |
| Content rights | No third-party content |
| Privacy policy URL | https://ircage.com/privacy |
| Support URL | https://ircage.com/support |
| Marketing URL | https://ircage.com |
| Copyright | 2026 IRCage |
| Price | Free |

### Promotional text (170)

> Find a room, say hello. IRCage brings the classic chat rooms of IRC to
> your iPhone and iPad: no account, no ads, no tracking.

### Description

> IRCage is a modern app for IRC, the open chat network that has hosted
> real-time chat rooms for decades. Pick a nickname, pick a network, and
> you're in. No account and no sign-up.
>
> FIND YOUR ROOMS
> • Discover every room on a network, sorted by size, with topics and
> categories like Tech, Gaming, Music and Social
> • Preview a room before you join, star favorites to rejoin them next time
> • Libera.Chat, OFTC, EFnet, Undernet, DALnet and Rizon are one tap away,
> or add your own server
>
> A CHAT THAT READS WELL
> • Grouped messages, replies, mentions and typing indicators
> • Classic mIRC colours and styles, always readable in light and dark mode
> • Tap links; images and videos show right in the chat when you want them
>
> PRIVATE AND SAFE
> • Send photos and files in private chats, encrypted on your device;
> links expire within hours and photos can be seen once
> • Voice and video calls, with an option to hide your IP address
> • Hide offensive words and adult rooms (both on by default), report
> messages and ignore people
>
> FOR IRC REGULARS
> • Several networks at once, SASL login, server passwords
> • Works with bouncers such as soju and ZNC, with missed messages and
> older history
> • /commands, a classic mIRC theme and compact layout
>
> IRCage has no ads, no analytics and no tracking. Your chats go between
> your device and the networks you choose.

### Keywords (100)

```
irc,chat,chat rooms,mirc,libera,oftc,bouncer,soju,znc,community,group chat,messenger
```

### What's New (for later versions)

Paste the version's section from `CHANGELOG.md`, in plain words.

## App Privacy

Matches `ios/Runner/PrivacyInfo.xcprivacy` and the privacy policy.

- Do you or your third-party partners collect data from this app? **Yes**
- **Photos or Videos**: photos and files sent in private chats. Not
  linked to the user, not used for tracking. Purpose: **App
  Functionality**. (They're encrypted before upload and deleted within
  hours; we can't open them, but declaring them is the safe side.)
- **Other User Content**: reports (the reason, details and the reported
  message). Not linked, no tracking. Purpose: **App Functionality**.
- Nothing else: no contact info, identifiers, location, usage data,
  diagnostics or purchases. Messages go to the IRC networks, not to us.

The label will read **Data Not Linked to You: User Content**.

## Age rating

Answer the questionnaire as it is: no violence, sexual content or
gambling in the app itself; **user-generated content: yes**; **messaging
and chat: yes**; **unrestricted web access: no** (links open in Safari);
content controls: yes (word filter and adult-room filter, on by default,
plus reporting and ignoring). Public chat with strangers usually ends up
at **18+** (or 17+). Accept it: the terms and privacy policy already say
IRCage isn't for children.

## Notes for the reviewer

Paste into **App Review Information → Notes**. No demo account is needed.

> IRCage is a client for IRC, an open chat protocol run by independent
> networks (we don't run the chat servers). No sign-in is needed.
>
> To try it:
> 1. Agree to the terms, choose a nickname (any, such as "reviewer42"),
>    and tap Libera.Chat.
> 2. Open Discover to browse rooms, or join #libera to chat.
> 3. Long-press someone's message for Report message. Profiles have Ignore
>    and Report. Settings → Safety has the word filter and adult-room
>    filter (both on by default).
>
> Photos, files and voice/video calls are in private (one-to-one) chats
> and need a second person; they go through our server
> (share.ircage.com), encrypted.
>
> Reports go to support@ircage.com's review queue and are handled within
> 24 hours; the reporter stops seeing the sender right away.

Contact: your name, phone and support@ircage.com.

## Screenshots

`store/ios/screenshots/` has the sizes App Store Connect asks for:

- iPhone 6.9" (1320 × 2868): `iphone-*.png`, from the iPhone 17 Pro Max
  simulator
- iPad 13" (2064 × 2752): `ipad-*.png`, from the iPad Pro 13-inch simulator

They're taken against `tool/demo_ircd.py`, a pretend network with made-up
rooms and people, so no real person's messages appear. To take new ones:
run it, add your own network `127.0.0.1`, port 6667, TLS off, name
`Demo`, then:

```sh
xcrun simctl io booted screenshot store/ios/screenshots/iphone-1-discover.png
```

## After approval

- Choose manual or automatic release; the first one is usually manual.
- Add an App Store badge to `website/index.html` next to the downloads.
- Tick the iOS item in `docs/roadmap.md`.
