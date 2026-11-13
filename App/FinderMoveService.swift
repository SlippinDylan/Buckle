import AppKit

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
    func move(_ plan: FinderMovePlan) throws {
        do {
            try plan.validate()
            for source in plan.sources {
                try Task.checkCancellation()
                let target = plan.destination.appendingPathComponent(source.lastPathComponent)
                let coordinator = NSFileCoordinator()
                var coordinationError: NSError?
                var operationError: Error?
                coordinator.coordinate(
                    writingItemAt: source, options: .forMoving,
                    writingItemAt: target, options: [], error: &coordinationError
                ) { coordinatedSource, coordinatedTarget in
                    do {
                        // FileManager preserves a source symlink and refuses existing destinations.
                        coordinator.item(at: coordinatedSource, willMoveTo: coordinatedTarget)
                        try FileManager.default.moveItem(at: coordinatedSource, to: coordinatedTarget)
                        coordinator.item(at: coordinatedSource, didMoveTo: coordinatedTarget)
                    } catch { operationError = error }
                }
                if let coordinationError { throw coordinationError }
                if let operationError { throw operationError }
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
