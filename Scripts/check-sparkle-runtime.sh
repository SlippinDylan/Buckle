#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/Checks
probe_directory=$(mktemp -d "$PWD/build/Checks/sparkle-runtime.XXXXXX")
trap 'rm -rf "$probe_directory"' EXIT
# A signature can verify while dyld still rejects its frameworks. Exercise the Release signing contract.
python3 - <<'PY'
from pathlib import Path
import re
settings = dict(re.findall(r'^(CODE_SIGN_IDENTITY|ENABLE_HARDENED_RUNTIME)\s*=\s*(.*?)\s*$',
                           Path('Config/Release.xcconfig').read_text(), re.MULTILINE))
assert settings == {'CODE_SIGN_IDENTITY': '-', 'ENABLE_HARDENED_RUNTIME': 'YES'}
PY
ditto build/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
    "$probe_directory/Sparkle.framework"
cat > "$probe_directory/main.swift" <<'SWIFT'
import Sparkle
print("Release signing permits loading \(SPUUpdater.self). No updater or application UI was started.")
SWIFT
xcrun swiftc -target "$(uname -m)-apple-macos15.0" "$probe_directory/main.swift" \
    -F "$probe_directory" -Xlinker -rpath -Xlinker "$probe_directory" -o "$probe_directory/probe"
codesign --force --sign - --options runtime --entitlements App/Buckle.entitlements "$probe_directory/probe"
"$probe_directory/probe"
