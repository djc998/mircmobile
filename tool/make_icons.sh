#!/bin/sh
# Regenerates every app icon from tool/icon/render_icons_test.dart (the
# icon's source) for iOS, Android and macOS. Needs ImageMagick (`magick`).
set -eu
cd "$(dirname "$0")/.."
flutter test tool/icon/render_icons_test.dart >/dev/null
work=build/icons

# iOS: no transparency allowed.
ios=ios/Runner/Assets.xcassets/AppIcon.appiconset
for f in "$ios"/Icon-App-*.png; do
  name=$(basename "$f" .png)              # Icon-App-83.5x83.5@2x
  pt=${name#Icon-App-}; pt=${pt%%x*}      # 83.5
  scale=${name##*@}; scale=${scale%x}     # 2
  px=$(echo "$pt * $scale" | bc | cut -d. -f1)
  magick "$work/ios.png" -background '#5B5BF0' -alpha remove -alpha off \
    -resize "${px}x${px}" "$f"
done

# macOS
mac=macos/Runner/Assets.xcassets/AppIcon.appiconset
for px in 16 32 64 128 256 512 1024; do
  magick "$work/macos.png" -resize "${px}x${px}" "$mac/app_icon_$px.png"
done

# Android: legacy icons, and adaptive foregrounds (108dp canvas).
res=android/app/src/main/res
for pair in mdpi:48:108 hdpi:72:162 xhdpi:96:216 xxhdpi:144:324 xxxhdpi:192:432; do
  d=${pair%%:*}; rest=${pair#*:}; legacy=${rest%%:*}; fg=${rest#*:}
  magick "$work/legacy.png" -resize "${legacy}x${legacy}" "$res/mipmap-$d/ic_launcher.png"
  magick "$work/foreground.png" -resize "${fg}x${fg}" \
    "$res/mipmap-$d/ic_launcher_foreground.png"
done
echo "Icons written."
