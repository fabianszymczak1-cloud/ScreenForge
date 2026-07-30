#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-Release}"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/ScreenForge.app"
DEST="/Applications/ScreenForge.app"
ENTITLEMENTS="$ROOT/ScreenForge/Resources/ScreenForge.entitlements"

sign_app() {
  local target="$1"
  if [[ -f "$ENTITLEMENTS" ]]; then
    codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$target" \
      || codesign --force --deep --sign - "$target"
  else
    codesign --force --deep --sign - "$target"
  fi
  codesign --verify --deep --strict --verbose=2 "$target"
}

"$ROOT/scripts/build_app.sh" "$CONFIG"

if [[ ! -d "$APP" ]]; then
  echo "Build product missing: $APP"
  exit 1
fi

echo "==> Quitting any running ScreenForge"
killall ScreenForge 2>/dev/null || true
sleep 0.3

echo "==> Installing to $DEST"
rm -rf "$DEST"
# ditto preserves resource forks better than cp -R; still re-sign after copy.
ditto "$APP" "$DEST"

echo "==> Re-sign installed app (avoids Sparkle Team ID mismatch after copy)"
sign_app "$DEST"

echo "==> Launching"
open "$DEST"

echo "==> Installed: $DEST"
echo "$DEST"
