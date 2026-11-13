import AppKit
import Observation

enum MouseResetStep: Int, CaseIterable {
    case stoppingApplications, refreshingPreferences, refreshingPermissions
    case restartingApplications, checking

    var titleKey: String {
        switch self {
        case .stoppingApplications: "mouse.step.stop"
        case .refreshingPreferences: "mouse.step.preferences"
        case .refreshingPermissions: "mouse.step.permissions"
        case .restartingApplications: "mouse.step.restart"
        case .checking: "mouse.step.check"
        }
    }
}

@MainActor
protocol MouseResetOperations {
    func perform(_ step: MouseResetStep) async throws
    func restoreApps() async throws
    func hasInterruptedRecovery() throws -> Bool
    func restoreInterruptedApps() async throws
}

extension MouseResetOperations {
    func hasInterruptedRecovery() throws -> Bool { false }
    func restoreInterruptedApps() async throws { try await restoreApps() }
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

    func recoverInterruptedReset(confirm: () -> Bool) async throws {
        guard try operations.hasInterruptedRecovery(), lifecycle.begin(.mouseReset) else { return }
        defer { lifecycle.end(.mouseReset) }
        guard confirm() else { return }
        try await operations.restoreInterruptedApps()
    }

    // Recovery is also run at the quit boundary, after all operations have finished.
    func recover() async throws { try await operations.restoreApps() }

    func dismiss() {
        guard !isRunning else { return }
        state = .idle
    }
}

@MainActor
protocol MouseResetApplication: AnyObject {
    var bundleIdentifier: String? { get }
    var localizedName: String? { get }
    var processIdentifier: pid_t { get }
    var launchDate: Date? { get }
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
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier),
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
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

struct MouseResetRecoveryStore {
    struct Application: Codable {
        let id: String
        let name: String
        var bundleIdentifiers: [String] {
            id == "app.monitorcontrol.MonitorControl" ? [id, "app.monitorcontrol.MonitorControlHelper"] : [id]
        }
    }

    struct Request: Codable {
        let tool: Application
        let processIdentifier: pid_t
        let bundleIdentifier: String?
        let launchDate: Date?
    }

    let directory: URL
    private var file: URL { directory.appendingPathComponent("pending.json") }

    func load() throws -> [Request] {
        let data: Data
        do { data = try Data(contentsOf: file) } catch CocoaError.fileReadNoSuchFile { return [] }
        let requests = try JSONDecoder().decode([Request].self, from: data)
        guard
            requests.allSatisfy({ request in
                !request.tool.id.isEmpty && request.tool.id != "studio.slippindylan.Buckle"
                    && request.processIdentifier > 0
                    && (request.bundleIdentifier.map { request.tool.bundleIdentifiers.contains($0) } ?? true)
            })
        else { throw CocoaError(.coderReadCorrupt) }
        return requests
    }

    func save(_ requests: [Request]) throws {
        if requests.isEmpty {
            do { try FileManager.default.removeItem(at: file) } catch CocoaError.fileNoSuchFile {}
            return
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(requests).write(to: file, options: .atomic)
    }
}

@MainActor
final class NativeMouseReset: MouseResetOperations {
    private typealias Tool = MouseResetRecoveryStore.Application
    private typealias StopRequest = MouseResetRecoveryStore.Request

    private struct RunningTool {
        let tool: Tool
        let applications: [any MouseResetApplication]
    }

    private var runningTools: [RunningTool] = []
    private var stopRequests: [StopRequest] = []
    private let workspace: any MouseResetWorkspace
    private let stopTimeout: Duration
    private let configuredTools: () throws -> [MouseResetTool]
    private let recovery: MouseResetRecoveryStore
    private let settleServices: () async throws -> Void

    init(
        workspace: any MouseResetWorkspace = NativeMouseResetWorkspace(), stopTimeout: Duration = .seconds(10),
        recovery: MouseResetRecoveryStore = MouseResetRecoveryStore(
            directory: URL.applicationSupportDirectory.appending(path: "Buckle/MouseReset")),
        settleServices: @escaping () async throws -> Void = { try await Task.sleep(for: .seconds(3)) },
        configuredTools: @escaping () throws -> [MouseResetTool] = { try MouseResetPreferences().load() }
    ) {
        self.workspace = workspace
        self.stopTimeout = stopTimeout
        self.configuredTools = configuredTools
        self.recovery = recovery
        self.settleServices = settleServices
    }

    func hasInterruptedRecovery() throws -> Bool { try !recovery.load().isEmpty }

    func restoreInterruptedApps() async throws {
        // Loading is explicit: declining startup recovery must not reopen apps at ordinary quit.
        stopRequests = try recovery.load()
        try await restoreApps()
    }

