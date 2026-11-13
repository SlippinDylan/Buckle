import ApplicationServices
import CoreFoundation
import Foundation

@MainActor
private final class FakePanelOperations: SystemMemoryPanelOperations {
    var value: CFPropertyList?
    var writes: [CFPropertyList?] = []
    var permissionsFail = false
    var triggerFails = false
    var restoreFails = false
    var triggered = false
    var issue: MemoryPanelPermissionIssue?
    var permissionRequests: [Bool] = []
    var automationGranted = true
    var onTrigger: (() -> Void)?
    var suspendsPermissionCheck = false
    var suspendsManualRequest = false
    var permissionContinuation: CheckedContinuation<Void, Never>?

    init(original: CFPropertyList?) { value = original }

    func debugValue() -> CFPropertyList? { value }

    func setDebugValue(_ value: CFPropertyList?) throws {
        writes.append(value)
        if restoreFails && writes.count > 1 {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "restore failure"])
        }
        self.value = value
    }

    func permissions(requestPermission: Bool) async throws -> MemoryPanelPermissions {
        permissionRequests.append(requestPermission)
        if (!requestPermission && suspendsPermissionCheck) || (requestPermission && suspendsManualRequest) {
            await withCheckedContinuation { permissionContinuation = $0 }
        }
        if permissionsFail { throw NSError(domain: "Test", code: 3) }
        return MemoryPanelPermissions(
            accessibilityGranted: issue != .accessibility, automationGranted: automationGranted && issue != .automation)
    }

    func trigger() async throws {
        triggered = true
        precondition(value as? Bool == true)
        onTrigger?()
        if triggerFails {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "trigger failure"])
        }
    }
}

@main
enum SystemMemoryPanelCheck {
    @MainActor static func main() async throws {
        try await verifyWindowConfirmation()
        let event = MemoryPanelShortcut.event()
        precondition(event.eventClass == 0x7072_6373 && event.eventID == 0x6b63_6f64)
        precondition(event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.int32Value == 53)
        let modifiers = event.paramDescriptor(forKeyword: 0x6661_616c)
        precondition(modifiers?.numberOfItems == 2)
        precondition(modifiers?.atIndex(1)?.enumCodeValue == 0x4b63_6d64)
        precondition(modifiers?.atIndex(2)?.enumCodeValue == 0x4b6f_7074)
        precondition(MemoryPanelShortcut.sendOptions.rawValue & UInt(kAEDoNotPromptForUserConsent) != 0)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch { preconditionFailure("\(error)") }
        }
        let recovery = MemoryPanelRecoveryStore(directory: directory)
        let originals: [CFPropertyList?] = [nil, kCFBooleanFalse, kCFBooleanTrue, "existing" as CFString]
        for original in originals {
            for triggerFails in [false, true] {
                let operations = FakePanelOperations(original: original)
                operations.triggerFails = triggerFails
                let panel = SystemMemoryPanel(operations: operations, recovery: recovery)
                var failure: Error?
                do { _ = try await panel.show(requestPermission: true) } catch { failure = error }
                precondition((failure != nil) == triggerFails)
                precondition(operations.triggered && operations.writes.count == 2 && !panel.isOpening)
                if let original, let restored = operations.value {
                    precondition(CFEqual(original, restored))
                } else {
                    precondition(original == nil && operations.value == nil)
                }
            }
        }
        let operations = FakePanelOperations(original: nil)
        operations.triggerFails = true
        operations.restoreFails = true
        let panel = SystemMemoryPanel(operations: operations, recovery: recovery)
        do {
            _ = try await panel.show(requestPermission: false)
            preconditionFailure("Restoration failure must be reported")
        } catch {
            precondition(error.localizedDescription.contains("trigger failure"))
            precondition(error.localizedDescription.contains("restore failure"))
        }
        // A failed restoration must retain the original across a fresh controller instance.
        let pendingFailure = try recovery.load()
        precondition(pendingFailure != nil)
        operations.restoreFails = false
        let restarted = SystemMemoryPanel(operations: operations, recovery: recovery)
        try restarted.recover()
        precondition(operations.value == nil)
        let pending = try recovery.load()
        precondition(pending == nil)

