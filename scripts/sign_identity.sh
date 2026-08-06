#!/bin/bash
# Release signing uses the self-signed "ScreenForge Release" certificate.
#
# Ad-hoc signing puts a bare cdhash in the designated requirement, so every rebuild is a
# different app to macOS: the Screen Recording grant dies and the Menu Bar allow-list entry
# stops matching, permanently, for that bundle ID. A certificate keeps the requirement stable
# across builds. (The 1.0.15 Sparkle crash blamed on this cert was library validation, fixed
# in 1.0.16 by the disable-library-validation entitlement.)
#
# Set SCREENFORGE_SIGN_IDENTITY to override, e.g. "-" for a throwaway ad-hoc build.

_SCREENFORGE_SIGN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_SCREENFORGE_SIGNING_KC="${SCREENFORGE_SIGNING_KEYCHAIN:-/tmp/screenforge-signing.keychain-db}"
_SCREENFORGE_SIGNING_KC_PASS="${SCREENFORGE_SIGNING_KEYCHAIN_PASSWORD:-screenforge-local}"

_screenforge_keychain_is_usable() {
  [[ -f "$_SCREENFORGE_SIGNING_KC" ]] || return 1
  security unlock-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC" 2>/dev/null || return 1
  security find-identity -v -p codesigning "$_SCREENFORGE_SIGNING_KC" 2>/dev/null | grep -Fq 'ScreenForge Release'
}

ensure_screenforge_signing_identity() {
  # An identity that merely exists is not enough: a keychain left over from an earlier run can
  # have a password nobody knows, and codesign then falls back to a GUI prompt that no password
  # satisfies. Import again whenever the keychain cannot be unlocked and used unattended.
  if _screenforge_keychain_is_usable; then
    return 0
  fi

  local p12="$_SCREENFORGE_SIGN_ROOT/Secrets/screenforge_release.p12"
  local pass_file="$_SCREENFORGE_SIGN_ROOT/Secrets/screenforge_release.p12.password"
  local p12_pass="${SCREENFORGE_P12_PASSWORD:-}"
  if [[ -z "$p12_pass" && -f "$pass_file" ]]; then
    p12_pass="$(tr -d '\n' < "$pass_file")"
  fi
  if [[ ! -f "$p12" || -z "$p12_pass" ]]; then
    return 1
  fi

  security delete-keychain "$_SCREENFORGE_SIGNING_KC" 2>/dev/null || true
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
  local identity="${SCREENFORGE_SIGN_IDENTITY:-ScreenForge Release}"
  if [[ "$identity" == "ScreenForge Release" ]] && ! ensure_screenforge_signing_identity; then
    echo "!! ScreenForge Release unavailable — falling back to ad-hoc." >&2
    echo "!! Ad-hoc builds lose Screen Recording and the menu bar slot on every update." >&2
    identity="-"
  fi
  printf '%s\n' "$identity"
}

# Sign nested Mach-O / bundles inside-out so Sparkle matches the main binary identity.
_sign_nested() {
  local root="$1"
  local identity="$2"
  shift 2
  local -a keychain_args=("$@")
  local path
  while IFS= read -r path; do
    [[ -e "$path" ]] || continue
    echo "  nest-sign: $path"
    codesign --force --sign "$identity" "${keychain_args[@]}" --timestamp=none "$path"
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

  # Pin the keychain: the same identity also sits in the login keychain, where using the private
  # key triggers a GUI password prompt that cannot be answered unattended.
  local -a keychain_args=()
  if [[ "$identity" != "-" && -f "$_SCREENFORGE_SIGNING_KC" ]]; then
    security unlock-keychain -p "$_SCREENFORGE_SIGNING_KC_PASS" "$_SCREENFORGE_SIGNING_KC" 2>/dev/null || true
    keychain_args=(--keychain "$_SCREENFORGE_SIGNING_KC")
  fi

  if [[ "$identity" == "-" ]]; then
    echo "==> Codesign identity: ad-hoc (-)"
  else
    echo "==> Codesign identity: $identity"
  fi

  echo "==> Nest-sign frameworks/helpers"
  _sign_nested "$target" "$identity" "${keychain_args[@]}"

  local -a args=(--force --deep --sign "$identity" "${keychain_args[@]}" --timestamp=none)
  if [[ -n "$entitlements" && -f "$entitlements" ]]; then
    args+=(--entitlements "$entitlements")
  fi
  codesign "${args[@]}" "$target"
  codesign --verify --deep --strict --verbose=2 "$target"
  echo "==> Designated requirement:"
  local requirement
  requirement="$(codesign -d -r- "$target" 2>&1 | sed -n 's/^.*designated => /designated => /p')"
  echo "$requirement"
  if [[ "$identity" != "-" && "$requirement" != *certificate* ]]; then
    echo "!! Requirement is not certificate-based — this build would lose its permissions and menu bar slot on the next update." >&2
    return 1
  fi
  if codesign -d --entitlements - "$target" 2>/dev/null | grep -Fq 'disable-library-validation'; then
    echo "==> library-validation: disabled (Sparkle OK)"
  fi
}
