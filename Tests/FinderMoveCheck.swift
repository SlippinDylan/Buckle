import AppKit
import ApplicationServices

private actor MoveCommand {
    private(set) var calls: [[String]] = []
    let response: String

    init(_ response: String) { self.response = response }

    func run(_ arguments: [String]) -> String {
        calls.append(arguments)
        return response
    }
}

@main
enum FinderMoveCheck {
    @MainActor private static func verifyAlerts() {
        let permissions: [PermissionRequirement] = [.accessibility, .automation(.finder), .automation(.systemEvents)]
        for permission in permissions {
            let alert = FinderActionAlert.make(permission)
            precondition(alert.buttons.map(\.title) == [localized("permissions.authorize"), localized("cancel")])
            precondition(alert.buttons[1].keyEquivalent == "\u{1b}")
            precondition(alert.informativeText == permission.localizedDescription)
        }
        let clipboardError = FinderMoveError.clipboardChanged
        let clipboard = FinderActionAlert.make(clipboardError)
        precondition(clipboard.alertStyle == .critical)
        precondition(clipboard.messageText == localized("finder.move.clipboard.changed.title"))
        precondition(clipboard.informativeText.contains(localized("finder.move.clipboard.changed")))
        for issue: FinderMoveError in [
            .targetUnavailable, .directoryRequired, .destination(CocoaError(.fileReadNoSuchFile)),
        ] {
            let icon = NSImage(size: NSSize(width: 32, height: 32))
            var iconRequests = 0
            let folder = FinderActionAlert.make(issue) {
                iconRequests += 1
                return icon
            }
            precondition(issue.concernsFolder && folder.alertStyle == .critical)
            // System icons may contain different cached representations on different hosts.
            precondition(iconRequests == 1 && folder.icon === icon)
        }
        for issue: FinderMoveError in [.clipboardChanged, .commandUnavailable, .handoffFailed] {
            let app = FinderActionAlert.make(issue) {
                preconditionFailure("An application error must not request a folder icon")
            }
            precondition(!issue.concernsFolder && app.alertStyle == .critical)
            precondition(app.icon === NSApp.applicationIconImage)
        }
        let invalid = FinderActionAlert.make(FinderActionRequest.RequestError.invalidFiles)
        precondition(invalid.alertStyle == .critical)
        precondition(invalid.messageText == localized("finder.invalid.request.title"))
        precondition(invalid.informativeText == localized("finder.invalid.request"))
        let timeout = FinderActionAlert.make(CommandFailure.timedOut(executable: "/usr/bin/osascript"))
        precondition(timeout.alertStyle == .critical)
        precondition(timeout.messageText == localized("finder.move.timeout.title"))
        precondition(timeout.informativeText == localized("finder.move.timeout.help"))
    }

    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let destination = root.appendingPathComponent("中文 \"quote\" '$(literal); folder")
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        defer {
            do { try manager.removeItem(at: root) } catch { preconditionFailure(error.localizedDescription) }
        }
        let source = root.appendingPathComponent("source.txt")
        try Data("must not be moved by Buckle".utf8).write(to: source)
        let plan = try FinderMovePlan(sources: [source], destination: destination, clipboardChangeCount: 42)
        let command = MoveCommand("sent\n")
        try await FinderMoveRunner(
            accessibilityGranted: { true }, automationGranted: { _ in true }, run: { await command.run($0) }
        ).move(plan)
        let calls = await command.calls
        precondition(calls.count == 1)
        precondition(calls[0] == ["-l", "AppleScript", "-e", FinderMoveRunner.script, destination.path, "42"])
        precondition(!FinderMoveRunner.script.contains(destination.path), "Paths must never become executable code")
        let data = try Data(contentsOf: source)
        precondition(data == Data("must not be moved by Buckle".utf8))
        precondition(!manager.fileExists(atPath: destination.appendingPathComponent(source.lastPathComponent).path))

        for result in ["clipboard-changed", "target-unavailable", "command-unavailable", "unexpected"] {
            let command = MoveCommand(result)
            do {
                try await FinderMoveRunner(
                    accessibilityGranted: { true }, automationGranted: { _ in true }, run: { await command.run($0) }
                ).move(plan)
                preconditionFailure("An unconfirmed handoff must not report success")
            } catch {
                precondition((error as NSError).localizedDescription != "")
                if result == "clipboard-changed" {
                    guard case FinderMoveError.clipboardChanged = error else { preconditionFailure() }
                }
                if result == "target-unavailable" {
                    guard case FinderMoveError.targetUnavailable = error else { preconditionFailure() }
                }
            }
        }
        do {
            try await FinderMoveRunner(
                accessibilityGranted: { false }, run: { _ in preconditionFailure("Missing permission sent keys") }
            ).move(plan)
            preconditionFailure("Missing accessibility permission was accepted")
        } catch PermissionRequirement.accessibility {}
        do {
            try await FinderMoveRunner(
                accessibilityGranted: { true }, automationGranted: { _ in true },
                run: { _ in throw CocoaError(.fileReadNoPermission) }
            ).move(plan)
            preconditionFailure("Automation failure was hidden")
        } catch CocoaError.fileReadNoPermission {}
        let invalid = try FinderMovePlan(sources: [source], destination: source, clipboardChangeCount: 42)
        do {
            try await FinderMoveRunner(
                accessibilityGranted: { true }, automationGranted: { _ in true },
                run: { _ in preconditionFailure("A file became a move destination") }
            ).move(invalid)
            preconditionFailure("Invalid directory was accepted")
        } catch FinderMoveError.directoryRequired {}
        let cancelled = Task {
            try await FinderMoveRunner(
                accessibilityGranted: { true }, automationGranted: { _ in true },
                run: { _ in preconditionFailure("Cancelled request sent keys") }
            ).move(plan)
        }
        cancelled.cancel()
        do {
            try await cancelled.value
            preconditionFailure("Cancelled handoff was accepted")
        } catch is CancellationError {}

