#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
node .github/scripts/sync-version.mjs --check
node .github/scripts/release-notes.mjs --check
swift test
swift build --product BucklePermissionSupport
permission_support_bin=$(swift build --show-bin-path)
bash Scripts/check-finder-sandbox.sh
bash Scripts/resolve-dependencies.sh
bash Scripts/check-sparkle-runtime.sh
xcrun swiftc -typecheck -parse-as-library -swift-version 6 \
    -I "$permission_support_bin" -I "$permission_support_bin/Modules" \
    -F build/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64 \
    -target "$(uname -m)-apple-macos15.0" App/*.swift App/Core/*.swift
xcrun swiftc -typecheck -parse-as-library -swift-version 6 -application-extension \
    -target "$(uname -m)-apple-macos15.0" FinderExtension/FinderSync.swift App/Core/FinderIntegration.swift App/Localization.swift
mkdir -p build/Checks
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/CommandRunner.swift App/Localization.swift Tests/CommandRunnerCheck.swift -o build/Checks/command-runner
build/Checks/command-runner
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/BrowserLauncher.swift App/Core/BrowserLanguage.swift App/Localization.swift Tests/BrowserLauncherCheck.swift \
    -o build/Checks/browser-launcher
build/Checks/browser-launcher
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/CommandRunner.swift App/MouseResetController.swift App/Core/MouseResetConfiguration.swift App/Core/ApplicationLifecycle.swift App/Localization.swift \
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
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/FinderActionService.swift App/FinderMoveService.swift App/AirDropService.swift App/Core/FinderIntegration.swift \
    App/Core/ApplicationLifecycle.swift App/Localization.swift Tests/FinderActionCheck.swift -o build/Checks/finder-action
build/Checks/finder-action
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/FinderMoveService.swift App/Core/FinderIntegration.swift App/Localization.swift Tests/FinderMoveCheck.swift -o build/Checks/finder-move
build/Checks/finder-move
xcrun swiftc -parse-as-library -swift-version 6 -application-extension -target "$(uname -m)-apple-macos15.0" \
    FinderExtension/FinderSync.swift App/Core/FinderIntegration.swift App/Localization.swift Tests/FinderPathCopyCheck.swift -o build/Checks/finder-copy-path
build/Checks/finder-copy-path
xcrun swiftc -parse-as-library -swift-version 6 -target "$(uname -m)-apple-macos15.0" \
    App/MenuBarRestartController.swift App/Core/ApplicationLifecycle.swift App/Localization.swift Tests/MenuBarRestartCheck.swift -o build/Checks/menu-bar-restart
build/Checks/menu-bar-restart
sparkle_framework="build/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64"
xcrun swiftc -parse-as-library -swift-version 6 -F "$sparkle_framework" \
    -I "$permission_support_bin" -I "$permission_support_bin/Modules" \
    -L "$permission_support_bin" -lBucklePermissionSupport \
    -Xlinker -rpath -Xlinker "$(pwd)/$sparkle_framework" -target "$(uname -m)-apple-macos15.0" \
    App/CommandRunner.swift App/StatusMenuController.swift App/ApplicationSettingsViewController.swift App/ApplicationUpdateController.swift \
    App/BrowserLauncher.swift App/FinderExtensionController.swift App/MouseResetController.swift App/MenuBarRestartController.swift \
    App/SystemMemoryPanel.swift App/Localization.swift App/Core/*.swift Tests/NativeMenuCheck.swift -o build/Checks/native-menu
build/Checks/native-menu
xcrun swift-format lint --strict --recursive App FinderExtension Support Tests Package.swift
python3 Scripts/check-localizations.py
node --test .github/scripts/*.test.mjs
for script in Scripts/*.sh; do bash -n "$script"; done
plutil -lint App/Info.plist App/Buckle.entitlements FinderExtension/Info.plist FinderExtension/BuckleFinder.entitlements Buckle.xcodeproj/project.pbxproj
git diff --check
