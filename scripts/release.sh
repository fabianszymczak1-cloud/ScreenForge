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
DMG_NAME="ScreenForge-${VERSION}.dmg"
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

# Gate: unit tests plus the smoke suite against the build already in /Applications.
if [[ "${SKIP_TESTS:-0}" != "1" ]]; then
  "$ROOT/scripts/run_tests.sh"
fi

"$ROOT/scripts/make_dmg.sh" "$VERSION"
DMG="$ROOT/build/dmg/$DMG_NAME"
if [[ ! -f "$DMG" ]]; then
  echo "Expected DMG missing: $DMG"
  exit 1
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
- Rectangles and ellipses can be rotated from the handle above the selection; hold Shift to snap to 15°.
- Fixed a crash when picking a window to capture: the selection overlays were released twice, so the app died in the next autorelease pool drain.
- Closed the same latent double-release in the countdown panel, the notification panel and the history window.
- Window capture no longer gives up when macOS refuses to stream the first window it finds: helper and system windows are ranked below real ones, degenerate results are rejected, and a failed stream is retried.
- Fixed display geometry reporting points where pixels were expected on Retina screens. "All displays" was stitched at half resolution, and "capture last region" silently refused any region in the right or bottom half of a screen.
- The smoke suite now drives both pickers, the countdown, the notification panel and the history/settings windows through a full open/close round trip, and checks every capture is a plausible size.
- Signed with a stable certificate instead of ad-hoc. Ad-hoc put a bare cdhash in the designated requirement, so every update looked like a different app: the Screen Recording grant died and the Menu Bar allow-list entry stopped matching for good. Measured: a certificate-signed app keeps its menu bar slot across a rebuild with a completely different cdhash; the ad-hoc one never does.
- Bundle ID app.screenforge.mac — a final identity, because the previous ones were burned by ad-hoc rebuilds and no reset, toggle or reinstall revives them.
- Grant **Screen Recording** with **Request permission** in the app (system sheet). Do **not** add via Settings “+”.
- Updating from an older build leaves a dead Screen Recording entry that silently blocks the system sheet; ScreenForge now detects that, clears it and asks again automatically.
- On launch ScreenForge verifies the icon is really rendered — not just created — and recovers by re-creating the item and reloading Control Center when an update left a stale binding.
- Open only \`/Applications/ScreenForge.app\`
- After launch, ScreenForge must appear under System Settings → Menu Bar → Allow in the Menu Bar (turn ON)
- If still missing: \`python3 scripts/fix_menubar_allowlist.py\` (Terminal may need Full Disk Access), or Reset Control Center…
- Ad-hoc signed (same as PasteRush)
- First launch may require **Privacy & Security → Open Anyway**
- Or: \`xattr -dr com.apple.quarantine /Applications/ScreenForge.app\`
- See README → *macOS security warning* for details
EOF
)"

echo "==> Creating GitHub release $TAG"
# Versioned DMG for Safari (no overwrite) + stable ScreenForge.dmg for README latest/download link.
STABLE_DMG="$ROOT/build/dmg/ScreenForge.dmg"
if [[ ! -f "$STABLE_DMG" ]]; then
  cp -f "$DMG" "$STABLE_DMG"
fi
gh release create "$TAG" \
  --repo "$REPO" \
  --title "ScreenForge $VERSION" \
  --notes "$NOTES" \
  "$DMG" \
  "$STABLE_DMG" \
  "$APPCAST"

echo "==> Done: https://github.com/${REPO}/releases/tag/${TAG}"
