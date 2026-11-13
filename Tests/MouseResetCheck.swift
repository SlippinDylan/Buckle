import Foundation

@MainActor
private final class FakeRunningTool: MouseResetApplication {
    let bundleIdentifier: String?
    var localizedName: String? { bundleIdentifier }
    let processIdentifier: pid_t = 1
    var isTerminated = false
    var refusesQuit = false
    var exitsImmediately = true
    var onTerminate: (() -> Void)?

    init(_ identifier: String) { bundleIdentifier = identifier }
    func terminate() -> Bool {
        onTerminate?()
        if refusesQuit { return false }
        if exitsImmediately { isTerminated = true }
        return true
    }
}

@MainActor
private final class FakeResetWorkspace: MouseResetWorkspace {
    let installed = [
        "com.manytricks.Moom", "app.monitorcontrol.MonitorControl",
        "com.naotanhaocan.BetterMouse", "cn.better365.iShotPro",
    ]
    var running: [String: FakeRunningTool] = [:]
    var launches: [String] = []
    var launchFails = false

    func applicationURL(for identifier: String) -> URL? {
        installed.contains(identifier) ? URL(fileURLWithPath: "/Applications/\(identifier).app") : nil
    }
    func runningApplications(for identifier: String) -> [any MouseResetApplication] {
        running[identifier].map { [$0] } ?? []
    }
    func launch(_ url: URL) async throws {
        if launchFails {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "launch failure"])
        }
        let identifier = url.deletingPathExtension().lastPathComponent
        launches.append(identifier)
        running[identifier] = FakeRunningTool(identifier)
    }
}

@MainActor
private final class FakeResetOperations: MouseResetOperations {
    var steps: [MouseResetStep] = []
    var restored = false
    let failingStep: MouseResetStep?
    var restorationFails: Bool
    var restorationAttempts = 0
    var onPerform: ((MouseResetStep) -> Void)?
    var onRestore: (() -> Void)?

    init(failingStep: MouseResetStep? = nil, restorationFails: Bool = false) {
        self.failingStep = failingStep
        self.restorationFails = restorationFails
    }

    func perform(_ step: MouseResetStep) async throws {
        steps.append(step)
        onPerform?(step)
        if step == failingStep {
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Expected step failure"])
        }
    }

    func restoreApps() async throws {
        onRestore?()
        restorationAttempts += 1
        if restorationFails {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "Expected recovery failure"])
        }
        restored = true
    }
}

@MainActor
private final class FakeMemoryRecovery: SystemMemoryPanelOperations {
    var fails = false
    var restorations = 0

    func debugValue() -> CFPropertyList? { nil }
    func setDebugValue(_ value: CFPropertyList?) throws {
        restorations += 1
        if fails {
            throw NSError(domain: "Test", code: 2, userInfo: [NSLocalizedDescriptionKey: "memory recovery failure"])
        }
    }
    func permissionIssue(requestPermission: Bool) async throws -> MemoryPanelPermissionIssue? {
        preconditionFailure("Quit recovery must not request permissions")
    }
    func trigger() async throws { preconditionFailure("Quit recovery must not open the memory window") }
}

