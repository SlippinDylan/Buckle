import AppKit
import Observation

enum MouseResetStep: Int, CaseIterable {
    case stoppingWindowTools, refreshingPreferences, refreshingPermissions
    case restartingInputTools, restartingWindowTools, checking

    var titleKey: String {
        switch self {
        case .stoppingWindowTools: "mouse.step.stop"
        case .refreshingPreferences: "mouse.step.preferences"
        case .refreshingPermissions: "mouse.step.permissions"
        case .restartingInputTools: "mouse.step.input"
        case .restartingWindowTools: "mouse.step.windows"
        case .checking: "mouse.step.check"
        }
    }
}

@MainActor
protocol MouseResetOperations {
    func perform(_ step: MouseResetStep) async throws
    func restoreApps() async throws
}

@MainActor @Observable
final class MouseResetController {
    enum State {
        case idle
        case running(MouseResetStep)
        case succeeded
        case failed(MouseResetStep, String)
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private let operations: any MouseResetOperations
    @ObservationIgnored private let lifecycle: ApplicationLifecycle

    init(
        operations: any MouseResetOperations = NativeMouseReset(),
        lifecycle: ApplicationLifecycle = ApplicationLifecycle()
    ) {
        self.operations = operations
        self.lifecycle = lifecycle
    }

    var isPresented: Bool {
        if case .idle = state { return false }
        return true
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var symbol: String {
        switch state {
        case .idle: "rectangle.compress.vertical"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    var accessibilityLabel: String {
        switch state {
        case .idle: "Buckle"
        case .running(let step): "Buckle — " + localizedFormat("mouse.accessibility.running", localized(step.titleKey))
        case .succeeded: "Buckle — " + localized("mouse.success")
        case .failed: "Buckle — " + localized("mouse.failed")
        }
    }

    func run() async {
        guard !isPresented, lifecycle.begin(.mouseReset) else { return }
        defer { lifecycle.end(.mouseReset) }
        for step in MouseResetStep.allCases {
            state = .running(step)
            do {
                try await operations.perform(step)
            } catch {
                var message = error.localizedDescription
                do { try await recover() } catch {
                    message += "\n" + localized("mouse.restore.failed") + "\n" + error.localizedDescription
                }
                state = .failed(step, message)
                return
            }
        }
        state = .succeeded
    }

    // Recovery is also run at the quit boundary, after all operations have finished.
    func recover() async throws { try await operations.restoreApps() }

    func dismiss() {
        guard !isRunning else { return }
        state = .idle
    }
}

private actor ResetCommandRunner {
    func run(_ executable: String, arguments: [String]) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "Buckle.MouseReset", code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
    }
}

@MainActor
protocol MouseResetApplication: AnyObject {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }
    var isTerminated: Bool { get }
    func terminate() -> Bool
}

extension NSRunningApplication: MouseResetApplication {}

@MainActor
protocol MouseResetWorkspace {
    func applicationURL(for identifier: String) -> URL?
    func runningApplications(for identifier: String) -> [any MouseResetApplication]
    func launch(_ url: URL) async throws
}

@MainActor
private struct NativeMouseResetWorkspace: MouseResetWorkspace {
    func applicationURL(for identifier: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    }

    func runningApplications(for identifier: String) -> [any MouseResetApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
    }

    func launch(_ url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }
}

@MainActor
final class NativeMouseReset: MouseResetOperations {
    private struct Tool {
        let id: String
        let name: String
        let input: Bool
        let url: URL

        var bundleIdentifiers: [String] {
            id == "app.monitorcontrol.MonitorControl" ? [id, "app.monitorcontrol.MonitorControlHelper"] : [id]
        }
    }

    private var tools: [Tool] = []
    private var stopRequests: [(tool: Tool, application: any MouseResetApplication)] = []
    private let runner = ResetCommandRunner()
    private let workspace: any MouseResetWorkspace
    private let stopTimeout: Duration

    init(workspace: any MouseResetWorkspace = NativeMouseResetWorkspace(), stopTimeout: Duration = .seconds(10)) {
        self.workspace = workspace
        self.stopTimeout = stopTimeout
    }

    func perform(_ step: MouseResetStep) async throws {
        switch step {
        case .stoppingWindowTools:
            // A previous timeout must be resolved before a new reset can replace its recovery state.
            try await restoreApps()
            let candidates = [
                ("com.manytricks.Moom", "Moom", false),
                ("app.monitorcontrol.MonitorControl", "MonitorControl", false),
                ("com.naotanhaocan.BetterMouse", "BetterMouse", true),
                ("cn.better365.iShotPro", "iShot Pro", true),
            ]
            tools = candidates.compactMap { id, name, input in
                guard let url = workspace.applicationURL(for: id) else { return nil }
                return Tool(id: id, name: name, input: input, url: url)
            }
            guard !tools.isEmpty else { throw failure(localized("mouse.no.tools")) }
            try await stop(tools.filter { !$0.input })
        case .refreshingPreferences:
            try await runner.run("/usr/bin/killall", arguments: ["-u", String(getuid()), "cfprefsd"])
        case .refreshingPermissions:
            // Only this fixed command is elevated. No shell text comes from user input.
            try await runner.run(
                "/usr/bin/osascript",
                arguments: [
                    "-e", "do shell script \"/usr/bin/killall tccd\" with administrator privileges",
                ])
        case .restartingInputTools:
            let inputTools = tools.filter(\.input)
            try await stop(inputTools)
            try await launch(inputTools)
        case .restartingWindowTools:
            try await launch(tools.filter { !$0.input })
        case .checking:
            for tool in tools {
                guard
                    workspace.runningApplications(for: tool.id).contains(where: {
                        !$0.isTerminated
                    })
                else {
                    throw failure(localizedFormat("mouse.app.not.running", tool.name))
                }
            }
        }
    }

    func restoreApps() async throws {
        var failures: [String] = []
        for tool in tools {
            let pending = stopRequests.filter { $0.tool.id == tool.id }.map(\.application)
            guard !pending.isEmpty else { continue }
            do {
                try await waitForTermination(pending)
                try await launch([tool])
            } catch { failures.append("\(tool.name): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { throw failure(failures.joined(separator: "\n")) }
    }

    private func stop(_ tools: [Tool]) async throws {
        var failures: [String] = []
        requesting: for tool in tools {
            for identifier in tool.bundleIdentifiers {
                for app in workspace.runningApplications(for: identifier) where !app.isTerminated {
                    if app.terminate() {
                        stopRequests.append((tool, app))
                    } else if !app.isTerminated {
                        failures.append(
                            localizedFormat(
                                "quit.failed",
                                app.localizedName ?? app.bundleIdentifier ?? String(app.processIdentifier)))
                        break requesting
                    }
                }
            }
        }
        // Even a later refusal cannot abandon quit requests already accepted by other processes.
        do { try await waitForTermination(stopRequests.map(\.application)) } catch {
            failures.append(error.localizedDescription)
        }
        if !failures.isEmpty { throw failure(failures.joined(separator: "\n")) }
    }

    private func waitForTermination(_ apps: [any MouseResetApplication]) async throws {
        let deadline = ContinuousClock.now.advanced(by: stopTimeout)
        while apps.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else { throw failure(localized("mouse.stop.timeout")) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func launch(_ tools: [Tool]) async throws {
        for tool in tools {
            if !workspace.runningApplications(for: tool.id).contains(where: {
                !$0.isTerminated
            }) {
                try await workspace.launch(tool.url)
            }
            stopRequests.removeAll { $0.tool.id == tool.id }
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Buckle.MouseReset", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
