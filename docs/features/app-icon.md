# App icon

A white chat bubble with the IRC `#` on an Electric Indigo gradient
(`#7474FF` → `#4141D8`); the `#` uses the accent `#5B5BF0`. It matches the
`#` mark in the app's sidebar.

| Platform | Shape |
| --- | --- |
| iOS | Full-bleed square with no transparency; iOS rounds the corners. |
| macOS | 824-pt rounded square (corner radius 185) with a soft shadow, inside the 1024 canvas (Big Sur style). |
| Android 8+ | Adaptive icon: the gradient as a background layer (`drawable/ic_launcher_background.xml`) and the bubble on a transparent foreground, inside the 72dp safe zone, so any mask shape works. |
| Older Android | Rounded square (`mipmap-*/ic_launcher.png`). |

## Changing it

The icon is drawn in code: `tool/icon/render_icons_test.dart` paints the
four 1024-px masters. Edit it, then run:

```sh
tool/make_icons.sh
```

It renders the masters into `build/icons` and resizes them into every slot
of `ios/Runner/Assets.xcassets/AppIcon.appiconset`,
`macos/Runner/Assets.xcassets/AppIcon.appiconset` and
`android/app/src/main/res/mipmap-*`. It needs ImageMagick (`magick`).
