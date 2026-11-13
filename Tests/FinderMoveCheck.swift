import AppKit

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
            print("Coordinated native moves preserve literal filenames, symbolic links and their untouched targets.")
        }
    }
}
