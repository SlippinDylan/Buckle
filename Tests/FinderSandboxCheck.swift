import CryptoKit
import Foundation

@main
enum FinderSandboxCheck {
    static func main() throws {
        let store = try FinderConfigurationStore.standard()
        let file = store.directory.appendingPathComponent(CommandLine.arguments[1])
        let contents = try String(contentsOf: file, encoding: .utf8)
        precondition(contents == "Buckle sandbox probe")
        let key = SymmetricKey(data: Data(contents.utf8))
        let request = try FinderActionRequest(action: .move, files: [file], clipboardChangeCount: 1).signed(using: key)
        let authenticated = try FinderActionRequest(url: request.url()).authenticates(using: key)
        precondition(authenticated)
        let target = try FinderNewTextFileTarget(directory: store.directory)
        let creation = try FinderNewTextFileRequest(target: target, key: key)
        try FinderNewTextFileRequest(url: creation.url()).validate(key: key, now: Date())
        do {
            try Data("write must fail".utf8).write(to: file)
            preconditionFailure("Finder extension must only have read access to the configuration directory")
        } catch CocoaError.fileWriteNoPermission {
            print("Sandboxed Finder configuration read and request signing succeeded; write access was denied.")
        }
    }
}
