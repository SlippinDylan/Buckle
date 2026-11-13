import AppKit
import Synchronization

private final class BlockingFilePresenter: NSObject, NSFilePresenter, Sendable {
    private typealias Writer = @Sendable ((@Sendable () -> Void)?) -> Void
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let writer = Mutex<Writer?>(nil)

    init(url: URL) { presentedItemURL = url }

    var isBlocking: Bool { writer.withLock { $0 != nil } }

    func relinquishPresentedItem(toWriter writer: @escaping @Sendable ((@Sendable () -> Void)?) -> Void) {
        self.writer.withLock { $0 = writer }
    }

    func releaseWriter() {
        let callback = writer.withLock { writer in
            let callback = writer
            writer = nil
            return callback
        }
        callback?(nil)
    }
}

@main
enum FinderMoveCheck {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try manager.createDirectory(at: source, withIntermediateDirectories: true)
        try manager.createDirectory(at: destination, withIntermediateDirectories: true)
        defer {
            do { try manager.removeItem(at: root) } catch { preconditionFailure(error.localizedDescription) }
        }
        let file = source.appendingPathComponent("中文 '$(literal); #?.txt")
        try Data("preserve".utf8).write(to: file)
        let plan = try FinderMovePlan(sources: [file], destination: destination)
        try plan.validate()
        for invalid in [
            try FinderMovePlan(sources: [source], destination: source),
            try FinderMovePlan(sources: [file], destination: source),
            try FinderMovePlan(sources: [source], destination: root),
            try FinderMovePlan(sources: [file, file], destination: destination),
            try FinderMovePlan(sources: [source, file], destination: destination),
        ] {
            do {
                try invalid.validate()
                preconditionFailure("Unsafe move passed validation")
            } catch is CocoaError {}
        }
        let child = source.appendingPathComponent("child")
        try manager.createDirectory(at: child, withIntermediateDirectories: true)
        do {
            try FinderMovePlan(sources: [source], destination: child).validate()
            preconditionFailure("A folder was permitted inside itself")
        } catch is CocoaError {}
        let conflict = destination.appendingPathComponent(file.lastPathComponent)
        try Data("original".utf8).write(to: conflict)
        do {
            try plan.validate()
            preconditionFailure("Conflict passed validation")
        } catch CocoaError.fileWriteFileExists {}
        let original = try Data(contentsOf: conflict)
        precondition(original == Data("original".utf8))
        try manager.removeItem(at: conflict)
        do {
            try await FinderMoveRunner().move(plan)
            precondition(!manager.fileExists(atPath: file.path))
            let moved = try Data(contentsOf: conflict)
            precondition(moved == Data("preserve".utf8))
            let realTarget = source.appendingPathComponent("link-target.txt")
            try Data("target stays here".utf8).write(to: realTarget)
            let link = source.appendingPathComponent("link.txt")
            try manager.createSymbolicLink(at: link, withDestinationURL: realTarget)
            try await FinderMoveRunner().move(FinderMovePlan(sources: [link], destination: destination))
            precondition(manager.fileExists(atPath: realTarget.path))
            let linkTarget = try manager.destinationOfSymbolicLink(
                atPath: destination.appendingPathComponent("link.txt").path)
            precondition(linkTarget == realTarget.path)
            try await verifyWaitingCanEnd(source: source, destination: destination, cancel: false)
            try await verifyWaitingCanEnd(source: source, destination: destination, cancel: true)
            print(
                "Coordinated moves preserve filenames and symlinks; waiting times out or cancels without a late move.")
        }
    }

    private static func verifyWaitingCanEnd(source: URL, destination: URL, cancel: Bool) async throws {
        let completedFile = source.appendingPathComponent(UUID().uuidString)
        try Data("already moved".utf8).write(to: completedFile)
        let file = source.appendingPathComponent(UUID().uuidString)
        try Data("must remain".utf8).write(to: file)
        let presenter = BlockingFilePresenter(url: file)
        NSFileCoordinator.addFilePresenter(presenter)
        defer {
            presenter.releaseWriter()
            NSFileCoordinator.removeFilePresenter(presenter)
        }
        let runner = FinderMoveRunner(coordinationTimeout: cancel ? .seconds(5) : .milliseconds(250))
        let plan = try FinderMovePlan(sources: [completedFile, file], destination: destination)
        let started = ContinuousClock.now
        let moving = Task { try await runner.move(plan) }
        let readyDeadline = started.advanced(by: .seconds(2))
        while !presenter.isBlocking {
            precondition(ContinuousClock.now < readyDeadline, "File presenter did not receive the coordination request")
            try await Task.sleep(for: .milliseconds(10))
        }
        if cancel { moving.cancel() }
        do {
            try await moving.value
            preconditionFailure("A blocked move must not report success")
        } catch {
            let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError
            precondition(underlying != nil, "The move failure must retain its cause")
            if cancel {
                precondition(underlying?.domain == NSCocoaErrorDomain && underlying?.code == NSUserCancelledError)
            } else {
                precondition(underlying?.domain == NSURLErrorDomain && underlying?.code == NSURLErrorTimedOut)
            }
        }
        precondition(started.duration(to: .now) < .seconds(2), "Cancellation must end the coordination wait")
        presenter.releaseWriter()
        try await Task.sleep(for: .milliseconds(100))
        precondition(FileManager.default.fileExists(atPath: file.path), "A cancelled wait must not move later")
        precondition(!FileManager.default.fileExists(atPath: completedFile.path))
        let completedData = try Data(contentsOf: destination.appendingPathComponent(completedFile.lastPathComponent))
        precondition(completedData == Data("already moved".utf8), "Earlier successful moves must stay completed")
        precondition(
            !FileManager.default.fileExists(atPath: destination.appendingPathComponent(file.lastPathComponent).path))
    }

}
