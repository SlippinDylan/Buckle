#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 2 ]]; then
    echo 'Usage: Scripts/prepare-update.sh <dedicated-archives-directory> <https-download-directory>' >&2
    echo 'Requires SPARKLE_ED_PRIVATE_KEY and SPARKLE_PUBLIC_KEY. Generates files; does not publish.' >&2
    exit 64
fi
archives_directory="$1"
download_directory="$2"
test -d "$archives_directory"
tools='build/SourcePackages/artifacts/sparkle/Sparkle/bin'
test -x "$tools/generate_appcast"
: "${SPARKLE_ED_PRIVATE_KEY:?Missing SPARKLE_ED_PRIVATE_KEY}"
: "${SPARKLE_PUBLIC_KEY:?Missing SPARKLE_PUBLIC_KEY}"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | node .github/scripts/update-key.mjs
# Reject ambiguous URL syntax before normalization; filenames resolve relative to this directory.
download_directory="$(node --input-type=module - "$download_directory" <<'JS'
const value = process.argv[2];
try {
  if (!/^https:\/\/[^/]/.test(value) || /[\s\u0000-\u001f\u007f\\?#]/u.test(value) || /^https:\/\/[^/]*@/.test(value)) throw Error();
  const url = new URL(value);
  if (!url.hostname || url.port === '0') throw Error();
  if (!url.pathname.endsWith('/')) url.pathname += '/';
  console.log(url.href);
} catch {
  console.error('Expected a valid HTTPS download directory without credentials, query or fragment.');
  process.exit(64);
}
JS
)"
feed_directory=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/buckle-feed.XXXXXX")
trap 'rm -rf "$feed_directory"' EXIT
candidate_feed="$feed_directory/appcast.xml"
if [[ -f "$archives_directory/appcast.xml" ]]; then
    printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tools/sign_update" \
        --verify --ed-key-file - "$archives_directory/appcast.xml"
    cp "$archives_directory/appcast.xml" "$candidate_feed"
fi
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tools/generate_appcast" \
    --ed-key-file - --download-url-prefix "$download_directory" \
    --embed-release-notes --maximum-deltas 0 --maximum-versions 3 \
    --link https://github.com/SlippinDylan/Buckle \
    -o "$candidate_feed" "$archives_directory"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tools/sign_update" \
    --ed-key-file - "$candidate_feed"
printf '%s' "$SPARKLE_ED_PRIVATE_KEY" | "$tools/sign_update" \
    --verify --ed-key-file - "$candidate_feed"
xmllint --noout "$candidate_feed"
if [[ -f "$archives_directory/appcast.xml" ]]; then
    python3 Scripts/update_feed.py "$candidate_feed" --previous "$archives_directory/appcast.xml"
else
    python3 Scripts/update_feed.py "$candidate_feed"
fi
cp "$candidate_feed" "$archives_directory/appcast.xml"