        for original in originals {
            try recovery.save(original: original)
            let interrupted = FakePanelOperations(original: kCFBooleanTrue)
            let restarted = SystemMemoryPanel(operations: interrupted, recovery: recovery)
            try restarted.recover()
            if let original, let restored = interrupted.value {
                precondition(CFEqual(original, restored))
            } else {
                precondition(original == nil && interrupted.value == nil)
            }
            let pending = try recovery.load()
            precondition(pending == nil)
        }
        for issue in [MemoryPanelPermissionIssue.accessibility, .automation] {
            for requestPermission in [false, true] {
                let denied = FakePanelOperations(original: nil)
                denied.issue = issue
                let panel = SystemMemoryPanel(operations: denied, recovery: recovery)
                let opened = try await panel.show(requestPermission: requestPermission)
                precondition(!opened && panel.permissionIssue == issue)
                precondition(denied.permissionRequests == [requestPermission])
                precondition(!denied.triggered && denied.writes.isEmpty)
                let pending = try recovery.load()
                precondition(pending == nil)
                denied.issue = nil
                let retried = try await panel.show(requestPermission: requestPermission)
                precondition(retried)
            }
        }
        let lifecycle = ApplicationLifecycle()
        let quitting = FakePanelOperations(original: nil)
        let opening = SystemMemoryPanel(operations: quitting, lifecycle: lifecycle, recovery: recovery)
        var replied = false
        quitting.onTrigger = {
            precondition(opening.isOpening)
            precondition(!lifecycle.requestTermination())
        }
        lifecycle.onReadyToTerminate = {
            precondition(quitting.value == nil && !opening.isOpening)
            replied = true
        }
        let opened = try await opening.show(requestPermission: false)
        precondition(opened && replied)
        let repeated = try await opening.show(requestPermission: true)
        precondition(!repeated)
        lifecycle.cancelTermination()

        let permissionOperations = FakePanelOperations(original: nil)
        permissionOperations.issue = .accessibility
        let permissions = SystemMemoryPanel(operations: permissionOperations, recovery: recovery)
        await permissions.refreshPermissions()
        precondition(permissions.permissionIssue == .accessibility)
        precondition(permissionOperations.permissionRequests == [false] && permissionOperations.writes.isEmpty)
        permissionOperations.issue = nil
        await permissions.refreshPermissions()
        precondition(permissions.permissionIssue == nil && !permissionOperations.triggered)

        let automationOperations = FakePanelOperations(original: nil)
        automationOperations.issue = .accessibility
        automationOperations.automationGranted = false
        let automationLifecycle = ApplicationLifecycle()
        let automation = SystemMemoryPanel(
            operations: automationOperations, lifecycle: automationLifecycle, recovery: recovery)
        await automation.refreshPermissions()
        precondition(automation.permissionIssue == .accessibility && automation.automationGranted == false)
        automationOperations.automationGranted = true
        try await automation.requestAutomationPermission()
        precondition(automation.permissionIssue == .accessibility && automation.automationGranted == true)
        precondition(automationOperations.permissionRequests == [false, true])
        precondition(automationOperations.writes.isEmpty && !automationOperations.triggered)
        automationOperations.suspendsManualRequest = true
        let manualRequest = Task { try await automation.requestAutomationPermission() }
        while automationOperations.permissionContinuation == nil { await Task.yield() }
        precondition(automation.isCheckingPermissions)
        do {
            try await automation.requestAutomationPermission()
            preconditionFailure("Duplicate manual authorization must not prompt")
        } catch CocoaError.userCancelled {}
        var automationQuitReady = false
        automationLifecycle.onReadyToTerminate = { automationQuitReady = true }
        precondition(!automationLifecycle.requestTermination() && !automationQuitReady)
        automationOperations.permissionContinuation?.resume()
        do {
            try await manualRequest.value
            preconditionFailure("Authorization returning during shutdown must cancel its UI continuation")
        } catch CocoaError.userCancelled {}
        precondition(automationQuitReady && !automation.isCheckingPermissions)
        do {
            try await automation.requestAutomationPermission()
            preconditionFailure("Authorization must not start during shutdown")
        } catch CocoaError.userCancelled {}

