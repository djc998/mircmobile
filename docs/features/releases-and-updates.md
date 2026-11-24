# Releases and updates

How the Mac, Windows and Linux downloads on ircage.com are made, and how
those apps find out about new versions. App Store and Google Play builds
are updated by the stores and never check.

## Making a release

1. Set `version:` in `pubspec.yaml` (e.g. `1.1.0+12`) and merge it.
2. Tag the matching commit on `main` and push the tag:

   ```sh
   git tag v1.1.0
   git push origin v1.1.0
   ```

3. `.github/workflows/release.yml` checks the tag matches `pubspec.yaml`,
   builds all three apps (each on its own GitHub runner), and publishes a
   GitHub release `IRCage 1.1.0` with:
   - `IRCage-macOS.zip`: `IRCage.app`
   - `IRCage-Windows-x64.zip`: the `IRCage` folder with `IRCage.exe`
   - `IRCage-Linux-x64.tar.gz`: the `IRCage` folder with `ircage`

The names never change, so the website links to
`https://github.com/djc998/mircmobile/releases/latest/download/<name>`
and always gets the newest one.

### Not signed yet

Without an Apple Developer ID and a Windows code-signing certificate, the
first launch shows a warning; the release notes and the website say how to
open the app anyway (Mac: System Settings → Privacy & Security → **Open
Anyway**; Windows: **More info** → **Run anyway**). Signing (and Apple
notarization) can be added to the workflow once the certificates exist.

## Update checks

- Only release builds check: they're built with
  `--dart-define=DISTRIBUTION=direct` and `--dart-define=APP_VERSION=<version>`
  (`updatesSupported`). Local, App Store and Google Play builds don't.
- On launch and every 24 hours, the app asks GitHub for the latest release
  (`GET https://api.github.com/repos/djc998/mircmobile/releases/latest`).
  Nothing else is sent. Errors, no release, or rate limits just mean "no
  update".
- A newer version shows a banner across the top: **IRCage 1.1.0 is
  available.** with **Download** (opens the release page) and **Later**
  (hides it until an even newer version).
- Settings → About → **Check for updates** turns it off, and shows whether
  you're up to date.

## Code

- `.github/workflows/release.yml`
- `lib/features/updates/update_checker.dart`: `updatesSupported`,
  `compareVersions`, `updateProvider` (`start`, `check`, `later`,
  `setEnabled`).
- `lib/features/updates/update_banner.dart`: `UpdateBannerHost` (wraps every
  screen in `lib/app/app.dart`).
- Settings → About: `_UpdatesTile`.

## Tests

`test/features/updates/update_test.dart`: version order, which builds
check, finding a release, staying quiet on errors, Later and switching off,
and the banner's Download and Later.
