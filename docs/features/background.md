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

### Tests

- `test/core/irc/connection_check_test.dart`: live connection answers;
  buffered lines and other PONGs don't count; no answer reconnects at once
  and rejoins; a failing write reconnects at once; a waiting reconnect
  retries now; a disconnected client is left alone; one check at a time.
- `test/features/chat/resume_test.dart`: the bar shows and goes on PONG;
  a dead connection reconnects, keeps the open chat selected, sends
  `CHATHISTORY LATEST` for the room and the private chat plus
  `CHATHISTORY TARGETS`, and doesn't repeat the welcome; inactive without
  hidden doesn't check; a disconnected network is left alone.