        // A quit during the foreground prompt must prevent all new system preference writes.
        for permissionsFail in [false, true] {
            for authorizationOnly in [false, true] {
                let operations = FakePanelOperations(original: nil)
                operations.suspendsManualRequest = true
                operations.permissionsFail = permissionsFail
                let lifecycle = ApplicationLifecycle()
                let panel = SystemMemoryPanel(operations: operations, lifecycle: lifecycle, recovery: recovery)
                var replies = 0
                lifecycle.onReadyToTerminate = { replies += 1 }
                let request = Task {
                    if authorizationOnly {
                        try await panel.requestAutomationPermission()
                        return true
                    }
                    return try await panel.show(requestPermission: true)
                }
                while operations.permissionContinuation == nil { await Task.yield() }
                precondition(!lifecycle.requestTermination())
                operations.permissionContinuation?.resume()
                if authorizationOnly {
                    do {
                        _ = try await request.value
                        preconditionFailure("Shutdown must cancel authorization, including a failed prompt")
                    } catch CocoaError.userCancelled {}
                    precondition(panel.permissionError == nil)
                } else {
                    let opened = try await request.value
                    precondition(!opened)
                }
                precondition(replies == 1 && !panel.isOpening && !panel.isCheckingPermissions)
                precondition(operations.writes.isEmpty && !operations.triggered)
                let pending = try recovery.load()
                precondition(pending == nil)
            }
        }

        for quitWhileWaiting in [false, true] {
            let operations = FakePanelOperations(original: nil)
            operations.suspendsPermissionCheck = true
            let lifecycle = ApplicationLifecycle()
            let panel = SystemMemoryPanel(operations: operations, lifecycle: lifecycle, recovery: recovery)
            var replies = 0
            lifecycle.onReadyToTerminate = { replies += 1 }
            let checking = Task { await panel.refreshPermissions() }
            while operations.permissionContinuation == nil { await Task.yield() }
            var requested = false
            var finished = false
            let opening = Task {
                requested = true
                let opened = try await panel.show(requestPermission: true)
                finished = true
                return opened
            }
            while !requested { await Task.yield() }
            precondition(!finished, "Manual opening must wait for the background permission check")
            let duplicate = try await panel.show(requestPermission: true)
            precondition(!duplicate)
            if quitWhileWaiting { precondition(!lifecycle.requestTermination()) }
            operations.permissionContinuation?.resume()
            await checking.value
            let opened = try await opening.value
            precondition(opened == !quitWhileWaiting && !panel.isOpening)
            precondition(operations.triggered == !quitWhileWaiting)
            precondition(operations.permissionRequests == (quitWhileWaiting ? [false] : [false, true]))
            precondition(replies == (quitWhileWaiting ? 1 : 0))
        }

