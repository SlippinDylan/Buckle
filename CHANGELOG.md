# Changelog

## [Unreleased]

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
