import AppKit
import OSLog

@main
enum FinderPathCopyCheck {
    @MainActor static func main() async throws {
        try await verifyBackgroundMenuCallbacks()
        try verifySharedLanguage()
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let urls = [URL(fileURLWithPath: "/tmp/中文 '$(literal); #?.txt"), URL(fileURLWithPath: "/Volumes/Test Folder")]
        try FinderPathCopy.write(urls, to: board)
        precondition(board.string(forType: .string) == urls.map(\.path).joined(separator: "\n"))
        precondition(!board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
        guard let remote = URL(string: "https://example.com") else { preconditionFailure("Invalid test URL") }
        for files in [[URL](), [remote]] {
            do {
                try FinderPathCopy.write(files, to: board)
                preconditionFailure("Invalid path copy replaced clipboard")
            } catch FinderActionRequest.RequestError.invalidFiles {}
            precondition(board.string(forType: .string) == urls.map(\.path).joined(separator: "\n"))
        }
        print(
            "Finder menu actions accept background Objective-C callbacks; path copying preserves literal names without changing the user clipboard."
        )
    }

    @MainActor private static func verifyBackgroundMenuCallbacks() async throws {
        let files = [URL(fileURLWithPath: "/tmp/中文 '$(literal); #?.txt"), URL(fileURLWithPath: "/Volumes/Test Folder")]
        let request = try FinderActionRequest(action: .airDrop, files: files).url()
        var openCount = 0
        var copyCount = 0
        let openRequest: @MainActor @Sendable (URL, Logger) -> Void = { received, _ in
            MainActor.preconditionIsolated()
            precondition(Thread.isMainThread && received == request)
            openCount += 1
            precondition(openCount == 1)
        }
        let copyFiles: @MainActor @Sendable ([URL], Logger) -> Void = { received, _ in
            MainActor.preconditionIsolated()
            precondition(Thread.isMainThread && received == files)
            copyCount += 1
            precondition(copyCount == 1)
        }
        // Exercise the real Objective-C entry points from Finder's background callback context.
        await Task.detached {
            var observedDirectories: Set<URL> = []
            let finder = BuckleFinderSync(
                observeDirectories: { observedDirectories = $0 }, openRequest: openRequest, copyFiles: copyFiles)
            precondition(observedDirectories.contains(URL(fileURLWithPath: "/")))
            precondition(!Thread.isMainThread)
            for name in ["performAction:", "copyPath:"] {
                let selector = NSSelectorFromString(name)
                precondition(finder.responds(to: selector))
                _ = finder.perform(selector, with: NSMenuItem())
                let invalid = NSMenuItem()
                invalid.representedObject = "invalid payload"
                _ = finder.perform(selector, with: invalid)
                let valid = NSMenuItem()
                if name == "performAction:" {
                    valid.representedObject = request
                } else {
                    valid.representedObject = files
                }
                _ = finder.perform(selector, with: valid)
            }
        }.value
        // A missing dispatch must fail the check rather than leave it waiting forever.
        let deadline = ContinuousClock.now + .seconds(2)
        while openCount == 0 || copyCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(openCount == 1 && copyCount == 1, "Valid Finder requests were not dispatched")
    }
    private static func verifySharedLanguage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer {
            do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") }
        }
        let contents = root.appendingPathComponent("Contents")
        for (language, title) in [("en", "Open in Terminal"), ("ja", "ターミナルで開く")] {
            let directory = contents.appendingPathComponent("Resources/\(language).lproj")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("\"finder.terminal.title\" = \"\(title)\";".utf8)
                .write(to: directory.appendingPathComponent("Localizable.strings"))
        }
        let info = ["CFBundleIdentifier": "Buckle.FinderLanguageCheck", "CFBundleDevelopmentRegion": "en"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard let bundle = Bundle(url: root) else { preconditionFailure("Missing localization test bundle") }
        precondition(localized("finder.terminal.title", language: "ja", bundle: bundle) == "ターミナルで開く")
        precondition(localized("finder.terminal.title", language: "en", bundle: bundle) == "Open in Terminal")
    }

}
