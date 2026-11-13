import AppKit

@main
enum MenuBarRestartCheck {
    @MainActor static func main() async throws {
        try await verifyNativeRestart()
        await verifyController()
        print(
            "Menu bar restart success, failures, duplicate requests and quit coordination verified without signaling real processes."
        )
    }

    @MainActor private static func verifyNativeRestart() async throws {
        let original = FakeMenuBarApplication()
        let replacement = FakeMenuBarApplication()
        let workspace = FakeMenuBarWorkspace([original])
        original.onSignal = {
            original.isTerminated = true
            workspace.applicationsToReturn = [replacement]
        }
        try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
        precondition(original.signals == 1 && replacement.signals == 0)

        workspace.applicationsToReturn = []
        do {
            try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
            preconditionFailure("A missing SystemUIServer is not a successful restart")
        } catch { precondition((error as NSError).domain == "Buckle.MenuBarRestart") }

        let denied = FakeMenuBarApplication()
        denied.signalError = POSIXError(.EPERM)
        workspace.applicationsToReturn = [denied]
        do {
            try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
            preconditionFailure("Signal permission failures must propagate")
        } catch { precondition((error as NSError).code == Int(EPERM)) }

        let unchanged = FakeMenuBarApplication()
        workspace.applicationsToReturn = [unchanged]
        do {
            try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
            preconditionFailure("A signal alone does not prove restart")
        } catch { precondition(unchanged.signals == 1) }

        let stopped = FakeMenuBarApplication()
        stopped.onSignal = { stopped.isTerminated = true }
        workspace.applicationsToReturn = [stopped]
        do {
            try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
            preconditionFailure("The old process exiting without a replacement is not success")
        } catch { precondition((error as NSError).domain == "Buckle.MenuBarRestart") }

        let launching = FakeMenuBarApplication()
        launching.isFinishedLaunching = false
        let pending = FakeMenuBarApplication()
        pending.onSignal = {
            pending.isTerminated = true
            workspace.applicationsToReturn = [launching]
        }
        workspace.applicationsToReturn = [pending]
        do {
            try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
            preconditionFailure("The replacement must finish launching")
        } catch { precondition((error as NSError).domain == "Buckle.MenuBarRestart") }

        let delayedOriginal = FakeMenuBarApplication()
        let delayedReplacement = FakeMenuBarApplication()
        workspace.applicationsToReturn = [delayedOriginal]
        delayedOriginal.onSignal = {
            Task { @MainActor in
                await Task.yield()
                delayedOriginal.isTerminated = true
                workspace.applicationsToReturn = [delayedReplacement]
            }
        }
        try await NativeMenuBarRestart(workspace: workspace, timeout: .seconds(1)).restart()
        precondition(delayedOriginal.signals == 1 && delayedReplacement.signals == 0)

        let cancelledOriginal = FakeMenuBarApplication()
        workspace.applicationsToReturn = [cancelledOriginal]
        let cancelled = Task { try await NativeMenuBarRestart(workspace: workspace).restart() }
        while cancelledOriginal.signals == 0 { await Task.yield() }
        cancelled.cancel()
        do {
            try await cancelled.value
            preconditionFailure("Cancellation while waiting must propagate")
        } catch is CancellationError {
        } catch { preconditionFailure("Expected cancellation, received \(error)") }

        workspace.queryError = POSIXError(.EACCES)
        do {
            try await NativeMenuBarRestart(workspace: workspace, timeout: .zero).restart()
            preconditionFailure("Discovery failures must propagate")
        } catch { precondition((error as NSError).code == Int(EACCES)) }
    }

    @MainActor private static func verifyController() async {
        let operations = FakeMenuBarOperations()
        let lifecycle = ApplicationLifecycle()
        let controller = MenuBarRestartController(operations: operations, lifecycle: lifecycle)
        await controller.run()
        precondition(operations.calls == 1 && !controller.isRunning && controller.error == nil)

        operations.failure = POSIXError(.EPERM)
        await controller.run()
        precondition(operations.calls == 2 && controller.error != nil && !controller.isRunning)
        operations.failure = nil
        operations.shouldSuspend = true
        let task = Task { await controller.run() }
        while operations.resume == nil { await Task.yield() }
        precondition(controller.isRunning && controller.error == nil)
        await controller.run()
        precondition(operations.calls == 3)
        var readyToQuit = 0
        lifecycle.onReadyToTerminate = { readyToQuit += 1 }
        precondition(!lifecycle.requestTermination())
        operations.resume?.resume()
        operations.resume = nil
        await task.value
        precondition(readyToQuit == 1 && !controller.isRunning)
        await controller.run()
        precondition(operations.calls == 3)
        lifecycle.cancelTermination()
        operations.shouldSuspend = false
        await controller.run()
        precondition(operations.calls == 4 && controller.error == nil)
    }
}

@MainActor
private final class FakeMenuBarApplication: NSObject, MenuBarRestartApplication {
    var isTerminated = false
    var isFinishedLaunching = true
    var signals = 0
    var signalError: Error?
    var onSignal: (() -> Void)?

    func sendMenuBarTerminationSignal() throws {
        signals += 1
        if let signalError { throw signalError }
        onSignal?()
    }
}

@MainActor
private final class FakeMenuBarWorkspace: MenuBarRestartWorkspace {
    var applicationsToReturn: [any MenuBarRestartApplication]
    var queryError: Error?

    init(_ applications: [any MenuBarRestartApplication]) { applicationsToReturn = applications }

    func applications() throws -> [any MenuBarRestartApplication] {
        if let queryError { throw queryError }
        return applicationsToReturn
    }
}

@MainActor
private final class FakeMenuBarOperations: MenuBarRestartOperations {
    var calls = 0
    var failure: Error?
    var shouldSuspend = false
    var resume: CheckedContinuation<Void, Never>?

    func restart() async throws {
        calls += 1
        if shouldSuspend { await withCheckedContinuation { resume = $0 } }
        if let failure { throw failure }
    }
}
