#!/bin/bash
# Build a verified download. Publishing is a separate GitHub Actions step.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 || ! $1 =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ || ! $2 =~ ^[1-9][0-9]*$ ]]; then
  echo 'Usage: scripts/release.sh VERSION BUILD_NUMBER (for example: 1.0.1 2)' >&2
  exit 2
fi
version=$1
build_number=$2
: "${SIGNING_IDENTITY:?Set a Developer ID Application identity}"
: "${APPLE_TEAM_ID:?Set your Apple team ID}"
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || { echo 'Invalid Apple team ID.' >&2; exit 2; }
output=build/distribution
[[ ! -e "$output/PrayBar.dmg" ]] || { echo "Refusing to overwrite $output/PrayBar.dmg; move the previous output aside first." >&2; exit 2; }
mkdir -p "$output"
notary_args=(--keychain-profile "${NOTARY_PROFILE:-PrayBarNotary}")
if [[ -n ${NOTARY_KEYCHAIN_PATH:-} ]]; then
  notary_args+=(--keychain "$NOTARY_KEYCHAIN_PATH")
fi
requirement="anchor apple generic and certificate leaf[subject.OU] = \"$APPLE_TEAM_ID\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
{
  xcodebuild -version
  swift --version
  git rev-parse HEAD
} > "$output/build-environment.log"
xcodebuild -project PrayBar.xcodeproj -scheme PrayBar -configuration Release \
  -derivedDataPath build/automated-release -clonedSourcePackagesDirPath .build/xcode-packages \
  -onlyUsePackageVersionsFromResolvedFile \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS=--timestamp MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" build \
  > "$output/build.log" 2>&1 || { tail -80 "$output/build.log"; exit 1; }
git diff --exit-code -- Package.resolved PrayBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
app=build/automated-release/Build/Products/Release/PrayBar.app
codesign --verify --deep --strict -R="$requirement" "$app"
[[ $(lipo -archs "$app/Contents/MacOS/PrayBar") == arm64 ]]
python3 - "$app/Contents/Info.plist" "$version" "$build_number" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    p = plistlib.load(f)
assert p['CFBundleShortVersionString'] == sys.argv[2]
assert p['CFBundleVersion'] == sys.argv[3]
assert p['CFBundleIdentifier'] == 'dev.personal.PrayBar'
assert p['LSMinimumSystemVersion'] == '13.0'
PY
scripts/package-dmg.sh "$app" "$output/PrayBar.dmg"
codesign --sign "$SIGNING_IDENTITY" --timestamp --identifier dev.personal.PrayBar.dmg "$output/PrayBar.dmg"
codesign --verify --strict -R="$requirement" "$output/PrayBar.dmg"
# Keep the submission ID even if Apple's processing outlasts the bounded wait.
xcrun notarytool submit "$output/PrayBar.dmg" "${notary_args[@]}" --output-format json > "$output/notarization-submission.json"
submission_id=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$output/notarization-submission.json")
echo "Apple notarization submission: $submission_id"
wait_result=0
xcrun notarytool wait "$submission_id" "${notary_args[@]}" --timeout 45m --output-format json > "$output/notarization-status.json" || wait_result=$?
xcrun notarytool log "$submission_id" "${notary_args[@]}" "$output/notarization-log.json" || true
if [[ $wait_result != 0 ]]; then
  echo "Notarization did not complete successfully. Check submission $submission_id before submitting again." >&2
  exit 1
fi
python3 - "$output/notarization-status.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    result = json.load(f)
if result.get('status') != 'Accepted':
    sys.exit('Apple did not accept this build; publishing is blocked.')
PY
xcrun stapler staple "$output/PrayBar.dmg"
scripts/verify-release.sh "$output/PrayBar.dmg"
(cd "$output" && shasum -a 256 PrayBar.dmg > PrayBar.dmg.sha256)
cat > "$output/release-notes.md" <<NOTES
Requires **macOS 13 or later and Apple Silicon**.

Download **PrayBar.dmg**, open it, drag PrayBar to Applications, and launch it.
To update, quit PrayBar and replace the existing app; saved settings remain.

Signed with Developer ID and notarized by Apple. The SHA-256 checksum is in
PrayBar.dmg.sha256. Version $version, build $build_number.
NOTES
echo "Verified release files are in $output."
