#!/bin/bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
    echo 'Usage: Scripts/create-dmg.sh <Buckle.app> <output.dmg>' >&2
    exit 64
fi
app_path="$1"
dmg_path="$2"
test -x "$app_path/Contents/MacOS/Buckle"
case "$dmg_path" in *.dmg) ;; *) echo 'Output must end in .dmg.' >&2; exit 64 ;; esac
bash "$(dirname "$0")/verify-bundle.sh" --distribution "$app_path"
temporary_root="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/buckle-dmg.XXXXXX")"
trap 'rm -rf "$temporary_root"' EXIT
mkdir -p "$temporary_root/contents" "$(dirname "$dmg_path")"
ditto "$app_path" "$temporary_root/contents/Buckle.app"
ln -s /Applications "$temporary_root/contents/Applications"
hdiutil create -volname Buckle -srcfolder "$temporary_root/contents" -format UDZO -ov "$dmg_path"