@main
enum MouseResetCheck {
    @MainActor static func main() async {
        let successfulOperations = FakeResetOperations()
        let success = MouseResetController(operations: successfulOperations)
        var symbols: [String] = []
        var labels: [String] = []
        success.onStateChange = {
            symbols.append(success.symbol)
            labels.append(success.accessibilityLabel)
        }
        await success.run()
        precondition(successfulOperations.steps == MouseResetStep.allCases)
        guard case .succeeded = success.state else { preconditionFailure("Expected success") }
        precondition(success.symbol == "checkmark.circle.fill")
        precondition(success.accessibilityLabel.contains(localized("mouse.success")))
        await success.run()
        precondition(successfulOperations.steps.count == MouseResetStep.allCases.count)
        success.dismiss()
        precondition(!success.isPresented)
        precondition(symbols.first == "arrow.triangle.2.circlepath")
        precondition(labels.first != labels.last)
        precondition(symbols.last == "rectangle.compress.vertical")

        for step in MouseResetStep.allCases {
            let operations = FakeResetOperations(failingStep: step)
            let controller = MouseResetController(operations: operations)
            await controller.run()
            precondition(operations.steps == Array(MouseResetStep.allCases.prefix(step.rawValue + 1)))
            precondition(operations.restored)
            guard case .failed(let failedStep, let message) = controller.state else {
                preconditionFailure("A failed operation must not report success")
            }
            precondition(failedStep == step && message.contains("Expected step failure"))
            precondition(controller.symbol == "exclamationmark.circle.fill")
        }

        let operations = FakeResetOperations(failingStep: .refreshingPermissions, restorationFails: true)
        let controller = MouseResetController(operations: operations)
        await controller.run()
        guard case .failed(_, let message) = controller.state else { preconditionFailure("Expected failure") }
        precondition(message.contains("Expected step failure") && message.contains("Expected recovery failure"))
        for failingStep: MouseResetStep? in [nil, .refreshingPermissions] {
            let lifecycle = ApplicationLifecycle()
            let operations = FakeResetOperations(failingStep: failingStep)
            let reset = MouseResetController(operations: operations, lifecycle: lifecycle)
            var replied = false
            operations.onPerform = { step in
                if step == .stoppingWindowTools {
                    precondition(!lifecycle.requestTermination())
                }
                precondition(lifecycle.isActive(.mouseReset) && !replied)
            }
            operations.onRestore = {
                precondition(lifecycle.isActive(.mouseReset) && !replied)
            }
            lifecycle.onReadyToTerminate = {
                precondition(!reset.isRunning)
                if failingStep != nil { precondition(operations.restored) }
                replied = true
            }
            await reset.run()
            precondition(replied)
            reset.dismiss()
            await reset.run()
            precondition(!reset.isPresented)
        }
        // Exercise the native reset implementation with only its OS boundary substituted.
        let workspace = FakeResetWorkspace()
        let moom = "com.manytricks.Moom"
        let monitorControl = "app.monitorcontrol.MonitorControl"
        let betterMouse = "com.naotanhaocan.BetterMouse"
        workspace.running[moom] = FakeRunningTool(moom)
        workspace.running[betterMouse] = FakeRunningTool(betterMouse)
        let native = NativeMouseReset(workspace: workspace)
        do {
            try await native.perform(.stoppingWindowTools)
            try await native.restoreApps()
            precondition(workspace.launches == [moom])
            precondition(workspace.running[betterMouse]?.isTerminated == false)

            // If the second app refuses to quit, restore the first app, not every installed tool.
            workspace.launches.removeAll()
            let refusing = FakeRunningTool(monitorControl)
            refusing.refusesQuit = true
            workspace.running[monitorControl] = refusing
            do {
                try await native.perform(.stoppingWindowTools)
                preconditionFailure("Expected refusal to quit")
            } catch {
                try await native.restoreApps()
                precondition(workspace.launches == [moom])
            }
        } catch { preconditionFailure("Unexpected native reset test error: \(error)") }
        let closedWorkspace = FakeResetWorkspace()
        let closedReset = NativeMouseReset(workspace: closedWorkspace)
        do {
            try await closedReset.perform(.stoppingWindowTools)
            try await closedReset.restoreApps()
            precondition(closedWorkspace.launches.isEmpty)
        } catch { preconditionFailure("Unexpected recovery error: \(error)") }
        let delayedWorkspace = FakeResetWorkspace()
        let delayed = FakeRunningTool(moom)
        delayed.exitsImmediately = false
        let refusing = FakeRunningTool(monitorControl)
        refusing.refusesQuit = true
        var refusalSent = false
        refusing.onTerminate = { refusalSent = true }
        delayedWorkspace.running[moom] = delayed
        delayedWorkspace.running[monitorControl] = refusing
        let delayedReset = NativeMouseReset(workspace: delayedWorkspace)
        var recoveryFinished = false
        let recovering = Task { @MainActor in
            do {
                try await delayedReset.perform(.stoppingWindowTools)
                preconditionFailure("Expected refusal to quit")
            } catch {
                do { try await delayedReset.restoreApps() } catch { preconditionFailure("\(error)") }
            }
            recoveryFinished = true
        }
        while !refusalSent { await Task.yield() }
        precondition(!recoveryFinished, "Recovery must wait for an accepted quit to actually finish")
        delayed.isTerminated = true
        await recovering.value
        precondition(delayedWorkspace.launches == [moom])
        let timedWorkspace = FakeResetWorkspace()
        let pending = FakeRunningTool(moom)
        pending.exitsImmediately = false
        timedWorkspace.running[moom] = pending
        let timedReset = NativeMouseReset(workspace: timedWorkspace, stopTimeout: .milliseconds(1))
        do {
            try await timedReset.perform(.stoppingWindowTools)
            preconditionFailure("Expected quit timeout")
        } catch { precondition(error.localizedDescription.contains(localized("mouse.stop.timeout"))) }
        // A timeout is unresolved recovery, even when the process still looks alive.
        do {
            try await timedReset.restoreApps()
            preconditionFailure("Pending quit must not be reported as restored")
        } catch { precondition(error.localizedDescription.contains(localized("mouse.stop.timeout"))) }
        do {
            try await timedReset.perform(.stoppingWindowTools)
            preconditionFailure("A new reset must not discard pending recovery")
        } catch { precondition(error.localizedDescription.contains(localized("mouse.stop.timeout"))) }
        precondition(timedWorkspace.launches.isEmpty)
        pending.isTerminated = true
        do {
            try await timedReset.restoreApps()
            precondition(timedWorkspace.launches == [moom])
        } catch { preconditionFailure("\(error)") }
        do { try await verifyTerminationRecovery() } catch { preconditionFailure("\(error)") }
        let helperWorkspace = FakeResetWorkspace()
        let helperID = "app.monitorcontrol.MonitorControlHelper"
        helperWorkspace.running[helperID] = FakeRunningTool(helperID)
        let helperReset = NativeMouseReset(workspace: helperWorkspace)
        do {
            try await helperReset.perform(.stoppingWindowTools)
            try await helperReset.restoreApps()
            precondition(helperWorkspace.launches == [monitorControl])
        } catch { preconditionFailure("\(error)") }
        precondition(success.accessibilityLabel == "Buckle")
        precondition(controller.accessibilityLabel.contains(localized("mouse.failed")))
        print(
            "Mouse reset sequence, failures, recovery, duplicate prevention, and status symbols verified using fake operations."
        )
    }

