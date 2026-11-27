# The app in the background

Phones don't keep an app's network connections open for long once you
switch away from it. This page says what IRCage does about that on each
platform, and what's still planned.

## Coming back to the app (all platforms)

Available on iOS, Android and macOS (shared Flutter code; Windows and
Linux too).

- When the app comes back from the background, every open network is
  checked straight away instead of waiting for the next keep-alive (up to
  two and a half minutes). The chat shows a thin **Reconnecting…** bar,
  and the subtitle says **Reconnecting…**, until it's sorted out.
- A connection that's still alive answers within a second or two and the
  bar goes away.
- A connection the system dropped (iOS does that within seconds of
  leaving the app) gets no answer within 6 seconds, or fails to send at
  all, and is reconnected **at once**, without the usual 2, 4, 8… second
  backoff. A network that was already waiting to reconnect tries again
  now.
- After reconnecting it rejoins its rooms **without jumping to them**: you
  stay on the chat you were reading. The "Welcome" line isn't repeated.
- Missed messages come back through IRCv3 chathistory where the server
  keeps history (Ergo, soju…; see [chathistory.md](chathistory.md)): each
  room and private chat gets what was said while you were away, and
  people who wrote to you meanwhile show up as new private chats. Leaving
  the app saves "seen until" right away, so the catch-up asks from then.
- Only really leaving the app counts: pulling down Control Center or the
  notification shade doesn't trigger a check. Networks you disconnected
  yourself stay disconnected.

### How it works

- `AppLifecycleWatcher` (`lib/app/app_lifecycle.dart`) wraps the app and
  uses an `AppLifecycleListener`: on `hide` it calls
  `ChatController.appPaused()` (writes "seen until" for each connected
  network), and on the next `show` it calls `ChatController.appResumed()`.
- `appResumed` sets `NetworkSession.resuming` (which shows `ReconnectingBar`
  in `chat_screen.dart`) and calls `IrcClient.checkConnection()` on every
  network that isn't disconnected or still connecting.
- `IrcClient.checkConnection({timeout = 6 s})`:
  - connected or logging in: sends `PING :check-<n>` and waits for the
    `PONG` carrying that token. Other lines don't count, since a dead
    socket can still hand over lines it had buffered. The answer emits
    `ConnectionCheckedEvent`; no answer in time, or a write error, closes
    the connection and reconnects with no delay.
  - waiting to reconnect: cancels the backoff timer and connects now.
  - disconnected or connecting: nothing.
- `ChatController` clears `resuming` on `ConnectionCheckedEvent` or when
  the network is connected (or disconnected) again. A dropped connection
  also clears any history request that was in flight, so the catch-up
  after reconnecting isn't skipped.
- `NetworkSession.registrations` counts logins: from the second one on, a
  self-JOIN for a room that's already open doesn't select it.

### Tests (coming back)

- `test/core/irc/connection_check_test.dart`: live connection answers;
  buffered lines and other PONGs don't count; no answer reconnects at once
  and rejoins; a failing write reconnects at once; a waiting reconnect
  retries now; a disconnected client is left alone; one check at a time.
- `test/features/chat/resume_test.dart`: the bar shows and goes on PONG;
  a dead connection reconnects, keeps the open chat selected, sends
  `CHATHISTORY LATEST` for the room and the private chat plus
  `CHATHISTORY TARGETS`, and doesn't repeat the welcome; inactive without
  hidden doesn't check; a disconnected network is left alone.

## Notifications for private messages and mentions

Available on iOS, Android and macOS (flutter_local_notifications). Not on
Windows and Linux yet: there the app shows no notifications.

- While the app is in the background (on a Mac: hidden, minimised or
  behind another app; a system alert over the app on a phone doesn't
  count),
  a private message or a room message that says your nickname shows a
  notification: **bob** with the message, or **ann in #chat**. With
  several networks open the network is added (`bob · OFTC`). `/me`
  actions read `* ann waves`. mIRC colours and bold are stripped.
- Not for: anything while the app is in front, your own messages,
  notices (NickServ and friends), history the server replays after a
  reconnect, ignored people, muted rooms and private chats.
- One notification per conversation: a newer message replaces the older
  one. Opening that conversation clears it.
- Tapping it opens the app on that conversation.
- **Settings → Notifications → Private messages and mentions** turns them
  off (on by default). The system asks for permission once, after you
  first log in to a network (Android 13+, iOS, macOS); turning the switch
  on asks again if needed.
- They only come while the app is still running: on Android until the
  system stops it (or always, with **Stay connected**, below), on iOS for
  about 30 seconds after leaving the app (below).

## Android: Stay connected in the background

Android only: iOS has no equivalent that an App Store app may use for a
chat connection (see the plan below), and on a Mac or PC the app keeps
running anyway.

- **Settings → Notifications → Stay connected in the background**, off by
  default. When on and at least one network is open, a foreground service
  keeps the app running after you leave it, with a quiet ongoing
  notification: **IRCage is staying connected**. Your networks stay
  connected, so private messages and mentions arrive as they're sent.
- It stops when the setting is turned off, when every network is
  disconnected or closed, and when the app is swiped away from recent
  apps (the connection goes with it).
- It uses more battery: the setting says so. Some phone makers' battery
  savers stop background apps anyway; allowing IRCage in the system's
  battery settings helps there.

### How it works

