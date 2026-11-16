import CryptoKit
import Darwin
import Foundation

@main
enum NewTextFileCheck {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { do { try FileManager.default.removeItem(at: root) } catch { preconditionFailure("\(error)") } }
        let store = FinderConfigurationStore(directory: root.appendingPathComponent("configuration"))
        try store.save(FinderConfiguration(newTextFileEnabled: true))
        try store.prepareNewTextFileKey()
        let key = try store.loadNewTextFileKey()
        let folder = root.appendingPathComponent("中文 '$(literal); #?")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let now = Date()
        func request(_ directory: URL = folder) throws -> FinderNewTextFileRequest {
            try FinderNewTextFileRequest(target: FinderNewTextFileTarget(directory: directory), key: key, now: now)
        }
        let first = try request()
        let decoded = try FinderNewTextFileRequest(url: first.url())
        try decoded.validate(key: key, now: now)
        precondition(decoded.target == first.target)
        do {
            try decoded.validate(key: SymmetricKey(size: .bits256), now: now)
            preconditionFailure("Wrong key accepted")
        } catch FinderActionRequest.RequestError.invalidRoute {}
        for time in [now.addingTimeInterval(301), now.addingTimeInterval(-10)] {
            do {
                try decoded.validate(key: key, now: time)
                preconditionFailure("Invalid time accepted")
            } catch FinderActionRequest.RequestError.invalidRoute {}
        }
        guard var parts = URLComponents(url: try first.url(), resolvingAgainstBaseURL: false) else {
            preconditionFailure("Cannot encode test URL")
        }
        parts.queryItems?.append(URLQueryItem(name: "payload", value: "duplicate"))
        guard let duplicateURL = parts.url else { preconditionFailure("Cannot encode duplicate query") }
        do {
            _ = try FinderNewTextFileRequest(url: duplicateURL)
            preconditionFailure("Duplicate field accepted")
        } catch FinderActionRequest.RequestError.invalidRoute {}
        guard var tamperedParts = URLComponents(url: try first.url(), resolvingAgainstBaseURL: false),
            let items = tamperedParts.queryItems,
            let payload = items.first(where: { $0.name == "payload" })?.value,
            let bytes = Data(base64Encoded: payload),
            var object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
            var target = object["target"] as? [String: Any]
        else { preconditionFailure("Malformed test payload") }
        target["directory"] = root.absoluteString
        object["target"] = target
        let changedData = try JSONSerialization.data(withJSONObject: object)
        tamperedParts.queryItems = items.map { item in
            item.name == "payload"
                ? URLQueryItem(name: "payload", value: changedData.base64EncodedString()) : item
        }
        guard let tamperedURL = tamperedParts.url else { preconditionFailure("Cannot encode changed query") }
        let tampered = try FinderNewTextFileRequest(url: tamperedURL)
        do {
            try tampered.validate(key: key, now: now)
            preconditionFailure("Tampered destination accepted")
        } catch FinderActionRequest.RequestError.invalidRoute {}

        let original = folder.appendingPathComponent("New.txt")
        try Data("keep this".utf8).write(to: original)
        let symlink = folder.appendingPathComponent("New 2.txt")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: original)
        let creator = NewTextFileService()
        let created = try await creator.create(decoded, baseName: "New", store: store, now: now)
        precondition(created.lastPathComponent == "New 3.txt")
        let createdData = try Data(contentsOf: created)
        let originalData = try Data(contentsOf: original)
        let symlinkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: symlink.path)
        precondition(createdData.isEmpty && originalData == Data("keep this".utf8))
        precondition(symlinkTarget == original.path)
        do {
            _ = try await NewTextFileService().create(decoded, baseName: "New", store: store, now: now)
            preconditionFailure("Reopened service accepted a consumed request")
        } catch NewTextFileError.alreadyConsumed {}
        let independent = try (0..<8).map { _ in try request() }
        let results = try await withThrowingTaskGroup(of: URL.self) { group in
            for request in independent {
                group.addTask {
                    try await NewTextFileService().create(request, baseName: "New", store: store, now: now)
                }
            }
            var urls: [URL] = []
            for try await url in group { urls.append(url) }
            return urls
        }
        precondition(Set(results).count == 8)
        for request in independent {
            do {
                _ = try await NewTextFileService().create(request, baseName: "New", store: store, now: now)
                preconditionFailure("Concurrent consumption record was lost")
            } catch NewTextFileError.alreadyConsumed {}
        }
        let repeated = try request()
        let successes = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do {
                        _ = try await NewTextFileService().create(repeated, baseName: "Once", store: store, now: now)
                        return true
                    } catch NewTextFileError.alreadyConsumed { return false }
                }
            }
            var count = 0
            for try await success in group { if success { count += 1 } }
            return count
        }
        precondition(successes == 1, "One signed request must create at most one file under concurrency")

        let replaced = root.appendingPathComponent("replaced")
        try FileManager.default.createDirectory(at: replaced, withIntermediateDirectories: true)
        let stale = try request(replaced)
        try FileManager.default.moveItem(at: replaced, to: root.appendingPathComponent("moved"))
        try FileManager.default.createDirectory(at: replaced, withIntermediateDirectories: true)
        do {
            _ = try await creator.create(stale, baseName: "New", store: store, now: now)
            preconditionFailure("A replacement directory accepted an old identity")
        } catch NewTextFileError.directoryChanged {}
        let replacementContents = try FileManager.default.contentsOfDirectory(atPath: replaced.path)
        precondition(replacementContents.isEmpty)

        let readonly = root.appendingPathComponent("readonly")
        try FileManager.default.createDirectory(at: readonly, withIntermediateDirectories: true)
        let denied = try request(readonly)
        guard chmod(readonly.path, 0o555) == 0 else { throw finderFileError() }
        do {
            _ = try await creator.create(denied, baseName: "New", store: store, now: now)
            preconditionFailure("Read-only directory was written")
        } catch let error as NSError { precondition(error.domain == NSPOSIXErrorDomain && error.code == Int(EACCES)) }
        guard chmod(readonly.path, 0o755) == 0 else { throw finderFileError() }
        let deniedContents = try FileManager.default.contentsOfDirectory(atPath: readonly.path)
        precondition(deniedContents.isEmpty)
        do {
            _ = try await creator.create(denied, baseName: "New", store: store, now: now)
            preconditionFailure("A consumed failed request was replayed")
        } catch NewTextFileError.alreadyConsumed {}

        try store.save(FinderConfiguration())
        do {
            _ = try await creator.create(request(), baseName: "New", store: store, now: now)
            preconditionFailure("Disabled file creation accepted")
        } catch CocoaError.featureUnsupported {}
        try store.save(FinderConfiguration(newTextFileEnabled: true))
        let journal = store.directory.appendingPathComponent("new-text-file-consumed.log")
        try Data("partial-record".utf8).write(to: journal)
        do {
            _ = try await creator.create(request(), baseName: "New", store: store, now: now)
            preconditionFailure("Corrupt request record accepted")
        } catch NewTextFileError.journalDamaged {}
        let keyFile = store.directory.appendingPathComponent("new-text-file-request.key")
        try Data("damaged".utf8).write(to: keyFile)
        do {
            try store.prepareNewTextFileKey()
            preconditionFailure("Damaged key silently replaced")
        } catch CocoaError.fileReadCorruptFile {}
        print(
            "Text creation preserves existing files, authenticates requests, rejects replay across reopen/concurrency, and fails closed on stale directories and damaged records."
        )
    }
}
