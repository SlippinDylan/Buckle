import AppKit

@main
enum FinderPathCopyCheck {
    static func main() throws {
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
}