- The service is flutter_local_notifications' `ForegroundService`
  (`android/app/src/main/AndroidManifest.xml`), type `specialUse` with a
  `PROPERTY_SPECIAL_USE_FGS_SUBTYPE` explanation and `stopWithTask`.
  Permissions: `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`,
  `FOREGROUND_SERVICE_SPECIAL_USE`. It only keeps the process alive; the
  IRC connections are the app's usual ones in the Flutter engine.
  **Play Console:** the app's foreground service declaration needs the
  same explanation (special use: keeping a user-requested chat connection
  open) and a short video of the setting.
- Android 12+ doesn't let an app start a foreground service from the
  background, so it's started in the foreground (when the setting is
  turned on, or a network is opened). A network that drops in the
  background stays "reconnecting", which keeps the service running.
- Notification channels: **Messages** (high importance) and **Staying
  connected** (low, ongoing). Core library desugaring is on in
  `android/app/build.gradle.kts`, which the plugin needs.

### Code

- `lib/features/notifications/data/message_notifier.dart`:
  `MessageNotifier` (what the app needs), `NoMessageNotifier` (tests,
  Windows, Linux), `LocalMessageNotifier` (the plugin), and
  `messageNotifierProvider`, overridden in `main.dart`.
- `lib/features/notifications/application/notification_settings.dart`:
  `NotificationSettings` (`messages`, `stayConnected`, `askedPermission`,
  saved as `notifications`).
- `lib/features/notifications/application/keep_alive.dart`:
  `keepAliveProvider` starts and stops the service; `AppLifecycleWatcher`
  watches it and routes notification taps to the chat.
- `ChatController._maybeNotify`, `ChatController.notificationId`;
  `selectBuffer` clears the conversation's notification.
- `settings_screen.dart`: the Notifications group.

### Tests

`test/features/notifications/notifications_test.dart`: private messages,
mentions and actions notify in the background, other messages don't;
nothing in the foreground; muted rooms and the switch turned off stay
quiet; tapping opens the chat and opening clears it; permission is asked
once; the service runs only with the setting on and a network open; the
Settings switches.

## iOS: the short background window

- iOS suspends an app a few seconds after you leave it, and its sockets
  stop. IRCage asks for a little more time when it goes to the background
  (`beginBackgroundTask` in `ios/Runner/AppDelegate.swift`, normally
  about 30 seconds). Until iOS ends that, private messages and mentions
  still arrive and show as notifications. Then the app is suspended and
  the server drops the connection after its ping timeout; coming back
  reconnects at once (above).
- `AppDelegate` also makes flutter_local_notifications the
  `UNUserNotificationCenter` delegate, so tapping a notification opens
  the chat.
- Settings → Notifications on iOS says this, and points to a bouncer for
  staying online.
- Apple doesn't allow an App Store app to keep a chat socket open in the
  background (the VoIP and audio modes are for calls and audio only), so
  staying connected on iOS means letting a server stay connected instead,
  and having it **push** what matters to the phone. That's the plan below.

## Plan: staying connected on iOS (bouncer + push)

Not built yet. It needs server-side pieces, and each one is a separate
piece of work.

### How it would work

1. **A bouncer stays connected.** The user connects through soju (already
   supported, see [bouncers.md](bouncers.md)). soju stays on IRC while the
   phone sleeps and keeps history, which the app already fetches through
   chathistory when it comes back.
2. **soju pushes.** soju implements the `soju.im/webpush` extension: a
   client registers a Web Push subscription (`WEBPUSH REGISTER <endpoint>
   <keys>`, with the server's VAPID key from `ISUPPORT VAPID=`), and soju
   sends an encrypted Web Push message (RFC 8030/8291) to that endpoint
   for each private message and mention, while the client is away.
3. **A push relay turns Web Push into APNs.** An iPhone app can't receive
   Web Push itself, so the endpoint is ours: a small relay that accepts
   the Web Push request and forwards it to Apple Push Notification service
   for the device token it was registered with. The payload stays
   encrypted end to end: the relay only sees ciphertext and a token. It
   fits next to the picture host as a Cloudflare Worker
   (`server/picture-host`, or its own Worker), with the APNs key as a
   secret.
4. **The phone decrypts and shows it.** A Notification Service Extension
   in the iOS app decrypts the payload with the subscription's private key
   (kept in a Keychain access group shared with the app), and shows
   "bob: hey" or "ann in #chat: me: lunch?". Tapping it opens the chat,
   which catches up through chathistory.

### What to build, in order

- **App:** on a bouncer that offers `soju.im/webpush`, create a P-256 key
  pair and auth secret, register for remote notifications (APNs device
  token), register the subscription with soju, and unregister when the
  network is removed or notifications are turned off. Add the Push
  Notifications capability and the Notification Service Extension target
  (iOS and macOS).
- **Relay:** `POST /push/<subscription-id>` receives Web Push and sends
  to APNs (token-based auth, `apns-push-type: alert`,
  `mutable-content: 1`); registration stores subscription id → device
  token, nothing else; rate limits; deletes on APNs `410 Unregistered`.
- **Android:** the same relay can forward to Firebase Cloud Messaging, so
  Android users can get push through a bouncer too, without **Stay
  connected** and its battery cost. UnifiedPush is an alternative that
  needs no Google services.
- **Privacy:** the relay never sees message text; the privacy policy and
  App Store privacy labels need updating for the device token it keeps.
- **Without a bouncer:** a plain IRC server can't push, so there's
  nothing to do there; the app keeps reconnecting on return.

### Code (today)

- `ios/Runner/AppDelegate.swift`: background task and notification
  center delegate.
- iOS notifications use the same Dart code as Android and macOS (above).
