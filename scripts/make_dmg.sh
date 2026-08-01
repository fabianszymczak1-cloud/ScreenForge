#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=sign_identity.sh
source "$ROOT/scripts/sign_identity.sh"

VERSION="${1:-${SCREENFORGE_VERSION:-1.0.0}}"
export SCREENFORGE_VERSION="$VERSION"
export SCREENFORGE_BUILD="${SCREENFORGE_BUILD:-$VERSION}"
ENTITLEMENTS="$ROOT/ScreenForge/Resources/ScreenForge.entitlements"

"$ROOT/scripts/build_app.sh" Release

APP="$ROOT/build/DerivedData/Build/Products/Release/ScreenForge.app"
STAGE="$ROOT/build/dmg-stage"
DMG_DIR="$ROOT/build/dmg"
DMG="$DMG_DIR/ScreenForge-${VERSION}.dmg"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup_noncanonical_apps() {
  echo "==> Quit ScreenForge + eject DMG volumes + unregister build copies"
  killall ScreenForge 2>/dev/null || true
  sleep 0.2
  for vol in /Volumes/ScreenForge*; do
    if [[ -d "$vol" ]]; then
      hdiutil detach "$vol" -force 2>/dev/null || true
    fi
  done
  if [[ -x "$LSREGISTER" ]]; then
    [[ -d "$APP" ]] && "$LSREGISTER" -u "$APP" 2>/dev/null || true
    [[ -d "$STAGE/ScreenForge.app" ]] && "$LSREGISTER" -u "$STAGE/ScreenForge.app" 2>/dev/null || true
  fi
}

rm -rf "$STAGE" "$DMG_DIR/ScreenForge-${VERSION}.dmg" "$DMG_DIR/ScreenForge.dmg"
mkdir -p "$STAGE" "$DMG_DIR"
ditto "$APP" "$STAGE/ScreenForge.app"

# Re-sign after copy so Sparkle nested binaries stay consistent with the main binary.
sign_screenforge_app "$STAGE/ScreenForge.app" "$ENTITLEMENTS"

ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "ScreenForge" -srcfolder "$STAGE" -ov -format UDZO -imagekey zlib-level=9 "$DMG"
# Convenience copy for scripts that still expect the unversioned name.
cp -f "$DMG" "$DMG_DIR/ScreenForge.dmg"

cleanup_noncanonical_apps

echo "==> DMG: $DMG"
echo "$DMG"
