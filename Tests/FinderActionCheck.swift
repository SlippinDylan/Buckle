import AppKit

@main
enum FinderActionCheck {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) } catch {
                preconditionFailure(error.localizedDescription)
            }
        }
        let enabledConfiguration = FinderConfiguration(
            airDropEnabled: true, terminalEnabled: true, copyPathEnabled: true, moveEnabled: true)
        let lifecycle = ApplicationLifecycle()
        var opened: [URL] = []
        let service = FinderActionService(
            lifecycle: lifecycle,
            openTerminal: { directory in
                precondition(lifecycle.isActive(.finderAction))
                opened.append(directory)
            }, configuration: { enabledConfiguration })
        try await service.handle(FinderActionRequest(action: .terminal, files: [root]))
        precondition(opened == [root] && !lifecycle.isActive(.finderAction))
        let denied = FinderActionService(
            lifecycle: lifecycle, openTerminal: { _ in preconditionFailure("Disabled action launched Terminal") },
            configuration: { FinderConfiguration(airDropEnabled: true, terminalEnabled: false) })
        do {
            try await denied.handle(FinderActionRequest(action: .terminal, files: [root]))
            preconditionFailure("Disabled action was accepted")
        } catch CocoaError.featureUnsupported {}
        let failing = FinderActionService(
            lifecycle: lifecycle, openTerminal: { _ in throw CocoaError(.fileReadNoPermission) },
            configuration: { enabledConfiguration })
        do {
            try await failing.handle(FinderActionRequest(action: .terminal, files: [root]))
            preconditionFailure("Terminal error was swallowed")
        } catch CocoaError.fileReadNoPermission {}
        precondition(!lifecycle.isActive(.finderAction))
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let source = root.appendingPathComponent("source.txt")
        try Data("keep".utf8).write(to: source)
        board.writeObjects([source as NSURL])
        let moveRequest = try FinderActionRequest(action: .move, files: [root], clipboardChangeCount: board.changeCount)
        var moved: [FinderMovePlan] = []
        var confirmations = 0
        let mover = FinderActionService(
            lifecycle: lifecycle, configuration: { enabledConfiguration }, pasteboard: board,
            confirmMove: { plan in
                confirmations += 1
                precondition(plan.sources == [source] && plan.destination == root)
                return true
            }, move: { moved.append($0) })
        try await mover.handle(moveRequest)
        precondition(moved.count == 1 && confirmations == 1)
        let cancelled = FinderActionService(
            lifecycle: lifecycle, configuration: { enabledConfiguration }, pasteboard: board,
            confirmMove: { _ in false }, move: { _ in preconditionFailure("Cancelled move ran") })
        try await cancelled.handle(moveRequest)
        let changed = FinderActionService(
            lifecycle: lifecycle, configuration: { enabledConfiguration }, pasteboard: board,
            confirmMove: { _ in
                board.clearContents()
                board.setString("changed", forType: .string)
                return true
            }, move: { _ in preconditionFailure("Changed clipboard was accepted") })
        do {
            try await changed.handle(moveRequest)
            preconditionFailure("Clipboard change during confirmation was ignored")
        } catch CocoaError.fileReadUnknown {}
        do {
            try await mover.handle(moveRequest)
            preconditionFailure("Stale menu request was accepted")
        } catch CocoaError.fileReadUnknown {}
        precondition(confirmations == 1 && moved.count == 1 && !lifecycle.isActive(.finderAction))
        let movingLifecycle = ApplicationLifecycle()
        board.clearContents()
        board.writeObjects([source as NSURL])
        let pendingRequest = try FinderActionRequest(
            action: .move, files: [root], clipboardChangeCount: board.changeCount)
        var finishMove: CheckedContinuation<Void, Never>?
        var terminationReady = false
        movingLifecycle.onReadyToTerminate = { terminationReady = true }
        let pendingMover = FinderActionService(
            lifecycle: movingLifecycle, configuration: { enabledConfiguration }, pasteboard: board,
            confirmMove: { _ in true },
            move: { _ in await withCheckedContinuation { finishMove = $0 } })
        let pending = Task { try await pendingMover.handle(pendingRequest) }
        while finishMove == nil { await Task.yield() }
        do {
            try await pendingMover.handle(pendingRequest)
            preconditionFailure("A concurrent action was accepted")
        } catch {
            precondition((error as NSError).domain == "Buckle.FinderAction")
            precondition((error as? CocoaError)?.code != .userCancelled)
        }
        precondition(!movingLifecycle.requestTermination() && !terminationReady)
        do {
            try await pendingMover.handle(pendingRequest)
            preconditionFailure("A second move was accepted during shutdown")
        } catch CocoaError.userCancelled {}
        finishMove?.resume()
        try await pending.value
        precondition(terminationReady && !movingLifecycle.isActive(.finderAction))
        // A failed launch still releases its operation, but cannot reopen error UI after a quit request.
        for quitWhileOpening in [false, true] {
            let lifecycle = ApplicationLifecycle()
            var finishOpening: CheckedContinuation<Void, Error>?
            var replies = 0
            var presentedErrors: [NSError] = []
            lifecycle.onReadyToTerminate = { replies += 1 }
            let terminal = FinderActionService(
                lifecycle: lifecycle,
                openTerminal: { _ in
                    try await withCheckedThrowingContinuation { finishOpening = $0 }
                }, configuration: { enabledConfiguration })
            let request = try FinderActionRequest(action: .terminal, files: [root])
            let opening = Task {
                do { try await terminal.handle(request) } catch {
                    if lifecycle.shouldPresentUserActionError(error) { presentedErrors.append(error as NSError) }
                }
            }
            while finishOpening == nil { await Task.yield() }
            if quitWhileOpening { precondition(!lifecycle.requestTermination()) }
            finishOpening?.resume(throwing: CocoaError(.fileReadNoPermission))
            await opening.value
            precondition(replies == (quitWhileOpening ? 1 : 0))
            precondition(presentedErrors.count == (quitWhileOpening ? 0 : 1))
            precondition(!lifecycle.isActive(.finderAction))
        }
        precondition(lifecycle.requestTermination())
        do {
            try await service.handle(FinderActionRequest(action: .terminal, files: [root]))
            preconditionFailure("Action started while quitting")
        } catch CocoaError.userCancelled {}
        print(
            "Finder actions, switches, move confirmation, clipboard changes and quit admission verified without launching Terminal or moving files."
        )
    }
}
