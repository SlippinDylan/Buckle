import AppKit
import ApplicationServices
import UniformTypeIdentifiers

struct FinderMovePlan: Equatable, Sendable {
    let sources: [URL]
    let destination: URL
    let clipboardChangeCount: Int

    init(sources: [URL], destination: URL, clipboardChangeCount: Int) throws {
        guard !sources.isEmpty,
            (sources + [destination]).allSatisfy({
                $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")
            })
        else { throw FinderActionRequest.RequestError.invalidFiles }
        self.sources = sources
        self.destination = destination
        self.clipboardChangeCount = clipboardChangeCount
    }
}

enum FinderMoveError: LocalizedError {
    case clipboardChanged, commandUnavailable, targetUnavailable, handoffFailed, directoryRequired
    case destination(Error)

    var errorDescription: String? {
        switch self {
        case .clipboardChanged: localized("finder.move.clipboard.changed.title")
        case .commandUnavailable: localized("finder.move.command.unavailable.title")
        case .targetUnavailable: localized("finder.move.target.unavailable.title")
        case .handoffFailed: localized("finder.move.handoff.failed.title")
        case .directoryRequired: localized("finder.directory.required")
        case .destination: localized("finder.move.destination.unavailable.title")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .clipboardChanged: localized("finder.move.clipboard.changed")
        case .commandUnavailable: localized("finder.move.command.unavailable")
        case .targetUnavailable: localized("finder.move.target.unavailable")
        case .handoffFailed: localized("finder.move.handoff.failed")
        case .destination: localized("finder.move.destination.unavailable.help")
        case .directoryRequired: nil
        }
    }

    var concernsFolder: Bool {
        switch self {
        case .targetUnavailable, .directoryRequired, .destination: true
        case .clipboardChanged, .commandUnavailable, .handoffFailed: false
        }
    }
}