        // A recovery file that cannot be read must not be overwritten by a new request.
        let invalid = Data("invalid recovery record".utf8)
        try invalid.write(to: directory.appendingPathComponent("pending.plist"))
        let untouched = FakePanelOperations(original: nil)
        let blocked = SystemMemoryPanel(operations: untouched, recovery: recovery)
        do {
            _ = try await blocked.show(requestPermission: false)
            preconditionFailure("Unreadable recovery must prevent a new preference change")
        } catch {
            precondition(untouched.writes.isEmpty && !untouched.triggered)
            for allowQuit in [false, true] {
                let lifecycle = ApplicationLifecycle()
                precondition(lifecycle.requestTermination())
                var prompted = false
                let decision = await lifecycle.resolveTermination(recover: blocked.recover) { _ in
                    prompted = true
                    return allowQuit ? .quit : .cancel
                }
                precondition(prompted && decision == allowQuit)
                precondition(lifecycle.terminationRequested == allowQuit)
                let preserved = try Data(contentsOf: directory.appendingPathComponent("pending.plist"))
                precondition(preserved == invalid)
            }
        }
        print(
            "Memory panel recovery across restarts, permission denial and error paths verified without opening a window."
        )
    }
    @MainActor private static func verifyWindowConfirmation() async throws {
        let root = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) } catch {
                preconditionFailure("Cannot remove test resources: \(error)")
            }
        }
        let table = root.appendingPathComponent("LowMemoryPanel.loctable")
        let translations = [
            "en": ["100009.title": "Memory warning"], "ja": ["100009.title": "メモリの警告"],
            "metadata": ["other": "Not a warning"],
        ]
        try PropertyListSerialization.data(fromPropertyList: translations, format: .binary, options: 0).write(to: table)
        let messages = try MemoryPanelWindowVerification.warningMessages(resources: root)
        precondition(messages == ["Memory warning", "メモリの警告"])
        try FileManager.default.removeItem(at: table)
        let legacy = root.appendingPathComponent("en.lproj")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let legacyTable = legacy.appendingPathComponent("LowMemoryPanel.strings")
        try PropertyListSerialization.data(
            fromPropertyList: ["100009.title": "Legacy warning"], format: .xml, options: 0
        )
        .write(to: legacyTable)
        let legacyMessages = try MemoryPanelWindowVerification.warningMessages(resources: root)
        precondition(legacyMessages == ["Legacy warning"])
        try FileManager.default.removeItem(at: legacyTable)
        do {
            _ = try MemoryPanelWindowVerification.warningMessages(resources: root)
            preconditionFailure("Unknown system resources must not imply support")
        } catch { precondition((error as NSError).code == 3) }
        var polls = 0
        var sharedDeadline: ContinuousClock.Instant?
        try await MemoryPanelWindowVerification.wait { deadline in
            if let sharedDeadline { precondition(deadline == sharedDeadline) }
            sharedDeadline = deadline
            polls += 1
            return polls == 2
        }
        precondition(polls == 2)
        do {
            try await MemoryPanelWindowVerification.wait(timeout: .milliseconds(10)) { _ in
                try await Task.sleep(for: .milliseconds(50))
                return true
            }
            preconditionFailure("A result received after the deadline must not succeed")
        } catch { precondition((error as NSError).code == 4) }
        do {
            try await MemoryPanelWindowVerification.wait(timeout: .zero) { _ in
                preconditionFailure("An expired check must not query the system")
            }
            preconditionFailure("An absent panel must fail")
        } catch { precondition((error as NSError).code == 4) }
        var waiting = false
        let cancelled = Task { @MainActor in
            try await MemoryPanelWindowVerification.wait { _ in
                waiting = true
                return false
            }
        }
        while !waiting { await Task.yield() }
        cancelled.cancel()
        do {
            try await cancelled.value
            preconditionFailure("Cancelled checks must stop")
        } catch { precondition(error is CancellationError) }
        var query: CheckedContinuation<Bool, Never>?
        let cancelledDuringQuery = Task { @MainActor in
            try await MemoryPanelWindowVerification.wait { _ in
                await withCheckedContinuation { query = $0 }
            }
        }
        while query == nil { await Task.yield() }
        cancelledDuringQuery.cancel()
        query?.resume(returning: true)
        do {
            try await cancelledDuringQuery.value
            preconditionFailure("A cancelled query must not return success")
        } catch { precondition(error is CancellationError) }
    }

}
