#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-${SCREENFORGE_VERSION:-1.0.0}}"
export SCREENFORGE_VERSION="$VERSION"
export SCREENFORGE_BUILD="${SCREENFORGE_BUILD:-$VERSION}"

"$ROOT/Scripts/build_app.sh" Release

APP="$ROOT/build/DerivedData/Build/Products/Release/ScreenForge.app"
STAGE="$ROOT/build/dmg-stage"
DMG_DIR="$ROOT/build/dmg"
DMG="$DMG_DIR/ScreenForge.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" "$DMG_DIR"
cp -R "$APP" "$STAGE/ScreenForge.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "ScreenForge" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG"
echo "==> DMG: $DMG"
echo "$DMG"
