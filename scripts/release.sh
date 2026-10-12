#!/usr/bin/env bash
# Builds a universal NotchBar.app and packages it as build/NotchBar-<version>.dmg.
#
#   scripts/release.sh 0.2.0
#
# Signing and notarization are optional and switch on when these are set:
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_KEY + NOTARY_KEY_ID + NOTARY_ISSUER  App Store Connect API key (.p8 path), or
#   NOTARY_PROFILE  a notarytool keychain profile (xcrun notarytool store-credentials), or
#   APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD  (app-specific password)
# Without them the DMG is ad-hoc signed and macOS will ask users to approve it in
# System Settings > Privacy & Security the first time.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>}"
VERSION="${VERSION#v}"
DMG="build/NotchBar-$VERSION.dmg"

VERSION="$VERSION" BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD)}" ./build.sh --universal

# dmgbuild lays out the install window (background, icon positions) without Finder
# scripting, so it also works on CI. It lives in a private virtualenv under build/.
VENV="build/.venv"
if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet "dmgbuild==1.6.5"
fi
# The first-open guide, under a name that says what it's for and with a large icon
# (Finder's shrunken preview of the guide would be unreadable).
GUIDE="build/If NotchBar won't open.png"
cp Resources/open-guide.png "$GUIDE"
swift scripts/set-icon.swift Resources/open-guide-icon.png "$GUIDE"

rm -f "$DMG"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app=build/NotchBar.app -D guide="$GUIDE" "NotchBar $VERSION" "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

  NOTARY_ARGS=()
  if [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  elif [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_PASSWORD")
  fi

  if (( ${#NOTARY_ARGS[@]} )); then
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
    echo "Signed and notarized."
  else
    echo "Signed but NOT notarized: set NOTARY_KEY/NOTARY_KEY_ID/NOTARY_ISSUER, NOTARY_PROFILE or APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD." >&2
  fi
else
  echo "Ad-hoc build: not signed with a Developer ID, so Gatekeeper will warn on first open." >&2
fi

(cd build && shasum -a 256 "$(basename "$DMG")") | tee "$DMG.sha256"
echo "Created $DMG"
