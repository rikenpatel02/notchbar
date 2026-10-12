#!/usr/bin/env bash
# Installs or updates NotchBar from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/rikenpatel02/notchbar/main/install.sh | bash
#
# Downloads the DMG, checks it against the release's SHA-256 checksum, copies
# NotchBar.app into /Applications and opens it.
set -euo pipefail

REPO="rikenpatel02/notchbar"
APP="/Applications/NotchBar.app"

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "NotchBar runs on macOS only."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 13 )) || fail "NotchBar needs macOS 13 or later (this Mac has $(sw_vers -productVersion))."

say "Finding the latest release"
RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")" || fail "Couldn't reach GitHub."
DMG_URL="$(printf '%s' "$RELEASE_JSON" | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')"
TAG="$(printf '%s' "$RELEASE_JSON" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')"
[[ -n "$DMG_URL" ]] || fail "The latest release has no DMG."

TMP="$(mktemp -d)"
MOUNT=""
cleanup() {
  [[ -n "$MOUNT" ]] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true
  rm -rf "$TMP"
}
trap cleanup EXIT

DMG="$TMP/$(basename "$DMG_URL")"
say "Downloading NotchBar $TAG"
curl -fL --progress-bar "$DMG_URL" -o "$DMG"
curl -fsSL "$DMG_URL.sha256" -o "$DMG.sha256" || fail "Couldn't download the checksum."

say "Verifying checksum"
EXPECTED="$(awk '{print $1}' "$DMG.sha256")"
ACTUAL="$(shasum -a 256 "$DMG" | awk '{print $1}')"
[[ -n "$EXPECTED" && "$EXPECTED" == "$ACTUAL" ]] || fail "Checksum mismatch; the download may be corrupted. Nothing was installed."

say "Installing to /Applications"
MOUNT="$(hdiutil attach -nobrowse -readonly "$DMG" | tail -1 | cut -f3)"
[[ -d "$MOUNT/NotchBar.app" ]] || fail "The disk image doesn't contain NotchBar.app."
pkill -x NotchBar 2>/dev/null && sleep 1 || true
if [[ -w /Applications ]]; then
  rm -rf "$APP"
  ditto "$MOUNT/NotchBar.app" "$APP"
else
  say "Administrator password needed to write to /Applications"
  sudo rm -rf "$APP"
  sudo ditto "$MOUNT/NotchBar.app" "$APP"
fi

say "Opening NotchBar"
open "$APP"
printf '\nNotchBar %s is installed. Look for it in the menu bar; the setup window walks you through connecting Claude Code.\n' "$TAG"
