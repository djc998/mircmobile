# Voice and video calls

One-to-one voice and video calls from a private chat, on iOS, Android and
macOS. People on other IRC apps can join from a browser.

## Using it

- **Call:** open a private chat and tap **Voice call** (📞) or **Video call**
  (🎥) in the top bar. The other person gets a private message like
  `🎥 Video call from dennis: https://<host>/c/<id>#video`, and you see
  **Calling bob…** until they answer.
- **Answer:** when someone calls you, a banner appears at the top of the app:
  **bob is calling you (video)** with **Accept** and **Decline**. Calls only
  ring while the app is open (phase 1).
- **During the call:** **Mute**, **Turn camera off/on**, **Switch camera** and
  **Speaker** (phones), and **Hang up**. Video calls show the other person
  full screen with your own preview in the corner. A timer shows how long
  the call has run.
- **From another IRC app:** clicking the link opens a call page in the
  browser (Chrome, Safari, Firefox). It asks for the microphone (and camera
  for video) and joins with **Join call**.
- **Ending:** hanging up, closing the page, or losing the connection ends the
  call for both. A call nobody answers stops ringing after 10 minutes. Each
  link works for one call only; afterwards it says the call has ended.
- **Hide my IP address on calls** (start screen, **More options**, on by
  default): the call always goes through Cloudflare's relay, so the other
  person never sees your IP address. If the relay isn't set up on the
  server, the call screen says so and the call connects directly.

## Camera and microphone access

The system asks once for the camera and microphone. If that was missed or
declined, the call ends with **The camera or microphone is blocked.** and
buttons that open the right settings page:

- **Mac:** **Open Camera settings** and **Open Microphone settings** open
  System Settings → Privacy & Security at those pages; switch on
  **irc_client**.
- **iPhone / Android:** **Open Settings** opens the app's own settings
  page with its Camera and Microphone switches.

The same buttons are on the start screen under **More options → Camera and
microphone**. Code: `lib/core/platform/privacy_settings.dart`
(`url_launcher` on macOS/iOS, a small `irc_client/settings` channel in
Android's `MainActivity`).

## Privacy

- Calls are WebRTC: audio and video are encrypted end to end (DTLS-SRTP)
  between the two devices, or through the relay, which only forwards
  encrypted packets.
- The server only passes the short connection messages between the two
  sides. It keeps nothing once the call ends.
- Links posted in rooms, and old links replayed from server history (more
  than two minutes old), never ring.
- Blocked people's call links are hidden like their other messages.
- If you're already in a call, a new incoming call is declined
  automatically.

## Setup

Calls use the same Cloudflare Worker as pictures
(`server/picture-host`, see its README). It adds a Durable Object per call.
For the relay ("Hide my IP"), create a TURN key in the Cloudflare dashboard
(**Realtime → TURN Server**) and store it as two Worker secrets:

```sh
cd server/picture-host
npx wrangler secret put TURN_KEY_ID
npx wrangler secret put TURN_KEY_API_TOKEN
```

The relay is free for the first 1,000 GB a month.

## Code

- `lib/features/calls/domain/call_link.dart`: the link and its addresses.
- `lib/features/calls/data/call_api.dart`: `CallApi` (start, relay
  addresses, decline) and the WebSocket signaling channel.
- `lib/features/calls/data/call_media.dart`: `CallMedia`, with
  `WebRtcCallMedia` wrapping `flutter_webrtc` (camera, microphone, peer
  connection, video views).
- `lib/features/calls/application/call_controller.dart`: `CallController`,
  one call at a time: ring, accept, decline, start, hang up, mute, camera,
  speaker.
- `lib/features/calls/presentation/call_widgets.dart`: call buttons,
  ringing banner and call screen (`CallOverlay` sits above every page).
- `ChatController` rings for fresh call links in private messages
  (`_maybeRing`) and sends invites (`sendPrivateText`).
- Server: `server/picture-host/src/calls.js` (routes, `CallRoom` Durable
  Object, browser call page).
- Permissions: camera and microphone on iOS/macOS (`Info.plist`, macOS
  entitlements) and Android (`CAMERA`, `RECORD_AUDIO`, …).

## Tests

- `test/features/calls/calls_test.dart`: links; calling, answering,
  declining, no answer, mute/camera, "Hide my IP", and that old or room
  links don't ring (fake media and signaling).
- `server/picture-host/test/calls.test.js`: matching two people, forwarding
  signaling, third person refused, hang up, decline, ring timeout, rate
  limit, relay addresses.

## Later (phase 2)

- Ringing when the app is closed (Apple PushKit/CallKit, Android
  notifications).
- Group calls in rooms (Cloudflare Realtime SFU).
- Screen sharing on the Mac.
