# Changelog

## [Unreleased]

### Added
- Optional New Text File Finder action creates and selects an empty text file in a single folder, using numbered names without overwriting existing files and rejecting replayed creation requests across restarts.

### Changed
- Documented how to clear the setup dismissal record when uninstalling so setup appears after reinstalling; normal upgrades preserve it.

## [0.3.1] - 2026-11-15

### Changed
- Removed the setup guide reopen button from General settings; first-run setup still appears once.
- Added spacing above the mouse reset wait description and styled it as secondary text.

## [0.3.0] - 2026-11-15

### Added
- An optional first-run setup guide introduces the menu-bar app, Finder actions and their required access, launch at login, and automatic update checks, with an animated welcome, a separate permissions page before feature switches, grouped circular back and continue controls, an inline completion page with a celebration and an action to open the menu, and a reopen action in General settings.

### Changed
- Closing setup preserves saved choices and prevents the guide from reopening automatically after restarts or upgrades; existing users see it once while keeping their settings.
- New installations leave automatic update checks off until selected in setup or Settings, without a separate Sparkle permission prompt; existing update preferences and manual checks are preserved.

### Fixed
- Setup errors stay attached to the window that initiated the action, including after controls refresh.
- Finder configuration failures expose existing recovery or retry actions instead of an empty feature page.
- Canceling quit restores a previously visible setup window at its current step.

## [0.2.3] - 2026-11-15

### Changed
- Settings tabs now appear in General, Permissions, Mouse Reset, and About order.

### Fixed
- Accessibility guidance now closes automatically when access is granted and stops checking when returning to Buckle or System Settings exits.

## [0.2.2] - 2026-11-15

### Fixed
- Finder context-menu actions now retain their request snapshots when Finder replaces menu items with XPC proxies and publish concurrent menu snapshots atomically.
- AirDrop requests file access before checking availability, so protected-folder access errors are not mistaken for an unsupported sharing service.

## [0.2.1] - 2026-11-15

### Changed
- CI now classifies changes and automatically packages and publishes an unpublished version after a successful full main build when packaging is enabled; documentation and helper-only changes do not release installers. Test packaging remains a separate manual workflow.
- Test installers disable updates, and DMGs now use a drag-to-install layout with version, destination, and overwrite checks.
- Distribution synchronization now prepares the Buckle Homebrew Cask and Tap listing from the published installer alongside its signed update feed.

### Fixed
- About now explains unavailable updates when configuration is missing or initialization fails.
- Release checks reject reused versions or build numbers and mismatched update-signing keys before publishing.
- Activity notifications now cover PR reviews and code comments, link PR conversation comments correctly, and report one start and result per actual CI, packaging, and update-synchronization stage, with publishing results tracked separately.
- Localization and release-note checks now validate more format arguments, accept Breaking Changes, and reject unfinished release notes.
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
