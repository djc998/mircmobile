# Publishing on Google Play

Everything the Play Console asks for IRCage on Android, ready to paste,
and the steps to get a build there. The App Store version is in
[app-store.md](app-store.md).

The app ID is **`com.ircage.app`**. It can never change once the app is on
Play. (The Kotlin package, `com.djc998.irc_client`, is separate and doesn't
matter to Play.)

## Before the first upload

- [ ] A Google Play developer account (play.google.com/console, one-time
      fee). Personal accounts made after November 2023 must run a **closed
      test with at least 12 testers for 14 days in a row** before they can
      publish to everyone, so start that early. Organization accounts
      (with a D-U-N-S number) skip it.
- [ ] `support@ircage.com` receives mail, and someone reads
      `/admin/reports` daily (the terms promise 24 hours).
- [ ] **JDK 21 for Gradle.** The Android build's lint step crashes on the
      JDK 17 that comes with older Android Studio. Point Flutter at JDK 21
      once (Homebrew's `openjdk@21` is already installed):

      ```sh
      flutter config --jdk-dir=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
      ```

## The upload key (once)

Play signs the app for users with its own key (Play App Signing, on by
default). You sign uploads with an **upload key** that stays with you. If
it's lost, Play support can reset it, but keep a backup.

1. Make it (it asks for a password; use a password manager):

   ```sh
   mkdir -p ~/keys
   keytool -genkey -v -keystore ~/keys/ircage-upload.jks -keyalg RSA \
     -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties` (git ignores it; never commit it):

   ```properties
   storeFile=/Users/you/keys/ircage-upload.jks
   storePassword=…
   keyAlias=upload
   keyPassword=…
   ```

Without `key.properties`, release builds are signed with the debug key:
fine for trying them, but Play refuses them.

## Making a build and uploading it

1. Raise the build number in `pubspec.yaml` (the number after `+`). Every
   upload needs a higher one, and it's shared with the App Store builds.
2. Build:

   ```sh
   flutter build appbundle --release
   ```

   This writes `build/app/outputs/bundle/release/app-release.aab`
   (about 80 MB with every CPU type; Play sends each phone only its own
   part, around 25 MB). Store builds never check GitHub for updates.
3. In the Play Console: **Test and release → Testing → Closed testing →
   Create track**, upload the .aab, add release notes, add testers (an
   email list or a Google Group), and roll it out. After the 14 days,
   **Production → Create release** with the same or a newer build.

## Store listing

| Field | Value |
|---|---|
| App name (30) | IRCage |
| Category | Communication |
| Tags | Chat, Messaging |
| Email | support@ircage.com |
| Website | https://ircage.com |
| Privacy policy | https://ircage.com/privacy |
| App icon | `store/android/icon-512.png` (512 × 512) |
| Feature graphic | `store/android/feature-graphic.png` (1024 × 500) |
| Phone screenshots | `store/android/screenshots/phone-*.png` |
| Tablet screenshots | `store/android/screenshots/tablet-*.png` |

### Short description (80)

> IRC chat rooms, made easy. No account, no ads, no tracking.

### Full description (4000)

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

## App content (Policy → App content)

- **Privacy policy:** https://ircage.com/privacy
- **Ads:** No.
- **App access:** All functionality is available without special access.
  (No login. Add the reviewer note below under "Instructions" anyway.)
- **Account deletion:** the app has no accounts, so "No" to creating
  accounts.
- **Target audience:** 18 and over only. (Choosing younger ages brings in
  the Families policy, which an open chat app can't meet.)
- **Content rating** (IARC questionnaire, category *Communication* /
  social): no violence, sexual content, gambling or drugs in the app
  itself; **users can interact or exchange content: Yes**; **shares the
  user's location: No**; **digital purchases: No**; **unrestricted
  internet: No** (links open in the browser). Expect a Teen/Mature-style
  rating with the "Users Interact" notice.
- **News app:** No. **Government app:** No. **Financial features:** none.
  **Health:** none.
- **Data safety:** see below.
- **Foreground service permissions:** the app declares a *special use*
  foreground service for **Stay connected in the background** (off by
  default; see [features/background.md](features/background.md)). Play
  asks why and wants a short video:
  - Task: *Other*. Description:
    > Keeps the user's IRC chat connection open while the app is in the
    > background, so they keep receiving messages. It only runs when the
    > user turns on Settings → Notifications → Stay connected in the
    > background, shows an ongoing notification the whole time, and stops
    > when the app is closed. No other foreground service type covers a
    > user-requested chat connection.
  - Video (an unlisted YouTube link is fine): open Settings →
    Notifications, turn on Stay connected, go Home and show the ongoing
    "Staying connected" notification, then a message arriving while the
    app is in the background.

### Data safety

Matches the privacy policy and the iOS privacy manifest.

- Does the app collect or share any of the required user data types?
  **Yes.**
- Is all collected data encrypted in transit? **Yes.**
- Can users request that data be deleted? **Yes** (photos and files delete
  themselves within hours; reports by emailing support@ircage.com).

| Data type | Collected | Shared | Optional | Purpose |
|---|---|---|---|---|
| Photos and videos → Photos | Yes | No | Yes | App functionality |
| Files and docs | Yes | No | Yes | App functionality |
| App activity → Other user-generated content (reports) | Yes | No | Yes | App functionality |

Not collected: location, personal info, contacts, messages (IRC messages
go to the IRC networks, not to us), app info and performance, device or
other IDs, financial info, health, web browsing, audio. Calls are
peer-to-peer (or through an encrypted relay) and aren't stored.

Photos and files are encrypted on the device before upload, so we can't
open them; they're declared anyway, on the safe side.

## Notes for the reviewer

Paste into **App access → instructions** (and the release notes for the
first closed test, if you like):

> IRCage is a client for IRC, an open chat protocol run by independent
> networks (we don't run the chat servers). No sign-in is needed.
>
> 1. Agree to the terms, choose a nickname (any, such as "reviewer42"),
>    and tap Libera.Chat.
> 2. Open Discover to browse rooms, or join #libera to chat.
> 3. Long-press someone's message for Report message. Profiles have Ignore
>    and Report. Settings → Safety has the word filter and adult-room
>    filter (both on by default).
>
> Photos, files and calls are in private chats and need a second person;
> they go through our server (share.ircage.com), encrypted.

## Screenshots

`store/android/screenshots/` has phone shots (1080 × 2160) and 10-inch
tablet shots (2560 × 1600), taken on the Android emulator against
`tool/demo_ircd.py`, a pretend network with made-up rooms and people. Play
wants the long side no more than twice the short one, so the phone shots
are taken with the screen set to 1080 × 2160:

```sh
adb shell wm size 1080x2160      # 'adb shell wm size reset' afterwards
adb exec-out screencap -p > store/android/screenshots/phone-1-welcome.png
```

In the emulator the demo server on your Mac is `10.0.2.2`, port 6667,
TLS off.

## After launch

- Add a Google Play badge to `website/index.html` next to the downloads.
- Tick the Android item in `docs/roadmap.md`.
