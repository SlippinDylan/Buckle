import AppKit
import Synchronization

struct FinderMovePlan: Equatable, Sendable {
    let sources: [URL]
    let destination: URL

    init(sources: [URL], destination: URL) throws {
        guard !sources.isEmpty,
            (sources + [destination]).allSatisfy({
                $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")
            })
        else {
            throw FinderActionRequest.RequestError.invalidFiles
        }
        self.sources = sources
        self.destination = destination
    }

    func validate() throws {
        guard try FinderMenuContext.items([destination]).directory() != nil else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let target = destination.resolvingSymlinksInPath().standardizedFileURL
        let sourcePaths = Set(
            sources.map {
                $0.deletingLastPathComponent().resolvingSymlinksInPath()
                    .appendingPathComponent($0.lastPathComponent).standardizedFileURL.path
            })
        for source in sources {
            _ = try source.resourceValues(forKeys: [.fileResourceIdentifierKey])
            // Resolve ancestor directories, while keeping a symbolic-link source itself as the item to move.
            let resolved = source.deletingLastPathComponent().resolvingSymlinksInPath()
                .appendingPathComponent(source.lastPathComponent).standardizedFileURL
            guard resolved != target,
                !target.pathComponents.starts(with: resolved.pathComponents),
                resolved.deletingLastPathComponent() != target
            else { throw CocoaError(.fileWriteInvalidFileName) }
            var ancestor = resolved.deletingLastPathComponent()
            while ancestor.path != "/" {
                guard !sourcePaths.contains(ancestor.path) else { throw CocoaError(.fileWriteInvalidFileName) }
                ancestor.deleteLastPathComponent()
            }
            let result = destination.appendingPathComponent(source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: result.path) else { throw CocoaError(.fileWriteFileExists) }
        }
        guard Set(sources.map(\.lastPathComponent)).count == sources.count else {
            throw CocoaError(.fileWriteFileExists)
        }
    }
}

actor FinderMoveRunner {
    private let coordinationTimeout: Duration

    init(coordinationTimeout: Duration = .seconds(15)) {
        self.coordinationTimeout = coordinationTimeout
    }

    func move(_ plan: FinderMovePlan) async throws {
        do {
            try Task.checkCancellation()
            try plan.validate()
            for source in plan.sources {
                try Task.checkCancellation()
                let target = plan.destination.appendingPathComponent(source.lastPathComponent)
                try await FinderMoveCoordination().move(source, to: target, timeout: coordinationTimeout)
            }
        } catch {
            throw NSError(
                domain: "Buckle.FinderMove", code: (error as NSError).code,
                userInfo: [
                    NSLocalizedDescriptionKey: localized("finder.move.failed") + "\n" + error.localizedDescription,
                    NSUnderlyingErrorKey: error,
                ])
        }
    }
}

private final class FinderMoveCoordination: Sendable {
    private enum StopReason {
        case cancelled, timedOut

        var error: Error {
            switch self {
            case .cancelled: CocoaError(.userCancelled)
            case .timedOut: URLError(.timedOut)
            }
        }
    }

    private struct State {
        let coordinator = NSFileCoordinator()
        var isWaiting = true
        var stopReason: StopReason?
    }

    // Coordination starts under the lock; only cancel(), explicitly thread-safe in Foundation, crosses threads.
    private let state = Mutex(State())

    func move(_ source: URL, to target: URL, timeout: Duration) async throws {
        let waitingDeadline = ContinuousClock.now.advanced(by: timeout)
        let deadline = Task {
            do { try await Task.sleep(until: waitingDeadline, clock: .continuous) } catch { return }
            stopWaiting(.timedOut)
        }
        defer { deadline.cancel() }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let intents = [
                    NSFileAccessIntent.writingIntent(with: source, options: .forMoving),
                    NSFileAccessIntent.writingIntent(with: target, options: []),
                ]
                let queue = OperationQueue()
                queue.maxConcurrentOperationCount = 1
                state.withLock { state in
                    if let reason = state.stopReason {
                        continuation.resume(throwing: reason.error)
                        return
                    }
                    state.coordinator.coordinate(with: intents, queue: queue) { error in
                        let result = self.state.withLock { state -> (NSFileCoordinator, StopReason?) in
                            if state.stopReason == nil, ContinuousClock.now >= waitingDeadline {
                                state.stopReason = .timedOut
                            }
                            state.isWaiting = false
                            return (state.coordinator, state.stopReason)
                        }
                        if let reason = result.1 {
                            continuation.resume(throwing: reason.error)
                            return
                        }
                        if let error {
                            continuation.resume(throwing: error)
                            return
                        }
                        do {
                            // Once admitted, finish the move even if cancellation arrives during copying.
                            let coordinatedSource = intents[0].url
                            let coordinatedTarget = intents[1].url
                            result.0.item(at: coordinatedSource, willMoveTo: coordinatedTarget)
                            try FileManager.default.moveItem(at: coordinatedSource, to: coordinatedTarget)
                            result.0.item(at: coordinatedSource, didMoveTo: coordinatedTarget)
                            continuation.resume()
                        } catch { continuation.resume(throwing: error) }
                    }
                }
            }
        } onCancel: {
            self.stopWaiting(.cancelled)
        }
    }

    private func stopWaiting(_ reason: StopReason) {
        let coordinator = state.withLock { state -> NSFileCoordinator? in
            guard state.isWaiting, state.stopReason == nil else { return nil }
            state.stopReason = reason
            return state.coordinator
        }
        coordinator?.cancel()
    }
}

@MainActor
enum FinderMoveConfirmation {
    static func confirm(_ plan: FinderMovePlan) -> Bool {
        let alert = NSAlert()
        alert.messageText = localized("finder.move.title")
        alert.informativeText =
            localized("finder.move.confirm") + "\n\n"
            + plan.sources.prefix(10).map(\.lastPathComponent).joined(separator: "\n")
            + (plan.sources.count > 10 ? "\n…" : "") + "\n→ " + plan.destination.path
        alert.addButton(withTitle: localized("cancel"))
        alert.addButton(withTitle: localized("finder.move.title"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn
    }
}
