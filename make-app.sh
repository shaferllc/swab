#!/bin/bash
# Usage:
#   ./make-app.sh          build for this Mac, install to /Applications, launch
#   ./make-app.sh --dist   build a universal dist/Swab.app plus a .zip and .dmg
# VERSION=x.y.z overrides the bundle version (defaults to 0.2).
set -euo pipefail
cd "$(dirname "$0")"

DIST=0
[ "${1:-}" = "--dist" ] && DIST=1
SHORT_VERSION="${VERSION:-0.2}"

if [ "$DIST" = "1" ]; then
  # Anything people download has to run on both architectures — an arm64-only
  # binary is a broken download for every Intel Mac. The local install path
  # stays single-arch because it only ever has to run on this machine.
  echo "› Building universal release binary…"
  swift build -c release --arch arm64 --arch x86_64
  BINARY=".build/apple/Products/Release/Swab"
else
  echo "› Building release binary…"
  swift build -c release
  BINARY=".build/release/Swab"
fi

if [ ! -f AppIcon.icns ] || [ make-icon.swift -nt AppIcon.icns ]; then
  echo "› Generating AppIcon.icns…"
  swift make-icon.swift
fi

STAGE="$(mktemp -d)"
APP="$STAGE/Swab.app"
echo "› Assembling in staging: $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY"     "$APP/Contents/MacOS/Swab"
cp AppIcon.icns  "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                 <string>Swab</string>
    <key>CFBundleDisplayName</key>          <string>Swab</string>
    <key>CFBundleIdentifier</key>           <string>com.tomshafer.swab</string>
    <key>CFBundleVersion</key>              <string>2</string>
    <key>CFBundleShortVersionString</key>   <string>${SHORT_VERSION}</string>
    <key>CFBundleExecutable</key>           <string>Swab</string>
    <key>CFBundlePackageType</key>          <string>APPL</string>
    <key>CFBundleSupportedPlatforms</key>   <array><string>MacOSX</string></array>
    <key>CFBundleIconFile</key>             <string>AppIcon</string>
    <key>CFBundleIconName</key>             <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>       <string>14.0</string>
    <key>LSUIElement</key>                  <true/>
    <key>NSHighResolutionCapable</key>      <true/>
    <key>NSHumanReadableCopyright</key>     <string>© 2026 Tom Shafer</string>

    <!-- The \`swab\` command-line tool drives the app through this scheme. -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>          <string>com.tomshafer.swab.command</string>
            <key>CFBundleURLSchemes</key>       <array><string>swab</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

xattr -cr "$APP" 2>/dev/null || true
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

if [ "$DIST" = "1" ]; then
  rm -rf dist
  mkdir -p dist
  /bin/mv "$APP" dist/Swab.app
  rm -rf "$STAGE"

  echo "› Packaging dist/Swab-${SHORT_VERSION}.zip"
  /usr/bin/ditto -c -k --keepParent dist/Swab.app "dist/Swab-${SHORT_VERSION}.zip"

  # A DMG alongside the zip: it opens to a window holding Swab.app next to an
  # /Applications alias, so installing is one drag rather than "unzip, then
  # find where it went". UDZO is compressed and read-only.
  echo "› Packaging dist/Swab-${SHORT_VERSION}.dmg"
  DMG_ROOT="$(mktemp -d)"
  /bin/cp -R dist/Swab.app "$DMG_ROOT/Swab.app"
  /bin/ln -s /Applications "$DMG_ROOT/Applications"
  /usr/bin/hdiutil create \
    -volname "Swab ${SHORT_VERSION}" \
    -srcfolder "$DMG_ROOT" \
    -fs HFS+ -format UDZO -ov -quiet \
    "dist/Swab-${SHORT_VERSION}.dmg"
  rm -rf "$DMG_ROOT"
  echo "› Packaged: dist/Swab-${SHORT_VERSION}.dmg"
else
  DEST="/Applications/Swab.app"
  echo "› Installing to $DEST"
  /usr/bin/pkill -x Swab 2>/dev/null || true
  /bin/sleep 0.3
  rm -rf "$DEST"
  /bin/mv "$APP" "$DEST"
  rm -rf "$STAGE"
  open "$DEST"
  echo "› Installed and launched: $DEST"
fi