actor FinderMoveRunner {
    private let accessibilityGranted: @Sendable () -> Bool
    private let automationGranted: @Sendable (AutomationTarget) async throws -> Bool
    private let run: @Sendable ([String]) async throws -> String

    init(
        accessibilityGranted: @escaping @Sendable () -> Bool = { AXIsProcessTrusted() },
        automationGranted: @escaping @Sendable (AutomationTarget) async throws -> Bool = {
            try await AutomationPermissionProbe.shared.granted($0, requestPermission: false)
        },
        run: @escaping @Sendable ([String]) async throws -> String = { arguments in
            try await CommandRunner.run("/usr/bin/osascript", arguments: arguments)
        }
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.run = run
        self.automationGranted = automationGranted
    }

    func move(_ plan: FinderMovePlan) async throws {
        try Task.checkCancellation()
        guard accessibilityGranted() else {
            throw PermissionRequirement.accessibility
        }
        for target in AutomationTarget.allCases {
            guard try await automationGranted(target) else {
                throw PermissionRequirement.automation(target)
            }
        }
        let directory: URL?
        do { directory = try FinderMenuContext.items([plan.destination]).directory() } catch {
            throw FinderMoveError.destination(error)
        }
        guard directory != nil else { throw FinderMoveError.directoryRequired }
        // Paths are arguments, never executable script text. Finder owns the move after the menu action.
        let result = try await run([
            "-l", "AppleScript", "-e", Self.script,
            plan.destination.path, String(plan.clipboardChangeCount),
        ]).trimmingCharacters(in: .whitespacesAndNewlines)
        // The path-resolution stage reports a typed record; never classify errors by their human-readable text.
        let destinationErrorPrefix = "destination-error:"
        if result.hasPrefix(destinationErrorPrefix) {
            let parts = result.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let code = Int(parts[0].dropFirst(destinationErrorPrefix.count)) else {
                throw FinderMoveError.handoffFailed
            }
            throw FinderMoveError.destination(
                NSError(
                    domain: NSOSStatusErrorDomain, code: code,
                    userInfo: [NSLocalizedDescriptionKey: String(parts[1])]))
        }
        switch result {
        case "sent": return
        case "clipboard-changed": throw FinderMoveError.clipboardChanged
        case "command-unavailable": throw FinderMoveError.commandUnavailable
        case "target-unavailable": throw FinderMoveError.targetUnavailable
        default: throw FinderMoveError.handoffFailed
        }
    }

    // A right-clicked folder is not Finder's paste destination until its window has navigated there.
    // Recheck window, insertion location, focus and clipboard immediately before sending Finder's native shortcut.
    static let script = """
        use framework "AppKit"
        use scripting additions

        on run argv
            set expectedClipboardCount to item 2 of argv as integer
            if my readClipboardCount() is not expectedClipboardCount then return "clipboard-changed"
            try
                set destinationFolder to my resolveDestination(item 1 of argv)
            on error errorMessage number errorNumber
                return "destination-error:" & errorNumber & linefeed & errorMessage
            end try
            set moveWindowID to my prepareFinder(destinationFolder)
            set ready to false
            repeat 100 times
                set ready to my targetMatches(my readContext(), moveWindowID, destinationFolder)
                if ready then exit repeat
                delay 0.05
            end repeat
            if not ready then return "target-unavailable"
            return my dispatchMove(moveWindowID, destinationFolder, expectedClipboardCount)
        end run

        on dispatchMove(moveWindowID, destinationFolder, expectedClipboardCount)
            if my hasCustomShortcuts() then return "command-unavailable"
            set moveKeyCode to my resolveMoveKeyCode()
            if moveKeyCode is missing value then return "command-unavailable"
            set issue to my contextIssue(my readContext(), moveWindowID, destinationFolder, expectedClipboardCount)
            if issue is not "ready" then return issue
            return my performMove(moveKeyCode)
        end dispatchMove

        on targetMatches(context, moveWindowID, destinationFolder)
            return (item 1 of context is moveWindowID) and ¬
                (item 2 of context is destinationFolder) and ¬
                (item 3 of context is destinationFolder) and (item 4 of context)
        end targetMatches

        on contextIssue(context, moveWindowID, destinationFolder, expectedClipboardCount)
            if not my targetMatches(context, moveWindowID, destinationFolder) then return "target-unavailable"
            if item 5 of context then return "target-unavailable"
            if item 6 of context is in {"AXTextField", "AXTextArea", "AXComboBox"} then return "target-unavailable"
            if item 7 of context is not expectedClipboardCount then return "clipboard-changed"
            return "ready"
        end contextIssue

        on readClipboardCount()
            return current application's NSPasteboard's generalPasteboard()'s changeCount() as integer
        end readClipboardCount

        on resolveDestination(destinationPath)
            return POSIX file destinationPath as alias
        end resolveDestination

        on prepareFinder(destinationFolder)
            tell application id "com.apple.finder"
                if (count of Finder windows) is 0 then
                    set moveWindow to make new Finder window to destinationFolder
                else
                    set moveWindow to front Finder window
                    set target of moveWindow to destinationFolder
                end if
                set moveWindowID to id of moveWindow
                set index of moveWindow to 1
                set selection to {}
                activate
            end tell
            return moveWindowID
        end prepareFinder

        on readContext()
            tell application id "com.apple.finder"
                set windowID to id of front Finder window
                set currentFolder to target of front Finder window as alias
                set insertionFolder to insertion location as alias
            end tell
            tell application id "com.apple.systemevents"
                tell application process "Finder"
                    set isFront to frontmost
                    set hasSheet to exists sheet 1 of window 1
                    set focusedRole to role of (value of attribute "AXFocusedUIElement")
                end tell
            end tell
            return {windowID, currentFolder, insertionFolder, isFront, hasSheet, focusedRole, my readClipboardCount()}
        end readContext

        on hasCustomShortcuts()
            -- User key equivalents can change what Command-Option-V does; never guess their intent.
            set defaults to current application's NSUserDefaults's standardUserDefaults()
            repeat with domainName in {current application's NSGlobalDomain, "com.apple.finder"}
                set settings to defaults's persistentDomainForName:(domainName as text)
                if settings is not missing value then
                    set shortcuts to settings's objectForKey:"NSUserKeyEquivalents"
                    if shortcuts is not missing value then
                        if (shortcuts's |count|() as integer) > 0 then return true
                    end if
                end if
            end repeat
            return false
        end hasCustomShortcuts

        on resolveMoveKeyCode()
            -- AppKit applies the active layout's Command mapping, including Dvorak-QWERTY Command.
            set appInstance to current application's NSApplication's sharedApplication()
            set matches to {}
            repeat with code from 0 to 127
                set keyEvent to current application's NSEvent's keyEventWithType:(current application's NSEventTypeKeyDown) ¬
                    location:{0, 0} modifierFlags:(current application's NSEventModifierFlagCommand) timestamp:0 ¬
                    windowNumber:0 context:(missing value) |characters|:"" charactersIgnoringModifiers:"" isARepeat:false keyCode:code
                set chars to keyEvent's charactersByApplyingModifiers:(current application's NSEventModifierFlagCommand)
                if chars is not missing value then
                    if chars as text is "v" then set end of matches to code as integer
                end if
            end repeat
            if count of matches is not 1 then return missing value
            return item 1 of matches
        end resolveMoveKeyCode

        on performMove(moveKeyCode)
            tell application id "com.apple.systemevents" to tell application process "Finder" ¬
                to key code moveKeyCode using {command down, option down}
            return "sent"
        end performMove
        """
}

@MainActor
enum FinderActionAlert {
    static func make(_ error: Error) -> NSAlert {
        if error is PermissionRequirement { return permissionAlert(error) }
        let alert = NSAlert(error: error)
        if error is FinderActionRequest.RequestError {
            alert.messageText = localized("finder.invalid.request.title")
            alert.informativeText = localized("finder.invalid.request")
        } else if case CommandFailure.timedOut = error {
            alert.messageText = localized("finder.move.timeout.title")
            alert.informativeText = localized("finder.move.timeout.help")
        }
        alert.alertStyle = .critical
        if let issue = error as? FinderMoveError, issue.concernsFolder {
            alert.icon = NSWorkspace.shared.icon(for: UTType.folder)
        } else {
            alert.icon = NSApp.applicationIconImage
        }
        return alert
    }

    private static func permissionAlert(_ error: Error) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = localized("permissions.required.title")
        alert.informativeText = error.localizedDescription
        // AppKit places the first, default action on the right.
        alert.addButton(withTitle: localized("permissions.authorize"))
        alert.addButton(withTitle: localized("cancel")).keyEquivalent = "\u{1b}"
        return alert
    }
}
