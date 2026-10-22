#!/bin/bash
# Unit/integration tests plus the live smoke suite.
# Menu bar visibility and TCC state only exist in a running app, so both halves matter.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

DERIVED="$ROOT/build/DerivedData"
APP="${SCREENFORGE_SMOKE_APP:-/Applications/ScreenForge.app}"
# Non-sandboxed apps get the per-user Darwin temp dir, not /tmp.
REPORT="$(getconf DARWIN_USER_TEMP_DIR)screenforge-smoke-report.txt"
STATUS=0

echo "==> xcodegen"
xcodegen generate >/dev/null

echo "==> xcodebuild test"
# The test host is this menu-bar app. If WindowServer never hands XCTest a connection,
# xcodebuild waits forever — cap it so a wedged space cannot block a release overnight.
if python3 - "$DERIVED" <<'PY'
import os, signal, subprocess, sys
derived = sys.argv[1]
proc = subprocess.Popen(
    ["xcodebuild", "test", "-scheme", "ScreenForge", "-configuration", "Debug",
     "-derivedDataPath", derived, "-quiet"],
    start_new_session=True,
)
try:
    sys.exit(proc.wait(timeout=240))
except subprocess.TimeoutExpired:
    os.killpg(proc.pid, signal.SIGKILL)
    print("XCTest: TIMEOUT after 240s", flush=True)
    sys.exit(1)
PY
then
  echo "XCTest: PASSED"
else
  echo "XCTest: FAILED"
  STATUS=1
fi

echo "==> smoke suite ($APP)"
if [[ ! -x "$APP/Contents/MacOS/ScreenForge" ]]; then
  echo "Smoke: SKIPPED — missing $APP"
  STATUS=1
else
  rm -f "$REPORT"
  killall ScreenForge 2>/dev/null || true
  sleep 0.5
  # Build products carry the shipping bundle ID, so LaunchServices ends up with several
  # registrations for it and may resolve the smoke run to a copy we are not testing.
  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  for stale in "$DERIVED/Build/Products/Release/ScreenForge.app" \
               "$DERIVED/Build/Products/Debug/ScreenForge.app" \
               "$ROOT/build/dmg-stage/ScreenForge.app"; do
    [[ -d "$stale" ]] && "$LSREGISTER" -u "$stale" 2>/dev/null || true
  done
  "$LSREGISTER" -f "$APP" 2>/dev/null || true
  # Launch through LaunchServices: a raw binary is not a registered app instance and
  # StatusKit denies it a menu bar slot, which would fail the menu bar checks for no reason.
  open -a "$APP" --args --smoke-test
  for _ in $(seq 1 60); do
    [[ -f "$REPORT" ]] && break
    sleep 1
  done
  if [[ -f "$REPORT" ]]; then
    cat "$REPORT"
    grep -q '^RESULT=PASSED' "$REPORT" || STATUS=1
  else
    echo "Smoke: brak raportu po 60 s"
    STATUS=1
  fi
  killall ScreenForge 2>/dev/null || true
fi

echo "==> RESULT: $([[ $STATUS -eq 0 ]] && echo PASSED || echo FAILED)"
exit $STATUS
