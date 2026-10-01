#!/bin/zsh
# Package only. Use scripts/release.sh for Developer ID signing and notarization.
set -euo pipefail

if (( $# != 2 )); then
    print -u2 'Usage: scripts/package-dmg.sh /path/to/PrayBar.app /path/to/PrayBar.dmg'
    exit 2
fi
app_path=${1:A}
dmg_path=${2:a}
if [[ ! -d "$app_path" || "${app_path:t}" != PrayBar.app || "$dmg_path" != *.dmg ]]; then
    print -u2 'Expected a PrayBar.app bundle and a .dmg output path.'
    exit 2
fi
if [[ -e "$dmg_path" || -L "$dmg_path" ]]; then
    print -u2 "Output already exists: $dmg_path"
    exit 2
fi
codesign --verify --deep --strict "$app_path"
[[ -f "$app_path/Contents/Resources/LICENSE" ]]
[[ -f "$app_path/Contents/Resources/Adhan-LICENSE.txt" ]]

stage_dir=$(mktemp -d "${TMPDIR:-/tmp}/praybar-dmg.XXXXXX")
trap 'rm -rf -- "$stage_dir"' EXIT
ditto "$app_path" "$stage_dir/PrayBar.app"
ln -s /Applications "$stage_dir/Applications"
mkdir -p -- "${dmg_path:h}"
hdiutil create -volname PrayBar -fs HFS+ -format UDZO -srcfolder "$stage_dir" "$dmg_path"
hdiutil verify "$dmg_path"
print 'Packaged successfully. Sign and notarize the DMG before publishing it.'
