# Changelog

## [Unreleased]

### Fixed
- The Settings window no longer floats above Sparkle update windows.
- Finder context-menu actions no longer crash the extension when Finder invokes them on a background XPC queue, which prevented AirDrop from opening and removed the menu entry afterward.

## [0.2.0] - 2026-11-15

### Changed
- Move Items Here no longer asks for confirmation; missing-permission prompts open the existing Settings authorization flows, and move errors use consistent native alerts with clearer guidance and folder or app icons matching the cause.
- Only AirDrop retains an icon in Finder context menus; Open in Terminal, Copy Path, and Move Items Here use text labels.
- Move Items Here now opens the destination in Finder and triggers its native move command, with Finder managing progress, conflicts, and Undo; Accessibility and Finder/System Events automation access are required.

### Fixed
- A damaged move-signing key no longer blocks other Finder action switches or turning off Move Items Here.
- Destination folders disappearing before script execution now show a folder-specific error and icon while preserving the original error details.
- Move requests authenticate the destination and clipboard version so arbitrary external URLs cannot trigger a move.
- Finder authorization rechecks access after a cached grant, including permissions revoked in System Settings.
- Manual Finder automation authorization waits for an ongoing permission check instead of dropping the request.
- Finder and System Events automation permissions are reported separately, and moves identify missing access before execution.
- Move Items Here resolves the native move shortcut using the active keyboard layout, including Dvorak Command mappings, and refuses customized Finder/global menu shortcuts instead of guessing a command.
- AirDrop no longer blocks other Finder actions or normal quit while awaiting sharing callbacks; per-session delegates handle cancellation and prevent duplicate sharing windows.
- Copy Path now displays a clear error when copying fails, and remains available when folder metadata checks fail.

## [0.1.2] - 2026-11-14

### Fixed
- Release publishing now rejects an existing version tag that points to different source code, preventing mismatched installers and update metadata.
- Japanese browser launches now request the Tokyo time zone, matching the original launch script, without changing the macOS time zone.
- Chromium browsers launched in Japanese now receive Japanese (Japan) as the preferred language, with Japanese as the fallback, matching the original script.

### Added
- Added a configurable delay before reopening mouse-reset apps in Settings, from 0 to 60 seconds, with a default of 3 seconds.

### Improved
- Increased the menu-bar icon to 20pt and thickened its lines for better visibility alongside other menu-bar icons.
- GitHub Releases and in-app update notes now use the same version-specific English changelog, so each release explains what changed.

### Known Issues
- Website regional formatting can still follow the browser's macOS application language. Selecting Japanese does not guarantee that this formatting changes to Japanese.
- The Japanese time-zone behavior has been verified with Chrome Beta; other supported browsers still require testing.
