import Foundation

@main
enum FinderSandboxCheck {
    static func main() throws {
        let store = try FinderConfigurationStore.standard()
        let file = store.directory.appendingPathComponent(CommandLine.arguments[1])
        let contents = try String(contentsOf: file, encoding: .utf8)
        precondition(contents == "Buckle sandbox probe")
        do {
            try Data("write must fail".utf8).write(to: file)
            preconditionFailure("Finder extension must only have read access to the configuration directory")
        } catch CocoaError.fileWriteNoPermission {
            print("Sandboxed Finder configuration read succeeded; write access was denied.")
        }
    }
}
