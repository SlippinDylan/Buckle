import AppKit

@main
enum FinderPathCopyCheck {
    static func main() throws {
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
        print("Copy paths preserves literal names and multiple selections, without changing the user clipboard.")
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
