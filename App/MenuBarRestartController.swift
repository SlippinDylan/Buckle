import AppKit
import Darwin
import Observation

@MainActor
protocol MenuBarRestartOperations {
    func restart() async throws
}

@MainActor @Observable
final class MenuBarRestartController {
    enum State {
        case idle, running, succeeded
        case failed(String)
    }

    private(set) var state: State = .idle {
        didSet { onStateChange?() }
    }
    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private let operations: any MenuBarRestartOperations
    @ObservationIgnored private let lifecycle: ApplicationLifecycle

    init(
        operations: any MenuBarRestartOperations = NativeMenuBarRestart(),
        lifecycle: ApplicationLifecycle = ApplicationLifecycle()
    ) {
        self.operations = operations
        self.lifecycle = lifecycle
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var error: String? {
        if case .failed(let message) = state { return message }
        return nil
    }

    func run() async {
        guard !isRunning, lifecycle.begin(.menuBarRestart) else { return }
        state = .running
        defer { lifecycle.end(.menuBarRestart) }
        do {
            try await operations.restart()
            state = .succeeded
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}

@MainActor
protocol MenuBarRestartApplication: NSObjectProtocol {
    var isTerminated: Bool { get }
    var isFinishedLaunching: Bool { get }
    func sendMenuBarTerminationSignal() throws
}

extension NSRunningApplication: MenuBarRestartApplication {
    func sendMenuBarTerminationSignal() throws {
        // Never allow kill's zero/negative PID semantics to target a process group.
        guard processIdentifier > 0 else { throw POSIXError(.EINVAL) }
        guard let owner = try menuBarProcessOwner(processIdentifier) else { return }
        guard owner == getuid() else { throw POSIXError(.EPERM) }
        guard kill(processIdentifier, SIGTERM) == 0 else {
            // The process can exit between discovery and signaling; the replacement is still verified below.
            if errno == ESRCH { return }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }
}

@MainActor
protocol MenuBarRestartWorkspace {
    func applications() throws -> [any MenuBarRestartApplication]
}

@MainActor
private struct NativeMenuBarRestartWorkspace: MenuBarRestartWorkspace {
    func applications() throws -> [any MenuBarRestartApplication] {
        try NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver")
            .filter {
                guard !$0.isTerminated else { return false }
                return try menuBarProcessOwner($0.processIdentifier) == getuid()
            }
    }
}

private func menuBarProcessOwner(_ pid: pid_t) throws -> uid_t? {
    var info = proc_bsdinfo()
    let size = MemoryLayout<proc_bsdinfo>.size
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else {
        if errno == ESRCH { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
    return info.pbi_uid
}

@MainActor
struct NativeMenuBarRestart: MenuBarRestartOperations {
    private let workspace: any MenuBarRestartWorkspace
    private let timeout: Duration

    init(workspace: any MenuBarRestartWorkspace = NativeMenuBarRestartWorkspace(), timeout: Duration = .seconds(10)) {
        self.workspace = workspace
        self.timeout = timeout
    }

    func restart() async throws {
        let original = try workspace.applications()
        guard !original.isEmpty else { throw failure(localized("menubar.restart.missing")) }
        for application in original { try application.sendMenuBarTerminationSignal() }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            if original.allSatisfy(\.isTerminated),
                try workspace.applications().contains(where: { candidate in
                    !candidate.isTerminated && candidate.isFinishedLaunching
                        && !original.contains(where: { $0.isEqual(candidate) })
                })
            {
                return
            }
            guard ContinuousClock.now < deadline else { throw failure(localized("menubar.restart.timeout")) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Buckle.MenuBarRestart", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
