#!/bin/sh
# Draws the app icon for Android and iOS from the desktop's build/icon.svg, so the phone shows the
# same icon as the Mac and Windows. Run on the PC after the icon changed: sh tool/make_icons.sh
# Runs on the Mac (sips) with rsvg-convert (brew install librsvg). The images it writes are committed.
set -eu
cd "$(dirname "$0")/.."
res=android/app/src/main/res
ios=ios/Runner/Assets.xcassets/AppIcon.appiconset
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# The desktop icon's drawing, on its 1024 canvas, where the Mac's rounded square spans 100 to 924.
GRADIENT='<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#4f8ef7"/><stop offset="1" stop-color="#2353c4"/></linearGradient>'
ART='
  <path d="M274 230H510L610 330V770a24 24 0 0 1-24 24H274a24 24 0 0 1-24-24V254a24 24 0 0 1 24-24Z" fill="#fff"/>
  <path d="M510 230V306a24 24 0 0 0 24 24H610Z" fill="#c9d8f7"/>
  <rect x="300" y="390" width="220" height="24" rx="12" fill="#b9c3d6"/>
  <rect x="288" y="446" width="290" height="48" rx="12" fill="#ffd400"/>
  <rect x="300" y="458" width="262" height="24" rx="12" fill="#5b6780"/>
  <rect x="300" y="526" width="96" height="24" rx="12" fill="#2f6fed"/>
  <rect x="410" y="526" width="130" height="24" rx="12" fill="#b9c3d6"/>
  <rect x="300" y="594" width="240" height="24" rx="12" fill="#b9c3d6"/>
  <rect x="300" y="662" width="180" height="24" rx="12" fill="#b9c3d6"/>
  <g fill="none" stroke="#fff" stroke-width="30" stroke-linecap="round">
    <path d="M675 466A70 70 0 0 1 675 574"/><path d="M710 424A125 125 0 0 1 710 616"/><path d="M746 382A180 180 0 0 1 746 658"/>
  </g>'
# The same in one colour, the text lines cut out of the page: Android tints it (status bar, themed icons).
SILHOUETTE='
  <mask id="lines"><rect width="1024" height="1024" fill="#fff"/>
    <g fill="#000"><rect x="300" y="390" width="220" height="24" rx="12"/><rect x="300" y="458" width="262" height="24" rx="12"/>
    <rect x="300" y="526" width="240" height="24" rx="12"/><rect x="300" y="594" width="240" height="24" rx="12"/>
    <rect x="300" y="662" width="180" height="24" rx="12"/></g></mask>
  <path mask="url(#lines)" d="M274 230H510L610 330V770a24 24 0 0 1-24 24H274a24 24 0 0 1-24-24V254a24 24 0 0 1 24-24Z" fill="#fff"/>
  <g fill="none" stroke="#fff" stroke-width="30" stroke-linecap="round">
    <path d="M675 466A70 70 0 0 1 675 574"/><path d="M710 424A125 125 0 0 1 710 616"/><path d="M746 382A180 180 0 0 1 746 658"/>
  </g>'

# Scales the drawing about the canvas centre: the Mac square's 824 px become $1 px.
at() { echo "translate(512 512) scale($(echo "scale=4; $1 / 824" | bc)) translate(-512 -512)"; }
svg() { printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024"><defs>%s</defs>%s</svg>' "$GRADIENT" "$2" > "$tmp/$1.svg"; }

# iOS masks the corners itself and wants no transparency: the square fills the whole image.
svg ios "<rect width=\"1024\" height=\"1024\" fill=\"url(#bg)\"/><g transform=\"$(at 1024)\">$ART</g>"
# Android before 8 shows the image as it is: the rounded square, with the margin launchers expect.
svg legacy "<rect x=\"86\" y=\"86\" width=\"852\" height=\"852\" rx=\"190\" fill=\"url(#bg)\"/><g transform=\"$(at 852)\">$ART</g>"
# Android 8 and later (adaptive icons): a 108 dp background and foreground that the launcher shapes and
# crops to about the middle 72 dp; the drawing keeps to the 66 dp that is always shown.
svg background '<rect width="1024" height="1024" fill="url(#bg)"/>'
svg foreground "<g transform=\"$(at 683)\">$ART</g>"
svg monochrome "<g transform=\"$(at 683)\">$SILHOUETTE</g>"
# The notification's icon in the status bar: the silhouette, filling the 24 dp almost to the edge.
svg notification "<g transform=\"translate(512 512) scale(1.6) translate(-505 -512)\">$SILHOUETTE</g>"

draw() { rsvg-convert -w "$2" -h "$2" "$tmp/$1.svg" -o "$3"; }

for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  name=${d%:*}
  x=${d#*:}
  px() { echo "$1 * $x / 1" | bc; }
  mkdir -p "$res/mipmap-$name" "$res/drawable-$name"
  draw legacy "$(px 48)" "$res/mipmap-$name/ic_launcher.png"
  draw background "$(px 108)" "$res/mipmap-$name/ic_launcher_background.png"
  draw foreground "$(px 108)" "$res/mipmap-$name/ic_launcher_foreground.png"
  draw monochrome "$(px 108)" "$res/mipmap-$name/ic_launcher_monochrome.png"
  draw notification "$(px 24)" "$res/drawable-$name/ic_notification.png"
done

mkdir -p "$res/mipmap-anydpi-v26"
cat > "$res/mipmap-anydpi-v26/ic_launcher.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<!-- Written by tool/make_icons.sh. -->
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
    <monochrome android:drawable="@mipmap/ic_launcher_monochrome" />
</adaptive-icon>
XML

# The file names and sizes the Xcode project lists.
for entry in 20x20@1x:20 20x20@2x:40 20x20@3x:60 29x29@1x:29 29x29@2x:58 29x29@3x:87 40x40@1x:40 \
    40x40@2x:80 40x40@3x:120 60x60@2x:120 60x60@3x:180 76x76@1x:76 76x76@2x:152 83.5x83.5@2x:167 \
    1024x1024@1x:1024; do
  draw ios "${entry#*:}" "$tmp/icon.png"
  # rsvg-convert keeps an alpha channel even when nothing is transparent; the App Store refuses one.
  sips -s format jpeg -s formatOptions best "$tmp/icon.png" --out "$tmp/icon.jpg" >/dev/null
  sips -s format png "$tmp/icon.jpg" --out "$ios/Icon-App-${entry%:*}.png" >/dev/null
done
echo "Icons written."
