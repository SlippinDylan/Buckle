import Foundation

@MainActor
private final class FakeRunningTool: MouseResetApplication {
    let bundleIdentifier: String?
    var localizedName: String? { bundleIdentifier }
    private static var nextPID: pid_t = 1
    let processIdentifier: pid_t
    let launchDate: Date? = Date()
    var isTerminated = false
    var refusesQuit = false
    var exitsImmediately = true
    var onTerminate: (() -> Void)?

    init(_ identifier: String) {
        bundleIdentifier = identifier
        processIdentifier = Self.nextPID
        Self.nextPID += 1
    }
    func terminate() -> Bool {
        onTerminate?()
        if refusesQuit { return false }
        if exitsImmediately { isTerminated = true }
        return true
    }
}

@MainActor
private final class FakeResetWorkspace: MouseResetWorkspace {
    var installed = [
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
    func permissions(requestPermission: Bool) async throws -> MemoryPanelPermissions {
        preconditionFailure("Quit recovery must not request permissions")
    }
    func trigger() async throws { preconditionFailure("Quit recovery must not open the memory window") }
}

@main
enum MouseResetCheck {
    private static let recoveryRoot = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    @MainActor private static func makeNativeReset(
        workspace: any MouseResetWorkspace, stopTimeout: Duration = .seconds(10),
        recovery: MouseResetRecoveryStore? = nil,
        settleServices: @escaping () async throws -> Void = {},
        configuredTools: @escaping () throws -> [MouseResetTool]
    ) -> NativeMouseReset {
        NativeMouseReset(
            workspace: workspace, stopTimeout: stopTimeout,
            recovery: recovery
                ?? MouseResetRecoveryStore(directory: recoveryRoot.appendingPathComponent(UUID().uuidString)),
            settleServices: settleServices, configuredTools: configuredTools)
    }

