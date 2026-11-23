# Safety

Available on iOS, Android and macOS (shared Flutter code). What Apple asks
of apps with user-generated content (App Review Guideline 1.2): terms with
no tolerance for abuse, a filter, reporting, blocking, and a way to reach
the makers.

## What the user sees

- **Terms of use, first.** Before the welcome screen, a page of short
  sections (what IRCage is, no tolerance for abuse, keeping yourself safe,
  reports, photos and calls, contact) with **Agree and continue**. It's
  asked once, and again when the terms change. Settings → About →
  **Terms of use** shows them again without the button; **Contact** shows
  the address.
- **Hide offensive words** (Settings → Safety, on by default): slurs and
  the strongest swearing show as the first letter and `*` ("s***") in
  messages, topics, room info, chat previews, Discover and system lines.
  Whole words only, so "class", "spicy" or "Scunthorpe" are untouched.
- **Hide adult rooms** (Settings → Safety, and Discover → Filters; on by
  default): rooms whose name or topic mention sex, porn, NSFW, nudes,
  18+ and similar are left out of Discover.
- **Report message:** long-press someone else's message (or the flag that
  shows on hover on a Mac), pick a reason, add details if you like. The
  message goes to the IRCage team for review and the sender is ignored.
  Your own messages can't be reported.
- Already there: **Report photo**, **Ignore** and **Report** on a profile
  (who the room's operators are), and Settings → **Ignored people**.

## Before submitting to the App Store

- Put a real address in `supportContact` in `lib/app/legal.dart` (it's
  `support@example.com` for now).
- Redeploy the picture host so it accepts message reports, and review
  `/admin/reports` at least daily: the terms promise 24 hours
  ([server/picture-host/README.md](../../server/picture-host/README.md)).

## Code

- `lib/app/legal.dart`: `termsVersion`, `supportContact`, `termsSections`.
- `lib/core/safety/content_filter.dart`: `maskOffensive`, `hasOffensive`,
  `isAdultRoom`, and the `ContentFilter` scope the app puts above every
  screen.
- `lib/features/safety/application/safety_controller.dart`:
  `safetyProvider` (`termsAgreed`, `filterWords`, `hideAdultRooms`, saved
  under `safety`).
- `lib/features/safety/presentation/terms_screen.dart`: `TermsScreen`
  (route `/terms`, `?read=1` for read-only); the router in
  `lib/app/app.dart` sends everything there until the terms are agreed.
- `lib/features/safety/presentation/report_dialog.dart`: `ReportDialog`,
  shared by messages and photos.
- `mircSpans(filter:)`; `ChatController.reportMessage`;
  `PictureService.reportMessage`; `POST /report` with `"kind":"message"`
  on the picture host.

## Tests

`test/features/safety/safety_test.dart` (the word lists, adult rooms, the
terms gate, masking on and off, reporting a message, Discover, Settings)
and `server/picture-host/test/worker.test.js` (message reports).
`test/flutter_test_config.dart` starts other tests with the terms agreed.
