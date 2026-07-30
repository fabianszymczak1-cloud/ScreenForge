#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${1:-Release}"
VERSION="${SCREENFORGE_VERSION:-1.0.0}"
BUILD_NUMBER="${SCREENFORGE_BUILD:-1}"
DERIVED="$ROOT/build/DerivedData"
APP="$DERIVED/Build/Products/$CONFIG/ScreenForge.app"

echo "==> xcodegen"
xcodegen generate

echo "==> Building ScreenForge ($CONFIG) v$VERSION ($BUILD_NUMBER)"
xcodebuild \
  -scheme ScreenForge \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  build \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  MARKETING_VERSION="$VERSION"

if [[ ! -d "$APP" ]]; then
  echo "Build product missing: $APP"
  exit 1
fi

# Ad-hoc sign
codesign --force --deep --sign - "$APP"

echo "==> Built: $APP"
echo "$APP"
