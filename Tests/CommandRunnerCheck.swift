import Darwin
import Foundation

@main
enum CommandRunnerCheck {
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.count == 3, arguments[1] == "stubborn-child" {
            signal(SIGTERM, SIG_IGN)
            try String(getpid()).write(toFile: arguments[2], atomically: true, encoding: .utf8)
            try await Task.sleep(for: .seconds(30))
            return
        }
        let text = try await CommandRunner.run("/bin/sh", arguments: ["-c", "printf output; printf error >&2"])
        precondition(text == "outputerror")
        let large = try await CommandRunner.run("/usr/bin/head", arguments: ["-c", "262144", "/dev/zero"])
        precondition(large.utf8.count == 262144)
        do {
            _ = try await CommandRunner.run("/bin/sh", arguments: ["-c", "printf diagnostic >&2; exit 7"])
            preconditionFailure("A failed command must throw")
        } catch {
            guard case CommandFailure.exited(_, 7, let output) = error else {
                preconditionFailure("Expected exit status 7")
            }
            precondition(output.contains("diagnostic"))
        }
        do {
            _ = try await CommandRunner.run("/nonexistent/buckle-command", arguments: [])
            preconditionFailure("Launch failure must throw")
        } catch { precondition((error as NSError).domain == NSPOSIXErrorDomain) }
        let directory = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch {
                preconditionFailure("Cannot remove test files: \(error)")
            }
        }
        for cancel in [false, true] {
            let pidFile = directory.appendingPathComponent(UUID().uuidString)
            let started = ContinuousClock.now
            let command = Task {
                try await CommandRunner.run(
                    arguments[0], arguments: ["stubborn-child", pidFile.path],
                    timeout: cancel ? .seconds(10) : .seconds(1))
            }
            let readyDeadline = ContinuousClock.now.advanced(by: .seconds(5))
            while !FileManager.default.fileExists(atPath: pidFile.path) {
                precondition(ContinuousClock.now < readyDeadline, "Child did not start")
                try await Task.sleep(for: .milliseconds(10))
            }
            if cancel { command.cancel() }
            do {
                _ = try await command.value
                preconditionFailure("Timeout or cancellation must throw")
            } catch {
                if cancel {
                    precondition(error is CancellationError)
                } else {
                    precondition(
                        error.localizedDescription.contains(
                            localizedFormat("command.timeout", URL(fileURLWithPath: arguments[0]).lastPathComponent)))
                }
            }
            precondition(started.duration(to: .now) < .seconds(5))
            let text = try String(contentsOf: pidFile, encoding: .utf8)
            guard let pid = pid_t(text) else { preconditionFailure("Missing child PID") }
            precondition(kill(pid, 0) == -1 && errno == ESRCH, "The command child must be reaped before returning")
        }
        for parentWaits in [false, true] {
            let pidFile = directory.appendingPathComponent(UUID().uuidString)
            let marker = directory.appendingPathComponent(UUID().uuidString)
            let script = "trap '' TERM; echo $$ > \"$1\"; sleep 3; touch \"$2\""
            let command = Task {
                try await CommandRunner.run(
                    "/bin/sh",
                    arguments: [
                        "-c", "\"$1\" -c \"$2\" child \"$3\" \"$4\" & " + (parentWaits ? "wait" : "exit 0"),
                        "parent", "/bin/sh", script, pidFile.path, marker.path,
                    ], timeout: .milliseconds(300))
            }
            do {
                _ = try await command.value
                preconditionFailure("An active descendant must remain owned until stopped")
            } catch {
                guard case CommandFailure.timedOut = error else { preconditionFailure("Expected timeout: \(error)") }
            }
            precondition(FileManager.default.fileExists(atPath: pidFile.path), "Descendant must actually start")
            try await Task.sleep(for: .seconds(2))
            precondition(!FileManager.default.fileExists(atPath: marker.path), "Timed-out descendant continued working")
        }
        let authorizedReady = directory.appendingPathComponent("authorized-ready")
        let authorized = Task {
            try await CommandRunner.run(
                "/bin/sh", arguments: ["-c", "touch \"$1\"; sleep 0.2; printf finished", "test", authorizedReady.path],
                completion: .waitForExit)
        }
        let authorizationDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: authorizedReady.path) {
            precondition(ContinuousClock.now < authorizationDeadline, "Authorization substitute did not start")
            try await Task.sleep(for: .milliseconds(10))
        }
        authorized.cancel()
        let authorizedResult = try await authorized.value
        precondition(
            authorizedResult == "finished", "Authorization work must return its actual result after cancellation")
        print(
            "Command output, launch failure, nonzero exit, timeout, cancellation, and stubborn-child reaping verified.")
    }
}
