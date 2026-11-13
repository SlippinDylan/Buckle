import Darwin
import Foundation
import OSLog

enum CommandFailure: LocalizedError {
    case exited(executable: String, status: Int32, output: String)
    case timedOut(executable: String)
    case signalled(executable: String, signal: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .exited(let executable, let status, let output), .signalled(let executable, let status, let output):
            localizedFormat("command.failed", URL(fileURLWithPath: executable).lastPathComponent)
                + " (\(status))\n" + output
        case .timedOut(let executable):
            localizedFormat("command.timeout", URL(fileURLWithPath: executable).lastPathComponent)
        }
    }
}

enum CommandRunner {
    enum CompletionPolicy: Sendable {
        case deadline(Duration)
        // Stopping an authorization client cannot prove that its privileged work has stopped.
        case waitForExit
    }

    static func run(
        _ executable: String, arguments: [String], timeout: Duration = .seconds(15)
    ) async throws -> String {
        try await run(executable, arguments: arguments, completion: .deadline(timeout))
    }

    static func run(
        _ executable: String, arguments: [String], completion: CompletionPolicy
    ) async throws -> String {
        try await CommandExecution(executable: executable, arguments: arguments, policy: completion).run()
    }
}

private actor CommandExecution {
    private enum StopReason { case cancelled, timedOut }
    private let executable: String
    private let arguments: [String]
    private let policy: CommandRunner.CompletionPolicy
    private let logger = Logger(subsystem: "studio.slippindylan.Buckle", category: "Command")
    private var output: FileHandle?
    private var completion: CheckedContinuation<String, Error>?
    private var deadline: Task<Void, Never>?
    private var escalation: Task<Void, Never>?
    private var stopReason: StopReason?
    private var processID: pid_t = 0
    private var exitStatus: Int32?
    private let started = ContinuousClock.now

    init(executable: String, arguments: [String], policy: CommandRunner.CompletionPolicy) {
        self.executable = executable
        self.arguments = arguments
        self.policy = policy
    }

    func run() async throws -> String {
        try Task.checkCancellation()
        // An anonymous file avoids pipe back-pressure and inherited-descriptor EOF waits.
        var template = Array(URL.temporaryDirectory.appendingPathComponent("buckle-command-XXXXXX").path.utf8CString)
        let descriptor = mkstemp(&template)
        guard descriptor >= 0 else { throw posixError(errno) }
        guard unlink(template) == 0 else {
            let code = errno
            close(descriptor)
            throw posixError(code)
        }
        output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                completion = continuation
                do {
                    processID = try spawn(output: descriptor)
                    let child = processID
                    DispatchQueue.global(qos: .utility).async {
                        var status: Int32 = 0
                        var result: pid_t
                        repeat { result = waitpid(child, &status, 0) } while result < 0 && errno == EINTR
                        let waitError = result < 0 ? errno : nil
                        let finalStatus = status
                        Task { await self.finished(status: finalStatus, waitError: waitError) }
                    }
                    if case .deadline(let timeout) = policy {
                        deadline = Task {
                            do { try await Task.sleep(for: timeout) } catch { return }
                            stop(.timedOut)
                        }
                    }
                } catch {
                    completion = nil
                    output = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.stop(.cancelled) }
        }
    }

    private func spawn(output descriptor: Int32) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        var actions: posix_spawn_file_actions_t?
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        // Create the group atomically at spawn: no parent/child setpgid race.
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)))
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        try check(posix_spawn_file_actions_adddup2(&actions, descriptor, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, descriptor, STDERR_FILENO))
        let strings = ([executable] + arguments).map { strdup($0) }
        defer { for string in strings { free(string) } }
        var argv = strings + [nil]
        let environment = ProcessInfo.processInfo.environment.map { strdup("\($0.key)=\($0.value)") }
        defer { for string in environment { free(string) } }
        var envp = environment + [nil]
        var child: pid_t = 0
        try check(posix_spawn(&child, executable, &actions, &attributes, &argv, &envp))
        return child
    }

    private func stop(_ reason: StopReason) {
        guard case .deadline = policy, completion != nil, stopReason == nil else { return }
        stopReason = reason
        signalGroup(SIGTERM)
        escalation = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            // The group can outlive its original process, so never gate escalation on the parent's exit.
            signalGroup(SIGKILL)
        }
    }

    private func signalGroup(_ signal: Int32) {
        if kill(-processID, signal) != 0 && errno != ESRCH {
            logger.error("Could not signal command group: errno=\(errno)")
        }
    }

    private func finished(status: Int32, waitError: Int32?) async {
        if let waitError {
            complete(.failure(posixError(waitError)))
            return
        }
        exitStatus = status
        if case .deadline = policy {
            // Keep owning descendants even when their parent exits first.
            while kill(-processID, 0) == 0 || errno == EPERM {
                // This cleanup wait is not cancelled before the owned group has stopped.
                do { try await Task.sleep(for: .milliseconds(20)) } catch {
                    preconditionFailure("Cleanup is not cancellable")
                }
            }
        }
        do {
            guard let output else { preconditionFailure("A launched command owns its output file") }
            try output.seek(toOffset: 0)
            let text = String(decoding: try output.readToEnd() ?? Data(), as: UTF8.self)
            try output.close()
            switch stopReason {
            case .cancelled: throw CancellationError()
            case .timedOut: throw CommandFailure.timedOut(executable: executable)
            case nil: break
            }
            let signal = status & 0x7f
            if signal != 0 { throw CommandFailure.signalled(executable: executable, signal: signal, output: text) }
            let code = (status >> 8) & 0xff
            guard code == 0 else { throw CommandFailure.exited(executable: executable, status: code, output: text) }
            complete(.success(text))
        } catch { complete(.failure(error)) }
    }

    private func complete(_ result: Result<String, Error>) {
        guard let completion else { preconditionFailure("A command completes exactly once") }
        self.completion = nil
        deadline?.cancel()
        escalation?.cancel()
        output = nil
        logger.info(
            "Command \(URL(fileURLWithPath: self.executable).lastPathComponent, privacy: .public) ended: status=\(self.exitStatus ?? -1), elapsed=\(String(describing: self.started.duration(to: .now)), privacy: .public)"
        )
        completion.resume(with: result)
    }

    private func posixError(_ code: Int32) -> NSError { NSError(domain: NSPOSIXErrorDomain, code: Int(code)) }
    private func check(_ code: Int32) throws {
        if code != 0 { throw posixError(code) }
    }
}