    func perform(_ step: MouseResetStep) async throws {
        switch step {
        case .stoppingApplications:
            // Resolve durable recovery before a new reset can replace its records.
            try await restoreInterruptedApps()
            let tools = try configuredTools().compactMap { candidate -> Tool? in
                guard workspace.applicationURL(for: candidate.identifier) != nil else { return nil }
                return Tool(id: candidate.identifier, name: candidate.name)
            }
            runningTools = tools.compactMap { tool in
                let applications = tool.bundleIdentifiers.flatMap { workspace.runningApplications(for: $0) }
                    .filter { !$0.isTerminated }
                guard !applications.isEmpty else { return nil }
                return RunningTool(tool: tool, applications: applications)
            }
            try await stop(runningTools)
        case .refreshingPreferences:
            try await MouseResetServiceRefresh.preferences()
        case .refreshingPermissions:
            try await MouseResetServiceRefresh.permissions()
        case .restartingApplications:
            // Match the original script's settling interval after refreshing both shared services.
            try await settleServices()
            try await restoreApps()
        case .checking:
            for snapshot in runningTools {
                let tool = snapshot.tool
                guard workspace.applicationURL(for: tool.id) != nil else { continue }
                guard workspace.runningApplications(for: tool.id).contains(where: { !$0.isTerminated }) else {
                    throw failure(localizedFormat("mouse.app.not.running", tool.name))
                }
            }
        }
    }

    func restoreApps() async throws {
        var failures: [String] = []
        var restored = Set<String>()
        for request in stopRequests where restored.insert(request.tool.id).inserted {
            let tool = request.tool
            do {
                guard let url = workspace.applicationURL(for: tool.id) else {
                    try removeRequests(for: tool.id)
                    continue
                }
                let pending = stopRequests.filter { $0.tool.id == tool.id }.flatMap { request in
                    tool.bundleIdentifiers.flatMap { workspace.runningApplications(for: $0) }.filter {
                        $0.processIdentifier == request.processIdentifier
                            && (request.launchDate == nil || $0.launchDate == request.launchDate)
                            && (request.bundleIdentifier == nil || $0.bundleIdentifier == request.bundleIdentifier)
                    }
                }
                try await waitForTermination(pending)
                if !workspace.runningApplications(for: tool.id).contains(where: { !$0.isTerminated }) {
                    try await workspace.launch(url)
                }
                try removeRequests(for: tool.id)
            } catch { failures.append("\(tool.name): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { throw failure(failures.joined(separator: "\n")) }
    }

    private func removeRequests(for identifier: String) throws {
        try updateRequests(stopRequests.filter { $0.tool.id != identifier })
    }

    private func updateRequests(_ requests: [StopRequest]) throws {
        try recovery.save(requests)
        stopRequests = requests
    }

    private func stop(_ snapshots: [RunningTool]) async throws {
        var failures: [String] = []
        do {
            requesting: for snapshot in snapshots {
                for app in snapshot.applications where !app.isTerminated {
                    let request = StopRequest(
                        tool: snapshot.tool, processIdentifier: app.processIdentifier,
                        bundleIdentifier: app.bundleIdentifier, launchDate: app.launchDate)
                    // The original process identity must reach disk before its quit request is sent.
                    try updateRequests(stopRequests + [request])
                    if !app.terminate() {
                        try updateRequests(Array(stopRequests.dropLast()))
                        if !app.isTerminated {
                            failures.append(
                                localizedFormat(
                                    "quit.failed",
                                    app.localizedName ?? app.bundleIdentifier ?? String(app.processIdentifier)))
                            break requesting
                        }
                    }
                }
            }
        } catch { failures.append(error.localizedDescription) }
        // Even a later refusal or journal error cannot abandon earlier accepted quit requests.
        let pending = stopRequests.flatMap { request in
            snapshots.flatMap(\.applications).filter {
                $0.processIdentifier == request.processIdentifier && $0.bundleIdentifier == request.bundleIdentifier
                    && $0.launchDate == request.launchDate
            }
        }
        do { try await waitForTermination(pending) } catch { failures.append(error.localizedDescription) }
        if !failures.isEmpty { throw failure(failures.joined(separator: "\n")) }
    }

    private func waitForTermination(_ apps: [any MouseResetApplication]) async throws {
        let deadline = ContinuousClock.now.advanced(by: stopTimeout)
        while apps.contains(where: { !$0.isTerminated }) {
            guard ContinuousClock.now < deadline else { throw failure(localized("mouse.stop.timeout")) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Buckle.MouseReset", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

@MainActor
enum MouseResetServiceRefresh {
    typealias Execute = (String, [String], CommandRunner.CompletionPolicy) async throws -> String

    // killall -q suppresses only the no-match diagnostic; permission and signalling failures retain output.
    static let permissionCommand = """
        output=$(/usr/bin/killall -q tccd 2>&1)
        status=$?
        if [ "$status" -eq 1 ] && [ -z "$output" ]; then exit 0; fi
        printf '%s' "$output" >&2
        exit "$status"
        """

    static func preferences(execute: Execute = executeCommand) async throws {
        do {
            _ = try await execute(
                "/usr/bin/killall", ["-q", "-u", String(getuid()), "cfprefsd"], .deadline(.seconds(15)))
        } catch CommandFailure.exited(_, 1, let output) where output.isEmpty {
            // An already stopped service is a completed stop, not a failure.
        }
    }

    static func permissions(execute: Execute = executeCommand) async throws {
        // Only this fixed command is elevated; no user input becomes shell or AppleScript text.
        let literal = permissionCommand.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        _ = try await execute(
            "/usr/bin/osascript", ["-e", "do shell script \"\(literal)\" with administrator privileges"], .waitForExit)
    }

    private static func executeCommand(
        _ executable: String, _ arguments: [String], _ completion: CommandRunner.CompletionPolicy
    ) async throws -> String {
        try await CommandRunner.run(executable, arguments: arguments, completion: completion)
    }
}
