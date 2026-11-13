import ApplicationServices
import CoreFoundation
import Foundation

@MainActor
private final class FakePanelOperations: SystemMemoryPanelOperations {
    var value: CFPropertyList?
    var writes: [CFPropertyList?] = []
    var triggerFails = false
    var restoreFails = false
    var triggered = false
    var issue: MemoryPanelPermissionIssue?
    var permissionRequests: [Bool] = []
    var onTrigger: (() -> Void)?
    var suspendsPermissionCheck = false
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

    func permissionIssue(requestPermission: Bool) async throws -> MemoryPanelPermissionIssue? {
        permissionRequests.append(requestPermission)
        if !requestPermission && suspendsPermissionCheck {
            await withCheckedContinuation { permissionContinuation = $0 }
        }
        return issue
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
}
