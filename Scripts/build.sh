#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
case "$configuration" in Debug|Release) ;; *) echo 'Use Debug or Release.' >&2; exit 64 ;; esac
node .github/scripts/sync-version.mjs
xcodebuild build -project Buckle.xcodeproj -scheme Buckle \
    -configuration "$configuration" -destination 'generic/platform=macOS' \
    -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
    -onlyUsePackageVersionsFromResolvedFile
bash Scripts/verify-bundle.sh "build/DerivedData/Build/Products/$configuration/Buckle.app"
echo "build/DerivedData/Build/Products/$configuration/Buckle.app"
