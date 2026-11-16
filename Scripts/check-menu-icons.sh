#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Checks
probe_directory=$(mktemp -d "$PWD/build/Checks/menu-icons.XXXXXX")
trap 'rm -rf "$probe_directory"' EXIT
python3 - <<'PYSETTINGS'
import json
import subprocess

objects = json.loads(subprocess.check_output([
    'plutil', '-convert', 'json', '-o', '-', 'Buckle.xcodeproj/project.pbxproj',
]))['objects']
target = next(value for value in objects.values()
              if value.get('isa') == 'PBXNativeTarget' and value.get('name') == 'Buckle')
for identifier in objects[target['buildConfigurationList']]['buildConfigurations']:
    settings = objects[identifier]['buildSettings']
    assert settings['ASSETCATALOG_COMPILER_APPICON_NAME'] == 'Buckle'
    assert settings['ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS'] == 'YES'
PYSETTINGS
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/Core/FinderIntegration.swift App/FinderMenuIcon.swift Tests/FinderMenuIconCheck.swift \
    -o "$probe_directory/check"
for target in extension main; do
    icon_bundle="$probe_directory/$target.bundle"
    mkdir -p "$icon_bundle/Contents/Resources"
    python3 - "$icon_bundle/Contents/Info.plist" <<'PYINFO'
import plistlib
import sys
from pathlib import Path

Path(sys.argv[1]).write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'studio.slippindylan.Buckle.MenuIconCheck',
    'CFBundlePackageType': 'BNDL',
}))
PYINFO
    icon_arguments=(App/Resources/FinderIcons/*.icon)
    if [[ "$target" == main ]]; then
        icon_arguments+=(Buckle.icon --app-icon Buckle --include-all-app-icons
            --output-partial-info-plist "$probe_directory/primary-icon.plist")
    fi
    xcrun actool "${icon_arguments[@]}" \
        --compile "$icon_bundle/Contents/Resources" --platform macosx \
        --minimum-deployment-target 15.0 --target-device mac \
        --output-format human-readable-text --warnings --notices
    "$probe_directory/check" "$icon_bundle"
done