    @MainActor static func main() async {
        defer {
            if FileManager.default.fileExists(atPath: recoveryRoot.path) {
                do { try FileManager.default.removeItem(at: recoveryRoot) } catch { preconditionFailure("\(error)") }
            }
        }
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
                if step == .stoppingApplications {
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
        do {
            try await verifyServiceRefresh()
            try await verifyNormalResetOnlyRestartsRunningTools()
            try await verifyConfiguredApplications()
            try await verifyDurableRecovery()
        } catch { preconditionFailure("\(error)") }
        // Exercise the native reset implementation with only its OS boundary substituted.
        let workspace = FakeResetWorkspace()
        let moom = "com.manytricks.Moom"
        let monitorControl = "app.monitorcontrol.MonitorControl"
        let betterMouse = "com.naotanhaocan.BetterMouse"
        workspace.running[moom] = FakeRunningTool(moom)
        workspace.running[betterMouse] = FakeRunningTool(betterMouse)
        let native = makeNativeReset(workspace: workspace, configuredTools: { MouseResetTool.defaults })
        do {
            try await native.perform(.stoppingApplications)
            try await native.restoreApps()
            precondition(workspace.launches == [moom, betterMouse])
            precondition(workspace.running[betterMouse]?.isTerminated == false)

            // If the second app refuses to quit, restore the first app, not every installed tool.
            workspace.launches.removeAll()
            let refusing = FakeRunningTool(monitorControl)
            refusing.refusesQuit = true
            workspace.running[monitorControl] = refusing
            do {
                try await native.perform(.stoppingApplications)
                preconditionFailure("Expected refusal to quit")
            } catch {
                try await native.restoreApps()
                precondition(workspace.launches == [moom])
            }
        } catch { preconditionFailure("Unexpected native reset test error: \(error)") }
        let closedWorkspace = FakeResetWorkspace()
        let closedReset = makeNativeReset(workspace: closedWorkspace, configuredTools: { MouseResetTool.defaults })
        do {
            try await closedReset.perform(.stoppingApplications)
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
        let delayedReset = makeNativeReset(workspace: delayedWorkspace, configuredTools: { MouseResetTool.defaults })
        var recoveryFinished = false
        let recovering = Task { @MainActor in
            do {
                try await delayedReset.perform(.stoppingApplications)
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
        let timedReset = makeNativeReset(
            workspace: timedWorkspace, stopTimeout: .milliseconds(1), configuredTools: { MouseResetTool.defaults })
        do {
            try await timedReset.perform(.stoppingApplications)
            preconditionFailure("Expected quit timeout")
        } catch { precondition(error.localizedDescription.contains(localized("mouse.stop.timeout"))) }
        // A timeout is unresolved recovery, even when the process still looks alive.
        do {
            try await timedReset.restoreApps()
            preconditionFailure("Pending quit must not be reported as restored")
        } catch { precondition(error.localizedDescription.contains(localized("mouse.stop.timeout"))) }
        do {
            try await timedReset.perform(.stoppingApplications)
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
        let helperReset = makeNativeReset(workspace: helperWorkspace, configuredTools: { MouseResetTool.defaults })
        do {
            try await helperReset.perform(.stoppingApplications)
            try await helperReset.restoreApps()
            precondition(helperWorkspace.launches == [monitorControl])
        } catch { preconditionFailure("\(error)") }
        precondition(success.accessibilityLabel == "Buckle")
        precondition(controller.accessibilityLabel.contains(localized("mouse.failed")))
        print(
            "Mouse reset sequence, failures, recovery, duplicate prevention, and status symbols verified using fake operations."
        )
    }

    @MainActor private static func verifyServiceRefresh() async throws {
        var requested = false
        try await MouseResetServiceRefresh.preferences { executable, arguments, policy in
            precondition(executable == "/usr/bin/killall")
            precondition(arguments == ["-q", "-u", String(getuid()), "cfprefsd"])
            guard case .deadline = policy else { preconditionFailure("Preferences refresh must have a deadline") }
            requested = true
            throw CommandFailure.exited(executable: executable, status: 1, output: "")
        }
        precondition(requested)
        for error in [
            CommandFailure.exited(executable: "killall", status: 1, output: "permission denied"),
            CommandFailure.exited(executable: "killall", status: 2, output: ""),
            CommandFailure.timedOut(executable: "killall"),
        ] {
            do {
                try await MouseResetServiceRefresh.preferences { _, _, _ in throw error }
                preconditionFailure("A real service failure must propagate")
            } catch let actual { precondition(actual.localizedDescription == error.localizedDescription) }
        }
        try await MouseResetServiceRefresh.permissions { executable, arguments, policy in
            precondition(executable == "/usr/bin/osascript")
            precondition(arguments.count == 2 && arguments[0] == "-e")
            precondition(arguments[1].hasSuffix("with administrator privileges"))
            guard case .waitForExit = policy else { preconditionFailure("Await the actual privileged result") }
            try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
            _ = try await CommandRunner.run(
                "/usr/bin/osacompile",
                arguments: [
                    "-o", recoveryRoot.appendingPathComponent("service.scpt").path, "-e", arguments[1],
                ])
            return ""
        }
        // Exercise the actual fixed shell policy with harmless replacements, without authorization or services.
        for (replacement, expectedStatus) in [
            ("/bin/sh -c 'exit 1'", 0),
            ("/bin/sh -c 'printf denied >&2; exit 1'", 1),
            ("/bin/sh -c 'exit 2'", 2),
            ("/bin/sh -c 'exit 0'", 0),
        ] {
            let command = MouseResetServiceRefresh.permissionCommand.replacingOccurrences(
                of: "/usr/bin/killall -q tccd", with: replacement)
            do {
                _ = try await CommandRunner.run("/bin/sh", arguments: ["-c", command])
                precondition(expectedStatus == 0)
            } catch CommandFailure.exited(_, let status, let output) {
                precondition(status == expectedStatus && expectedStatus != 0)
                if status == 1 { precondition(output.contains("denied")) }
            }
        }
    }

    @MainActor private static func verifyNormalResetOnlyRestartsRunningTools() async throws {
        let moom = "com.manytricks.Moom"
        let betterMouse = "com.naotanhaocan.BetterMouse"
        let workspace = FakeResetWorkspace()
        workspace.running[moom] = FakeRunningTool(moom)
        workspace.running[betterMouse] = FakeRunningTool(betterMouse)
        let reset = makeNativeReset(workspace: workspace, configuredTools: { MouseResetTool.defaults })
        // Exercise only application steps; never execute preference or privileged system commands.
        for step: MouseResetStep in [.stoppingApplications, .restartingApplications, .checking] {
            try await reset.perform(step)
        }
        precondition(
            workspace.launches == [moom, betterMouse], "A normal reset must not start installed but closed tools")
        try await reset.restoreApps()
        precondition(workspace.launches == [moom, betterMouse], "Successful resets must leave no pending restarts")

        let closedWorkspace = FakeResetWorkspace()
        let closedReset = makeNativeReset(workspace: closedWorkspace, configuredTools: { MouseResetTool.defaults })
        for step: MouseResetStep in [.stoppingApplications, .restartingApplications, .checking] {
            try await closedReset.perform(step)
        }
        precondition(closedWorkspace.launches.isEmpty, "Resetting services must not open any initially closed tools")

        let lateWorkspace = FakeResetWorkspace()
        lateWorkspace.running[moom] = FakeRunningTool(moom)
        let lateReset = makeNativeReset(workspace: lateWorkspace, configuredTools: { MouseResetTool.defaults })
        try await lateReset.perform(.stoppingApplications)
        let newlyOpened = FakeRunningTool(betterMouse)
        lateWorkspace.running[betterMouse] = newlyOpened
        try await lateReset.perform(.restartingApplications)
        try await lateReset.perform(.checking)
        precondition(!newlyOpened.isTerminated, "A reset must not stop a tool opened after its running snapshot")
        precondition(lateWorkspace.launches == [moom])
    }

    @MainActor private static func verifyConfiguredApplications() async throws {
        let selected = MouseResetTool(identifier: "example.CustomMouse", name: "Custom Mouse")
        let workspace = FakeResetWorkspace()
        workspace.installed.append(selected.identifier)
        let running = FakeRunningTool(selected.identifier)
        let excluded = FakeRunningTool("com.manytricks.Moom")
        workspace.running[selected.identifier] = running
        workspace.running["com.manytricks.Moom"] = excluded
        var configured = [selected]
        let reset = makeNativeReset(workspace: workspace, configuredTools: { configured })
        try await reset.perform(.stoppingApplications)
        precondition(running.isTerminated && !excluded.isTerminated && workspace.launches.isEmpty)
        // Later settings changes must not replace the running reset's recovery snapshot.
        configured = []
        try await reset.perform(.restartingApplications)
        try await reset.perform(.checking)
        precondition(workspace.launches == [selected.identifier])
        try await reset.restoreApps()
        precondition(workspace.launches == [selected.identifier])
        try await reset.perform(.stoppingApplications)
        try await reset.perform(.restartingApplications)
        try await reset.perform(.checking)
        precondition(!excluded.isTerminated)
    }

    private static func assertJournal(_ journal: MouseResetRecoveryStore, count: Int) throws {
        let saved = try journal.load()
        precondition(saved.count == count)
    }

    @MainActor private static func verifyDurableRecovery() async throws {
        let moom = "com.manytricks.Moom"
        let workspace = FakeResetWorkspace()
        let original = FakeRunningTool(moom)
        workspace.running[moom] = original
        let journal = MouseResetRecoveryStore(directory: recoveryRoot.appendingPathComponent("interrupted"))
        original.onTerminate = {
            do {
                let saved = try journal.load()
                precondition(saved.count == 1 && saved[0].processIdentifier == original.processIdentifier)
            } catch { preconditionFailure("Quit must not precede its recovery record: \(error)") }
        }
        let interrupted = makeNativeReset(
            workspace: workspace, recovery: journal, configuredTools: { MouseResetTool.defaults })
        try await interrupted.perform(.stoppingApplications)
        let restarted = makeNativeReset(workspace: workspace, recovery: journal, configuredTools: { [] })
        let controller = MouseResetController(operations: restarted)
        var prompted = false
        try await controller.recoverInterruptedReset {
            prompted = true
            return false
        }
        try await controller.recover()
        precondition(prompted && workspace.launches.isEmpty)
        try await controller.recoverInterruptedReset { true }
        precondition(workspace.launches == [moom])
        try assertJournal(journal, count: 0)

        // An accepted quit may finish after Buckle restarts. Never mistake it for recovery.
        let delayed = FakeRunningTool(moom)
        delayed.exitsImmediately = false
        workspace.running[moom] = delayed
        let reset = makeNativeReset(
            workspace: workspace, stopTimeout: .milliseconds(1), recovery: journal,
            configuredTools: { MouseResetTool.defaults })
        do {
            try await reset.perform(.stoppingApplications)
            preconditionFailure("Expected pending quit")
        } catch {}
        let recovering = makeNativeReset(
            workspace: workspace, stopTimeout: .milliseconds(1), recovery: journal, configuredTools: { [] })
        do {
            try await recovering.restoreInterruptedApps()
            preconditionFailure("The original process is still quitting")
        } catch {}
        try assertJournal(journal, count: 1)
        delayed.isTerminated = true
        workspace.launchFails = true
        do {
            try await recovering.restoreApps()
            preconditionFailure("Expected restart failure")
        } catch {}
        try assertJournal(journal, count: 1)
        workspace.launchFails = false
        try await recovering.restoreApps()
        try assertJournal(journal, count: 0)

        // A reused process number with a different launch date is not the pending original.
        let replacement = FakeRunningTool(moom)
        workspace.running[moom] = replacement
        try journal.save([
            .init(
                tool: .init(id: moom, name: "Moom"), processIdentifier: replacement.processIdentifier,
                bundleIdentifier: moom, launchDate: .distantPast)
        ])
        let launchesBeforeReuse = workspace.launches.count
        let reused = makeNativeReset(
            workspace: workspace, stopTimeout: .milliseconds(1), recovery: journal, configuredTools: { [] })
        try await reused.restoreInterruptedApps()
        try assertJournal(journal, count: 0)
        precondition(!replacement.isTerminated && workspace.launches.count == launchesBeforeReuse)

        let invalid = Data("invalid mouse recovery record".utf8)
        try invalid.write(to: journal.directory.appendingPathComponent("pending.json"))
        do {
            try await reused.perform(.stoppingApplications)
            preconditionFailure("A damaged recovery record must not be replaced")
        } catch {
            let preserved = try Data(contentsOf: journal.directory.appendingPathComponent("pending.json"))
            precondition(preserved == invalid && !replacement.isTerminated)
        }
        try journal.save([])

        // Uninstalled apps are skipped at selection, restoration, and final verification.
        let removed = makeNativeReset(
            workspace: workspace, recovery: journal, configuredTools: { MouseResetTool.defaults })
        try await removed.perform(.stoppingApplications)
        workspace.installed = []
        try await removed.perform(.restartingApplications)
        try await removed.perform(.checking)
        try assertJournal(journal, count: 0)
        try await removed.perform(.stoppingApplications)
        try await removed.perform(.checking)

        let blockedDirectory = recoveryRoot.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedDirectory)
        let blockedWorkspace = FakeResetWorkspace()
        let untouched = FakeRunningTool(moom)
        blockedWorkspace.running[moom] = untouched
        let blocked = makeNativeReset(
            workspace: blockedWorkspace,
            recovery: MouseResetRecoveryStore(directory: blockedDirectory), configuredTools: { MouseResetTool.defaults }
        )
        do {
            try await blocked.perform(.stoppingApplications)
            preconditionFailure("Cannot overwrite unreadable recovery")
        } catch {}
        precondition(!untouched.isTerminated)

        var settled = false
        let settlingWorkspace = FakeResetWorkspace()
        settlingWorkspace.running[moom] = FakeRunningTool(moom)
        let settling = makeNativeReset(
            workspace: settlingWorkspace, settleServices: { settled = true },
            configuredTools: { MouseResetTool.defaults })
        try await settling.perform(.stoppingApplications)
        try await settling.perform(.restartingApplications)
        precondition(settled && settlingWorkspace.launches == [moom])
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
                        if requestDuringReset && step == .stoppingApplications {
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
                    precondition(operations.steps == [.stoppingApplications, .refreshingPreferences])
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
            let native = makeNativeReset(
                workspace: workspace, stopTimeout: .milliseconds(1), configuredTools: { MouseResetTool.defaults })
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
        let cleanMouse = MouseResetController(
            operations: makeNativeReset(workspace: FakeResetWorkspace(), configuredTools: { MouseResetTool.defaults }))
        let cleanRecovery = ApplicationRecovery(memoryPanel: cleanMemory, mouseReset: cleanMouse)
        let lifecycle = ApplicationLifecycle()
        precondition(lifecycle.requestTermination())
        let allowed = await lifecycle.resolveTermination(recover: cleanRecovery.restore) { _ in
            preconditionFailure("A clean exit must not ask for confirmation")
        }
        precondition(allowed)
    }
}
