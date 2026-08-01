#!/bin/bash
# Resolve a stable codesign identity for ScreenForge releases.
# Ad-hoc (`-`) embeds DR as raw CDHash → every rebuild invalidates Screen Recording TCC.
# "ScreenForge Release" (self-signed, local) embeds certificate-rooted DR so grants survive updates.
# This is NOT an Apple Developer ID — no paid account required.

_SCREENFORGE_SIGN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SCREENFORGE_SIGNING_KC="${SCREENFORGE_SIGNING_KEYCHAIN:-/tmp/screenforge-signing.keychain-db}"
_SCREENFORGE_SIGNING_KC_PASS="${SCREENFORGE_SIGNING_KEYCHAIN_PASSWORD:-screenforge-local}"

ensure_screenforge_signing_identity() {
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq 'ScreenForge Release'; then
    if [[ -f "$_SCREENFORGE_SIGNING_KC" ]]; then
      security unlock-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC" 2>/dev/null || true
    fi
    return 0
  fi

  local p12="$_SCREENFORGE_SIGN_ROOT/Secrets/screenforge_release.p12"
  local pass_file="$_SCREENFORGE_SIGN_ROOT/Secrets/screenforge_release.p12.password"
  local p12_pass="${SCREENFORGE_P12_PASSWORD:-}"
  if [[ -z "$p12_pass" && -f "$pass_file" ]]; then
    p12_pass="$(tr -d '\n' < "$pass_file")"
  fi
  if [[ ! -f "$p12" ]]; then
    return 1
  fi
  if [[ -z "$p12_pass" ]]; then
    echo "WARNING: $p12 present but no password (set SCREENFORGE_P12_PASSWORD or Secrets/screenforge_release.p12.password)"
    return 1
  fi

  rm -f "$_SCREENFORGE_SIGNING_KC"
  security create-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC" >/dev/null
  security set-keychain-settings -lut 21600 "$_SCREENFORGE_SIGNING_KC" >/dev/null
  security unlock-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC"
  security import "$p12" -k "$_SCREENFORGE_SIGNING_KC" -P "$p12_pass" \
    -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$_SCREENFORGE_SIGNING_KC_PASS" \
    "$_SCREENFORGE_SIGNING_KC" >/dev/null

  local login="$HOME/Library/Keychains/login.keychain-db"
  if [[ -f "$login" ]]; then
    security list-keychains -d user -s "$_SCREENFORGE_SIGNING_KC" "$login"
  else
    security list-keychains -d user -s "$_SCREENFORGE_SIGNING_KC"
  fi
  security unlock-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC"
  security find-identity -v -p codesigning "$_SCREENFORGE_SIGNING_KC" | grep -Fq 'ScreenForge Release'
}

resolve_screenforge_sign_identity() {
  if [[ -n "${SCREENFORGE_SIGN_IDENTITY:-}" ]]; then
    printf '%s\n' "$SCREENFORGE_SIGN_IDENTITY"
    return 0
  fi
  ensure_screenforge_signing_identity || true
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq 'ScreenForge Release'; then
    printf '%s\n' "ScreenForge Release"
    return 0
  fi
  printf '%s\n' "-"
}

# Sign nested Mach-O / bundles inside-out so Sparkle matches the main binary identity.
# Hardened runtime rejects Sparkle when Team IDs differ (self-signed main vs leftover nested sig).
_sign_nested() {
  local root="$1"
  local identity="$2"
  local path
  # Deepest first: XPC → appex → frameworks → helper apps
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    echo "  nest-sign: $path"
    codesign --force --sign "$identity" --options runtime --timestamp=none "$path"
  done < <(
    find "$root" \( -name '*.xpc' -o -name '*.appex' -o -name '*.framework' -o -name '*.app' \) \
      ! -path "$root" \
      -print 2>/dev/null | awk '{ print length, $0 }' | sort -nr | cut -d' ' -f2-
  )
}

sign_screenforge_app() {
  local target="$1"
  local entitlements="${2:-}"
  local identity
  identity="$(resolve_screenforge_sign_identity)"

  if [[ -f "$_SCREENFORGE_SIGNING_KC" ]]; then
    security unlock-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC" 2>/dev/null || true
  fi

  if [[ "$identity" == "-" ]]; then
    echo "WARNING: signing ad-hoc (-). Screen Recording TCC will break on the next rebuild."
    echo "         Place Secrets/screenforge_release.p12 (+ .password) or set SCREENFORGE_SIGN_IDENTITY."
  else
    echo "==> Codesign identity: $identity"
  fi

  echo "==> Nest-sign frameworks/helpers"
  _sign_nested "$target" "$identity"

  local -a args=(--force --deep --sign "$identity" --options runtime --timestamp=none)
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  fi
  codesign "${args[@]}" "$target"
  codesign --verify --deep --strict --verbose=2 "$target"
  echo "==> Designated requirement:"
  codesign -d -r- "$target" 2>&1 | sed -n 's/^.*designated => /designated => /p'
  # Entitlements must include disable-library-validation when embedding Sparkle under a custom identity.
  if codesign -d --entitlements - "$target" 2>/dev/null | grep -Fq 'disable-library-validation'; then
    echo "==> library-validation: disabled (Sparkle OK)"
  else
    echo "WARNING: com.apple.security.cs.disable-library-validation missing — Sparkle may fail to load"
  fi
}
