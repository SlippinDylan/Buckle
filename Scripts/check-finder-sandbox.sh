#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Checks
probe_directory=$(mktemp -d "$PWD/build/Checks/finder-sandbox.XXXXXX")
trap 'rm -rf "$probe_directory"' EXIT
python3 - "$probe_directory/Info.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'wb') as output:
    plistlib.dump({
        'CFBundleIdentifier': 'studio.slippindylan.Buckle.FinderSandboxCheck',
        'CFBundleName': 'FinderSandboxCheck',
        'CFBundleVersion': '1',
    }, output)
PY
xcrun swiftc -parse-as-library -swift-version 6 \
    App/Core/FinderIntegration.swift Tests/FinderSandboxCheck.swift \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$probe_directory/Info.plist" \
    -o "$probe_directory/probe"
codesign --force --sign - --entitlements FinderExtension/BuckleFinder.entitlements "$probe_directory/probe"
python3 - "$probe_directory/probe" <<'PY'
from pathlib import Path
import subprocess
import sys
import uuid

directory = Path.home() / 'Library/Application Support/Buckle/Finder'
existed = directory.exists()
directory.mkdir(parents=True, exist_ok=True)
probe = directory / ('probe-' + str(uuid.uuid4()) + '.txt')
try:
    probe.write_text('Buckle sandbox probe')
    subprocess.run([sys.argv[1], probe.name], check=True)
finally:
    probe.unlink()
    if not existed:
        directory.rmdir()
PY
