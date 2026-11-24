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

### Signing the Mac app

When the repository has these secrets, the release signs `IRCage.app` with a
Developer ID, has Apple notarize it and staples the result
(`tool/macos_release.sh`), so it opens without a warning. Without them the
Mac app is built unsigned, with a warning in the run.

| Secret | What it is |
|---|---|
| `MACOS_CERT_P12_BASE64` | the Developer ID Application certificate and its private key, exported as .p12, base64 |
| `MACOS_CERT_PASSWORD` | the password chosen when exporting it |
| `ASC_KEY_P8_BASE64` | an App Store Connect API key (.p8), base64 |
| `ASC_KEY_ID` | that key's Key ID |
| `ASC_ISSUER_ID` | the Issuer ID shown above the keys |

**Run workflow** on the Release workflow's page (Actions tab) builds and
signs everything without publishing: a test run, with the files on the
run's page.

To sign on a Mac instead (with the certificate in the login keychain):

```sh
flutter build macos --release --dart-define=DISTRIBUTION=direct --dart-define=APP_VERSION=1.0.1
SIGN_IDENTITY="Developer ID Application: … (W4QQ2637KN)" \
ASC_KEY_PATH=~/keys/AuthKey_XXXX.p8 ASC_KEY_ID=XXXX ASC_ISSUER_ID=… \
  tool/macos_release.sh build/macos/Build/Products/Release/IRCage.app
```

`NOTARIZE=0` only signs, for a quick check.

Windows downloads aren't signed yet: "Windows protected your PC" →
**More info** → **Run anyway**. A Windows code-signing certificate would
remove that.

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
