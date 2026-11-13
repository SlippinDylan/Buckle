#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node .github/scripts/sync-version.mjs --check
swift test
bash Scripts/check-finder-sandbox.sh
bash Scripts/resolve-dependencies.sh
bash Scripts/check-sparkle-runtime.sh
xcrun swiftc -typecheck -parse-as-library -swift-version 6 \
    -F build/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64 \
    -target "$(uname -m)-apple-macos15.0" App/*.swift App/Core/*.swift
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -application-extension \
    -target "$(uname -m)-apple-macos15.0" FinderExtension/FinderSync.swift App/Core/FinderIntegration.swift App/Localization.swift
mkdir -p build/Checks
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/MemoryMonitor.swift App/Core/MemoryPolicy.swift Tests/MemoryReaderCheck.swift \
    -o build/Checks/memory-reader
build/Checks/memory-reader
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/MemoryMonitor.swift App/Core/MemoryPolicy.swift Tests/MemoryTimerCheck.swift -o build/Checks/memory-timer
build/Checks/memory-timer
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/MouseResetController.swift App/Core/ApplicationLifecycle.swift App/Localization.swift \
    App/SystemMemoryPanel.swift App/ApplicationRecovery.swift Tests/MouseResetCheck.swift \
    -o build/Checks/mouse-reset
build/Checks/mouse-reset
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/SystemMemoryPanel.swift App/Core/ApplicationLifecycle.swift App/Localization.swift Tests/SystemMemoryPanelCheck.swift \
    -o build/Checks/system-memory-panel
build/Checks/system-memory-panel
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/AirDropService.swift App/Localization.swift Tests/AirDropCheck.swift -o build/Checks/airdrop
build/Checks/airdrop
xcrun swift-format lint --strict --recursive App FinderExtension Tests Package.swift Scripts/generate-icon.swift
python3 Scripts/check-localizations.py
node --test .github/scripts/*.test.mjs
for script in Scripts/*.sh; do bash -n "$script"; done
plutil -lint App/Info.plist App/Buckle.entitlements FinderExtension/Info.plist FinderExtension/BuckleFinder.entitlements Buckle.xcodeproj/project.pbxproj
git diff --check
