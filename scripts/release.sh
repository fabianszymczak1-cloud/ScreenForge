#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:?usage: release.sh <version> e.g. 1.0.0}"
export SCREENFORGE_VERSION="$VERSION"
export SCREENFORGE_BUILD="${SCREENFORGE_BUILD:-$VERSION}"
TAG="v$VERSION"

# Prefer PasteRush / local Sparkle tools, then SPM artifacts after resolve
SIGN_UPDATE=""
for c in \
  "$ROOT/build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
  "$HOME/Desktop/Projekty/ditto copy/PasteRush/.build/artifacts/sparkle/Sparkle/bin/sign_update"
do
  if [[ -x "$c" ]]; then SIGN_UPDATE="$c"; break; fi
done

PRIVATE_KEY="${SPARKLE_PRIVATE_KEY_FILE:-$ROOT/Secrets/sparkle_eddsa_private.key}"
BMC="https://buymeacoffee.com/5r8nffw85nw"
REPO="fabianszymczak1-cloud/ScreenForge"
DMG_NAME="ScreenForge.dmg"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${DMG_NAME}"

if [[ ! -f "$PRIVATE_KEY" ]]; then
  echo "Missing private key at $PRIVATE_KEY"
  echo "Set SPARKLE_PRIVATE_KEY_FILE or create Secrets/sparkle_eddsa_private.key"
  exit 1
fi
if [[ -z "$SIGN_UPDATE" ]]; then
  echo "sign_update not found. Build once so SPM downloads Sparkle, or point to PasteRush Sparkle bin."
  exit 1
fi

"$ROOT/Scripts/make_dmg.sh" "$VERSION"
DMG="$ROOT/build/dmg/ScreenForge.dmg"

# Optional smoke
if [[ -x "$ROOT/build/DerivedData/Build/Products/Release/ScreenForge.app/Contents/MacOS/ScreenForge" ]]; then
  echo "==> Smoke test"
  "$ROOT/build/DerivedData/Build/Products/Release/ScreenForge.app/Contents/MacOS/ScreenForge" --smoke-test || true
fi

echo "==> Signing update with Sparkle"
SIGNATURE_LINE="$("$SIGN_UPDATE" -f "$PRIVATE_KEY" "$DMG")"
ED_SIG="$(echo "$SIGNATURE_LINE" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
LENGTH="$(echo "$SIGNATURE_LINE" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [[ -z "$ED_SIG" || -z "$LENGTH" ]]; then
  echo "Failed to parse sign_update output: $SIGNATURE_LINE"
  exit 1
fi

PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"
APPCAST="$ROOT/build/dmg/appcast.xml"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>ScreenForge</title>
    <link>https://github.com/${REPO}/releases</link>
    <description>ScreenForge updates</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        length="${LENGTH}"
        type="application/octet-stream"
        sparkle:edSignature="${ED_SIG}" />
      <description><![CDATA[
        <h2>ScreenForge ${VERSION}</h2>
        <p>Local screenshot capture and annotation for macOS.</p>
        <p><a href="${BMC}">Buy Me a Coffee</a></p>
      ]]></description>
    </item>
  </channel>
</rss>
XML

NOTES="$(cat <<EOF
## ScreenForge ${VERSION}

Local screenshot capture & annotation for macOS. No account. No cloud. No telemetry.

### Download
- [${DMG_NAME}](${DOWNLOAD_URL})

### Support
If ScreenForge helps you: [Buy Me a Coffee](${BMC})

### Notes
- macOS 26+
- Grant **Screen Recording** on first launch
- First launch may require **Privacy & Security → Open Anyway** (ad-hoc signed build)
- Or: \`xattr -dr com.apple.quarantine /Applications/ScreenForge.app\`
- See README → *macOS security warning* for details
EOF
)"

echo "==> Creating GitHub release $TAG"
gh release create "$TAG" \
  --repo "$REPO" \
  --title "ScreenForge $VERSION" \
  --notes "$NOTES" \
  "$DMG" \
  "$APPCAST"

echo "==> Done: https://github.com/${REPO}/releases/tag/${TAG}"
