#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -resolvePackageDependencies -project Buckle.xcodeproj -scheme Buckle \
    -clonedSourcePackagesDirPath build/SourcePackages \
    -onlyUsePackageVersionsFromResolvedFile
