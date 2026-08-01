#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# shellcheck source=sign_identity.sh
source "$ROOT/scripts/sign_identity.sh"

CONFIG="${1:-Release}"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/ScreenForge.app"
DEST="/Applications/ScreenForge.app"
ENTITLEMENTS="$ROOT/ScreenForge/Resources/ScreenForge.entitlements"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

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
ditto "$APP" "$DEST"

echo "==> Re-sign installed app"
sign_screenforge_app "$DEST" "$ENTITLEMENTS"

if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -u "$APP" 2>/dev/null || true
fi

echo "==> Installed: $DEST (not launched)"
echo "$DEST"
