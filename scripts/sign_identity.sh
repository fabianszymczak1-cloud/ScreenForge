#!/bin/bash
# Resolve a stable codesign identity for ScreenForge releases.
# Ad-hoc (`-`) embeds DR as raw CDHash → every rebuild invalidates Screen Recording TCC.
# "ScreenForge Release" (self-signed, local) embeds certificate-rooted DR so grants survive updates.
# This is NOT an Apple Developer ID — no paid account required.

resolve_screenforge_sign_identity() {
  if [[ -n "${SCREENFORGE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$SCREENFORGE_SIGN_IDENTITY"
    return 0
  fi
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq 'ScreenForge Release'; then
    printf '%s\n' "ScreenForge Release"
    return 0
  fi
  printf '%s\n' "-"
}

sign_screenforge_app() {
  local target="$1"
  local entitlements="${2:-}"
  local identity
  identity="$(resolve_screenforge_sign_identity)"

  if [[ "$identity" == "-" ]]; then
    echo "WARNING: signing ad-hoc (-). Screen Recording TCC will break on the next rebuild."
    echo "         Import Secrets/screenforge_release.p12 into the login keychain, or set SCREENFORGE_SIGN_IDENTITY."
  else
    echo "==> Codesign identity: $identity"
  fi

  local -a args=(--force --deep --sign "$identity" --options runtime)
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  fi
  codesign "${args[@]}" "$target"
  codesign --verify --deep --strict --verbose=2 "$target"
  echo "==> Designated requirement:"
  codesign -d -r- "$target" 2>&1 | sed -n 's/^.*designated => /designated => /p'
}
