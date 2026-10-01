#!/bin/bash
# Verify both the container and its exact payload, without launching the app.
set -euo pipefail
[[ $# == 1 && -f $1 ]] || { echo 'Usage: scripts/verify-release.sh PrayBar.dmg' >&2; exit 2; }
: "${APPLE_TEAM_ID:?Set your Apple team ID}"
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || exit 2
requirement="anchor apple generic and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
codesign --verify --strict -R="$requirement" "$1"
xcrun stapler validate "$1"
spctl --assess --type open --context context:primary-signature --verbose=2 "$1"
mount_path=$(mktemp -d "${TMPDIR:-/tmp}/praybar-verify.XXXXXX")
mounted=false
cleanup() {
  if [[ $mounted == true ]]; then hdiutil detach "$mount_path"; fi
  rmdir "$mount_path"
}
trap cleanup EXIT
hdiutil attach "$1" -readonly -nobrowse -mountpoint "$mount_path"
mounted=true
codesign --verify --deep --strict -R="$requirement" "$mount_path/PrayBar.app"
spctl --assess --type execute --verbose=2 "$mount_path/PrayBar.app"
[[ $(readlink "$mount_path/Applications") == /Applications ]]
[[ -f "$mount_path/PrayBar.app/Contents/Resources/LICENSE" ]]
[[ -f "$mount_path/PrayBar.app/Contents/Resources/Adhan-LICENSE.txt" ]]
