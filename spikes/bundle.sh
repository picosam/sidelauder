#!/bin/sh
# Wraps a built spike executable in a minimal .app so LaunchServices starts it
# (the Dock's environment, not the shell's) and TCC can grant it permissions.
#
# Usage: spikes/bundle.sh <target> [signing identity] [app name]
# The app name (default: the target) sets the bundle and its identifier, so
# one binary can ship as two apps with separate TCC identities.
# Without an identity the bundle is signed ad hoc, which TCC grants by cdhash:
# every rebuild then needs a fresh grant (spec 4.2.11).
set -eu
target="$1"; identity="${2:--}"; name="${3:-$1}"
here="$(cd "$(dirname "$0")" && pwd)"
swift build -c release --package-path "$here" --product "$target" >/dev/null
app="$here/build/$name.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$here/.build/release/$target" "$app/Contents/MacOS/$target"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>io.github.picosam.sidelauder.spike.$name</string>
<key>CFBundleName</key><string>$name</string>
<key>CFBundleExecutable</key><string>$target</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.0.0</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --options runtime --timestamp=none --sign "$identity" "$app" >/dev/null 2>&1
echo "$app"
