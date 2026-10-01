#!/bin/bash
# GitHub-hosted macOS runner only; never run with shell tracing enabled.
set -euo pipefail
: "${GITHUB_ACTIONS:?Run this only on a GitHub-hosted runner}"
: "${RUNNER_TEMP:?}"
: "${SIGNING_CERTIFICATE_P12:?Missing release environment secret}"
: "${SIGNING_CERTIFICATE_PASSWORD:?Missing release environment secret}"
: "${NOTARIZATION_PASSWORD:?Missing release environment secret}"
: "${APPLE_ID:?Missing release environment variable}"
: "${APPLE_TEAM_ID:?Missing release environment variable}"
umask 077
certificate_path="$RUNNER_TEMP/praybar-signing.p12"
keychain_path="$RUNNER_TEMP/praybar-signing.keychain-db"
trap 'rm -f "$certificate_path"' EXIT
keychain_password=$(openssl rand -hex 32)
printf '::add-mask::%s\n' "$keychain_password"
printf '%s' "$SIGNING_CERTIFICATE_P12" | base64 --decode > "$certificate_path"
security create-keychain -p "$keychain_password" "$keychain_path"
security set-keychain-settings -lut 7200 "$keychain_path"
security unlock-keychain -p "$keychain_password" "$keychain_path"
security import "$certificate_path" -k "$keychain_path" -P "$SIGNING_CERTIFICATE_PASSWORD" -T /usr/bin/codesign > /dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain_path" > /dev/null
security list-keychains -d user -s "$keychain_path"
xcrun notarytool store-credentials PrayBarCI --keychain "$keychain_path" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$NOTARIZATION_PASSWORD"
