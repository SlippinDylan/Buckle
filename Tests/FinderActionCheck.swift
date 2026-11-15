import AppKit
import CryptoKit

@MainActor
private final class FakeAirDrop: AirDropPresenting {
    var requests: [[URL]] = []
    var error: Error?
    func present(_ urls: [URL]) throws {
        if let error { throw error }
        requests.append(urls)
    }
}

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
        let moveKey = SymmetricKey(size: .bits256)
        let enabledConfiguration = FinderConfiguration(
            airDropEnabled: true, terminalEnabled: true, copyPathEnabled: true, moveEnabled: true)
        let sharingLifecycle = ApplicationLifecycle()
        let airDrop = FakeAirDrop()
        var terminalAfterSharing = false
        let shortcut = FinderActionService(
            lifecycle: sharingLifecycle, airDrop: airDrop,
            openTerminal: { _ in terminalAfterSharing = true }, configuration: { enabledConfiguration })
        try await shortcut.handle(FinderActionRequest(action: .airDrop, files: [root]))
        precondition(airDrop.requests == [[root]])
        precondition(!sharingLifecycle.isActive(.finderAction), "AirDrop must not wait for a delegate callback")
        try await shortcut.handle(FinderActionRequest(action: .terminal, files: [root]))
        precondition(terminalAfterSharing)
        airDrop.error = CocoaError(.fileReadNoPermission)
        do {
            try await shortcut.handle(FinderActionRequest(action: .airDrop, files: [root]))
            preconditionFailure("Presentation failure was hidden")
        } catch CocoaError.fileReadNoPermission {}
        precondition(!sharingLifecycle.isActive(.finderAction))
        precondition(sharingLifecycle.requestTermination(), "Sharing must not hold normal quit open")
        let realLifecycle = ApplicationLifecycle()
        let sharingService = NSSharingService(
            title: "Test", image: NSImage(size: NSSize(width: 1, height: 1)), alternateImage: nil, handler: {})
        let realAirDrop = AirDropService(
            makeService: { sharingService }, perform: { _, _ in },
            reportError: { _ in preconditionFailure("Unexpected sharing error") })
        var openedWhileSharing = false
        let realShortcut = FinderActionService(
            lifecycle: realLifecycle, airDrop: realAirDrop,
            openTerminal: { _ in openedWhileSharing = true }, configuration: { enabledConfiguration })
        try await realShortcut.handle(FinderActionRequest(action: .airDrop, files: [root]))
        precondition(sharingService.delegate != nil, "The session must still be awaiting system callbacks")
        try await realShortcut.handle(FinderActionRequest(action: .terminal, files: [root]))
        precondition(openedWhileSharing && !realLifecycle.isActive(.finderAction))
        precondition(realLifecycle.requestTermination())
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
            .signed(using: moveKey)
        var moved: [FinderMovePlan] = []
        let mover = FinderActionService(
            lifecycle: lifecycle, configuration: { enabledConfiguration }, pasteboard: board, moveKey: { moveKey },
            move: { plan in
                precondition(lifecycle.isActive(.finderAction))
                precondition(plan.sources == [source] && plan.destination == root)
                precondition(plan.clipboardChangeCount == board.changeCount)
                moved.append(plan)
            })
        let unsigned = try FinderActionRequest(action: .move, files: [root], clipboardChangeCount: board.changeCount)
        let wrongKey = try unsigned.signed(using: SymmetricKey(size: .bits256))
        for forged in [unsigned, wrongKey] {
            do {
                try await mover.handle(FinderActionRequest(url: forged.url()))
                preconditionFailure("An unauthenticated move was dispatched")
            } catch FinderActionRequest.RequestError.invalidRoute {}
        }
        precondition(moved.isEmpty && !lifecycle.isActive(.finderAction))
        try await mover.handle(FinderActionRequest(url: moveRequest.url()))
        precondition(moved.count == 1, "Move must dispatch directly without confirmation")
        board.clearContents()
        board.setString("changed", forType: .string)
        do {
            try await mover.handle(moveRequest)
            preconditionFailure("Stale menu request was accepted")
        } catch FinderMoveError.clipboardChanged {}
        precondition(moved.count == 1 && !lifecycle.isActive(.finderAction))
        let movingLifecycle = ApplicationLifecycle()
        board.clearContents()
        board.writeObjects([source as NSURL])
        let pendingRequest = try FinderActionRequest(
            action: .move, files: [root], clipboardChangeCount: board.changeCount
        ).signed(using: moveKey)
        var finishMove: CheckedContinuation<Void, Never>?
        var terminationReady = false
        movingLifecycle.onReadyToTerminate = { terminationReady = true }
        let pendingMover = FinderActionService(
            lifecycle: movingLifecycle, configuration: { enabledConfiguration }, pasteboard: board,
            moveKey: { moveKey },
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
            "Finder actions, switches, direct move dispatch, clipboard changes and quit admission verified without launching Terminal or moving files."
        )
    }
}
