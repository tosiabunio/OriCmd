#!/bin/zsh
# Builds a Release OriCmd.app (universal, ad-hoc signed) and packs it into
# build/Oriel-<version>.dmg as Oriel.app, the fork's name, with an Applications
# link for drag-and-drop install. (Releases up to 2026.10.5 were OriCmd-<version>.dmg;
# from 2026.10.5 on the updater accepts both names.)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(xcodebuild -project OriCmd.xcodeproj -target OriCmd -configuration Release -showBuildSettings 2>/dev/null \
  | awk '$1 == "MARKETING_VERSION" { print $3; exit }')
WORK=build/release
rm -rf "$WORK"

echo "Building Oriel $VERSION…"
xcodebuild -project OriCmd.xcodeproj -scheme OriCmd -configuration Release \
  -derivedDataPath "$WORK/DerivedData" ONLY_ACTIVE_ARCH=NO build \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"

APP="$WORK/DerivedData/Build/Products/Release/OriCmd.app"
codesign --verify --deep --strict "$APP"
for binary in "$APP/Contents/MacOS/OriCmd" "$APP/Contents/XPCServices/OriCmdHighlighter.xpc/Contents/MacOS/OriCmdHighlighter"; do
  for arch in x86_64 arm64; do
    lipo "$binary" -verify_arch $arch || { echo "$binary has no $arch"; exit 1; }
  done
done

STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Oriel.app"
ln -s /Applications "$STAGE/Applications"

DMG="build/Oriel-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Oriel $VERSION" -srcfolder "$STAGE" -format UDZO -quiet "$DMG"
echo "Created $DMG"
