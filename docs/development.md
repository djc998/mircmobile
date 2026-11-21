# Development

## Requirements
- Flutter stable (3.50 or newer), Dart 3.14
- Xcode for iOS/macOS builds, Android Studio or the Android SDK for Android

## Common tasks
```sh
flutter pub get
dart format .
flutter analyze        # must report no issues
flutter test           # unit + widget tests
flutter run -d ios     # or -d android / -d macos
```

## Rules
- Every feature ships on iOS, Android and macOS together.
- Every change adds a CHANGELOG.md entry and updates docs/.
- `lib/core/irc` stays pure Dart (no Flutter imports) and fully tested.