    @MainActor private static func verifyTerminationRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") }
        }
        for requestDuringReset in [false, true] {
            for memoryFails in [false, true] {
                for choice in [ApplicationLifecycle.RecoveryDecision.cancel, .retry, .quit] {
                    let lifecycle = ApplicationLifecycle()
                    let operations = FakeResetOperations(failingStep: .refreshingPreferences, restorationFails: true)
                    let mouse = MouseResetController(operations: operations, lifecycle: lifecycle)
                    let memoryOperations = FakeMemoryRecovery()
                    memoryOperations.fails = memoryFails
                    let journal = MemoryPanelRecoveryStore(directory: root.appendingPathComponent(UUID().uuidString))
                    try journal.save(original: kCFBooleanFalse)
                    let memory = SystemMemoryPanel(
                        operations: memoryOperations, lifecycle: lifecycle, recovery: journal)
                    let recovery = ApplicationRecovery(memoryPanel: memory, mouseReset: mouse)
                    var prompted = 0
                    var resolution: Task<Bool, Never>?
                    let resolve = {
                        resolution = Task { @MainActor in
                            await lifecycle.resolveTermination(recover: recovery.restore) { failure in
                                prompted += 1
                                precondition(failure.includesMemory == memoryFails)
                                precondition(failure.localizedDescription.contains("Expected recovery failure"))
                                if choice == .retry {
                                    operations.restorationFails = false
                                    memoryOperations.fails = false
                                }
                                return choice
                            }
                        }
                    }
                    lifecycle.onReadyToTerminate = resolve
                    operations.onPerform = { step in
                        if requestDuringReset && step == .stoppingWindowTools {
                            precondition(!lifecycle.requestTermination())
                        }
                    }
                    await mouse.run()
                    if !requestDuringReset {
                        precondition(lifecycle.requestTermination())
                        resolve()
                    }
                    guard let resolution else { preconditionFailure("Expected quit recovery") }
                    let allowed = await resolution.value
                    precondition(prompted == 1 && allowed == (choice != .cancel))
                    precondition(operations.restorationAttempts == (choice == .retry ? 3 : 2))
                    precondition(operations.steps == [.stoppingWindowTools, .refreshingPreferences])
                    let pending = try journal.load()
                    precondition((pending != nil) == (memoryFails && choice != .retry))
                    if choice == .cancel {
                        precondition(!lifecycle.terminationRequested)
                        operations.restorationFails = false
                        memoryOperations.fails = false
                        mouse.dismiss()
                        precondition(lifecycle.requestTermination())
                        let retried = await lifecycle.resolveTermination(recover: recovery.restore) { _ in
                            preconditionFailure("Recovery should now succeed")
                        }
                        precondition(retried && operations.restored)
                    }
                    lifecycle.onReadyToTerminate = nil
                }
            }
        }
        // Exercise the actual pending-process records, including a failed relaunch.
        for launchFails in [false, true] {
            let lifecycle = ApplicationLifecycle()
            let workspace = FakeResetWorkspace()
            let moom = FakeRunningTool("com.manytricks.Moom")
            moom.exitsImmediately = launchFails
            moom.onTerminate = { precondition(!lifecycle.requestTermination()) }
            workspace.running["com.manytricks.Moom"] = moom
            workspace.launchFails = launchFails
            if launchFails {
                let refusing = FakeRunningTool("app.monitorcontrol.MonitorControl")
                refusing.refusesQuit = true
                workspace.running["app.monitorcontrol.MonitorControl"] = refusing
            }
            let native = NativeMouseReset(workspace: workspace, stopTimeout: .milliseconds(1))
            let mouse = MouseResetController(operations: native, lifecycle: lifecycle)
            let journal = MemoryPanelRecoveryStore(directory: root.appendingPathComponent(UUID().uuidString))
            try journal.save(original: kCFBooleanFalse)
            let memory = SystemMemoryPanel(operations: FakeMemoryRecovery(), lifecycle: lifecycle, recovery: journal)
            let recovery = ApplicationRecovery(memoryPanel: memory, mouseReset: mouse)
            var resolution: Task<Bool, Never>?
            lifecycle.onReadyToTerminate = {
                resolution = Task {
                    await lifecycle.resolveTermination(recover: recovery.restore) { failure in
                        precondition(!failure.includesMemory)
                        return .cancel
                    }
                }
            }
            await mouse.run()
            guard let resolution else { preconditionFailure("Expected pending quit to resolve") }
            let allowed = await resolution.value
            precondition(!allowed && !lifecycle.terminationRequested && workspace.launches.isEmpty)
            moom.isTerminated = true
            workspace.launchFails = false
            mouse.dismiss()
            precondition(lifecycle.requestTermination())
            let recovered = await lifecycle.resolveTermination(recover: recovery.restore) { _ in
                preconditionFailure("Pending native recovery must survive canceling quit")
            }
            precondition(recovered && workspace.launches == ["com.manytricks.Moom"])
            lifecycle.onReadyToTerminate = nil
        }
        let journal = MemoryPanelRecoveryStore(directory: root.appendingPathComponent("memory-only"))
        try journal.save(original: kCFBooleanFalse)
        let file = journal.directory.appendingPathComponent("pending.plist")
        let invalid = Data("corrupt memory journal".utf8)
        try invalid.write(to: file)
        let mouseOperations = FakeResetOperations()
        let memory = SystemMemoryPanel(operations: FakeMemoryRecovery(), recovery: journal)
        let mouse = MouseResetController(operations: mouseOperations)
        let recovery = ApplicationRecovery(memoryPanel: memory, mouseReset: mouse)
        do {
            try await recovery.restore()
            preconditionFailure("A corrupt memory journal must be reported")
        } catch {
            guard case .memory = error else { preconditionFailure("Expected only the memory recovery failure") }
            precondition(mouseOperations.restorationAttempts == 1)
            let preserved = try Data(contentsOf: file)
            precondition(preserved == invalid)
        }
        let cleanMemory = SystemMemoryPanel(
            operations: FakeMemoryRecovery(),
            recovery: MemoryPanelRecoveryStore(directory: root.appendingPathComponent("clean")))
        let cleanMouse = MouseResetController(operations: NativeMouseReset(workspace: FakeResetWorkspace()))
        let cleanRecovery = ApplicationRecovery(memoryPanel: cleanMemory, mouseReset: cleanMouse)
        let lifecycle = ApplicationLifecycle()
        precondition(lifecycle.requestTermination())
        let allowed = await lifecycle.resolveTermination(recover: cleanRecovery.restore) { _ in
            preconditionFailure("A clean exit must not ask for confirmation")
        }
        precondition(allowed)
    }
}
