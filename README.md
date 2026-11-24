# IRCage

IRCage is a modern mIRC-style IRC client for iPhone, iPad, Mac, Android,
Windows and Linux, built with
Flutter. The goal is to make classic IRC chat easy again: pick a network,
find a room, start talking.

- Built-in networks: Libera.Chat, OFTC, EFnet, Undernet, DALnet, Rizon
- Secure (TLS) connections, account login (SASL), classic /commands
- One codebase for iOS, Android, macOS, Windows and Linux

See [docs/](docs/) for architecture, features and the roadmap, and
[CHANGELOG.md](CHANGELOG.md) for what changed.

```sh
flutter pub get
flutter test
flutter run
```

## Windows and Linux

The desktop builds work like the Mac app: right-click menus at the pointer,
a save dialog for files, keyboard shortcuts with Ctrl, and voice/video
calls and **Take a photo** through the app's own camera screen.

Every pull request builds both on GitHub Actions; download the
`IRCage-windows-x64` or `IRCage-linux-x64` artifact from the run's
**Summary** page.

### Windows

Needs Windows 10 or later and Visual Studio 2022 with the **Desktop
development with C++** workload.

```sh
flutter build windows --release
```

The app is the folder `build\windows\x64\runner\Release`; run
`IRCage.exe` in it (keep the DLLs and `data` folder next to it). Saved
passwords go to the Windows Credential Manager.

### Linux

Tested on Ubuntu 22.04 and later (x64). Install the build tools and
libraries first:

```sh
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev libsecret-1-dev libpulse-dev
```

```sh
flutter build linux --release
```

The app is the folder `build/linux/x64/release/bundle`; run `./ircage` in
it (or `flutter run -d linux` while developing). To run it, a machine needs
GTK 3, `libsecret-1-0` and a Secret Service keyring (GNOME Keyring or
KWallet) for saved passwords; without a keyring, passwords are kept only
until the app quits. To add IRCage to your app launcher:

```sh
cp data/app_icon.png ~/.local/share/icons/ircage.png
sed "s|^Exec=.*|Exec=$PWD/ircage|" data/ircage.desktop > ~/.local/share/applications/ircage.desktop
```

(run from inside the `bundle` folder).