        for denied in AutomationTarget.allCases {
            do {
                try await FinderMoveRunner(
                    accessibilityGranted: { true }, automationGranted: { $0 != denied },
                    run: { _ in preconditionFailure("Unauthorized target sent keys") }
                ).move(plan)
                preconditionFailure("Missing target authorization was accepted")
            } catch PermissionRequirement.automation(let actual) {
                precondition(actual == denied)
            }
        }
        try await verifyDisappearingDestination(in: root)
        verifyAlerts()
        try await verifyPermissionStates()
        try await verifyPermissionRequestDuringRefresh()
        try await verifyDispatchGuards()
        // Compile the real script, then exercise its early guard without navigating Finder or writing the clipboard.
        let script = root.appendingPathComponent("move.applescript")
        try FinderMoveRunner.script.write(to: script, atomically: true, encoding: .utf8)
        _ = try await CommandRunner.run(
            "/usr/bin/osacompile", arguments: ["-o", root.appendingPathComponent("move.scpt").path, script.path])
        let stale = try await CommandRunner.run(
            "/usr/bin/osascript",
            arguments: ["-l", "AppleScript", "-e", FinderMoveRunner.script, destination.path, "-1"])
        precondition(stale.trimmingCharacters(in: .whitespacesAndNewlines) == "clipboard-changed")
        print(
            "Native Finder handoff validates permissions and destination, preserves arguments, propagates errors, and rejects stale clipboard requests without moving files."
        )
    }
    private static func verifyDisappearingDestination(in root: URL) async throws {
        let destination = root.appendingPathComponent("vanishing folder")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let plan = try FinderMovePlan(
            sources: [root.appendingPathComponent("unused.txt")], destination: destination, clipboardChangeCount: 42)
        do {
            try await FinderMoveRunner(
                accessibilityGranted: { true }, automationGranted: { _ in true },
                run: { arguments in
                    try FileManager.default.removeItem(at: destination)
                    var arguments = arguments
                    arguments[3] = replacingHandler("readClipboardCount", in: arguments[3], with: "return 42")
                    // The real path-to-alias conversion must fail before any Finder UI is touched.
                    arguments[3] = replacingHandler(
                        "prepareFinder", in: arguments[3], with: "error \"Unexpected Finder navigation\" number -99999")
                    return try await CommandRunner.run("/usr/bin/osascript", arguments: arguments)
                }
            ).move(plan)
            preconditionFailure("A disappearing destination was accepted")
        } catch FinderMoveError.destination(let underlying) {
            let failure = underlying as NSError
            precondition(failure.domain == NSOSStatusErrorDomain && failure.code != 0 && failure.code != -99999)
            precondition(!failure.localizedDescription.isEmpty)
        }
    }

    @MainActor private static func verifyPermissionStates() async throws {
        let allowed = try AutomationTarget.isGranted(noErr)
        precondition(allowed)
        let denied = try AutomationTarget.isGranted(OSStatus(errAEEventNotPermitted))
        precondition(!denied)
        let needsConsent = try AutomationTarget.isGranted(OSStatus(errAEEventWouldRequireUserConsent))
        precondition(!needsConsent)
        do {
            _ = try AutomationTarget.isGranted(-600)
            preconditionFailure("A failed query was reported as a permission decision")
        } catch { precondition((error as NSError).code == -600) }
        var requests: [Bool] = []
        let permission = FinderAutomationPermission(query: {
            requests.append($0)
            return $0
        })
        await permission.refresh()
        precondition(permission.state == .required && requests == [false])
        try await permission.request()
        precondition(permission.state == .granted && requests == [false, true])
        let revoked = FinderAutomationPermission(query: { request in request ? false : true })
        await revoked.refresh()
        precondition(revoked.state == .granted)
        try await revoked.request()
        precondition(revoked.state == .required, "A cached grant must not skip an explicit authorization request")
        let failed = FinderAutomationPermission(query: { _ in throw CocoaError(.fileReadUnknown) })
        await failed.refresh()
        guard case .failed = failed.state else { preconditionFailure("A failed permission query was hidden") }
    }

    @MainActor private static func verifyPermissionRequestDuringRefresh() async throws {
        for outcome in ["required", "granted", "failed"] {
            var requests: [Bool] = []
            var pending: CheckedContinuation<Bool, Error>?
            let permission = FinderAutomationPermission { request in
                requests.append(request)
                if request { return true }
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            let refresh = Task { await permission.refresh() }
            while pending == nil { await Task.yield() }
            var started = false
            var finished = false
            let request = Task {
                started = true
                try await permission.request()
                finished = true
            }
            while !started { await Task.yield() }
            precondition(!finished, "An explicit request must wait for the pending permission check")
            precondition(requests == [false])
            guard let pending else { preconditionFailure("Missing silent permission check") }
            if outcome == "failed" {
                pending.resume(throwing: CocoaError(.fileReadUnknown))
            } else {
                pending.resume(returning: outcome == "granted")
            }
            await refresh.value
            try await request.value
            precondition(permission.state == .granted)
            precondition(requests == [false, true])
        }
    }

    private static func replacingHandler(_ name: String, in script: String, with body: String) -> String {
        guard let start = script.range(of: "on " + name + "("),
            let end = script.range(of: "end " + name, range: start.lowerBound..<script.endIndex),
            let signatureEnd = script[start.lowerBound...].firstIndex(of: "\n")
        else { preconditionFailure("Missing production I/O handler: " + name) }
        return script.replacingCharacters(in: signatureEnd..<end.upperBound, with: "\n" + body + "\nend " + name)
    }

    private static func verifyDispatchGuards() async throws {
        let good = "{123, \"destination\", \"destination\", true, false, \"AXOutline\", 42}"
        let cases: [(String, String, String)] = [
            ("ready", good, "sent:1"),
            ("missing command", good, "command-unavailable:0"),
            ("custom shortcuts", good, "command-unavailable:0"),
            (
                "wrong window", "{124, \"destination\", \"destination\", true, false, \"AXOutline\", 42}",
                "target-unavailable:0"
            ),
            (
                "wrong directory", "{123, \"elsewhere\", \"destination\", true, false, \"AXOutline\", 42}",
                "target-unavailable:0"
            ),
            (
                "wrong insertion", "{123, \"destination\", \"elsewhere\", true, false, \"AXOutline\", 42}",
                "target-unavailable:0"
            ),
            (
                "background", "{123, \"destination\", \"destination\", false, false, \"AXOutline\", 42}",
                "target-unavailable:0"
            ),
            ("sheet", "{123, \"destination\", \"destination\", true, true, \"AXOutline\", 42}", "target-unavailable:0"),
            (
                "text field", "{123, \"destination\", \"destination\", true, false, \"AXTextField\", 42}",
                "target-unavailable:0"
            ),
            (
                "text area", "{123, \"destination\", \"destination\", true, false, \"AXTextArea\", 42}",
                "target-unavailable:0"
            ),
            (
                "combo box", "{123, \"destination\", \"destination\", true, false, \"AXComboBox\", 42}",
                "target-unavailable:0"
            ),
            (
                "clipboard", "{123, \"destination\", \"destination\", true, false, \"AXOutline\", 43}",
                "clipboard-changed:0"
            ),
        ]
        for (name, context, expected) in cases {
            // Only OS boundaries change. The real entry point, checks and dispatch gate execute unchanged.
            var script = FinderMoveRunner.script
            script = replacingHandler("readClipboardCount", in: script, with: "return 42")
            script = replacingHandler("resolveDestination", in: script, with: "return destinationPath")
            script = replacingHandler("prepareFinder", in: script, with: "return 123")
            script = replacingHandler(
                "hasCustomShortcuts", in: script, with: name == "custom shortcuts" ? "return true" : "return false")
            script = replacingHandler(
                "resolveMoveKeyCode", in: script,
                with: name == "missing command" ? "return missing value" : "return 9")
            script = replacingHandler(
                "readContext", in: script,
                with: """
                    set reads to reads + 1
                    if reads is 1 then return \(good)
                    return \(context)
                    """)
            script = replacingHandler(
                "performMove", in: script, with: "set dispatches to dispatches + 1\nreturn \"sent\"")
            script = script.replacingOccurrences(of: "on run argv", with: "on requestMove(argv)")
                .replacingOccurrences(of: "end run", with: "end requestMove")
            script =
                "property reads : 0\nproperty dispatches : 0\n" + script + """

                    on run argv
                        set outcome to my requestMove(argv)
                        return outcome & ":" & dispatches
                    end run
                    """
            let result = try await CommandRunner.run(
                "/usr/bin/osascript", arguments: ["-l", "AppleScript", "-e", script, "destination", "42"])
            precondition(result.trimmingCharacters(in: .whitespacesAndNewlines) == expected, name)
        }
    }

}
