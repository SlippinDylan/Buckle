import Darwin
import Foundation

enum NewTextFileError: LocalizedError {
    case directoryChanged, alreadyConsumed, journalDamaged
    case createdButUnavailable(URL, Error)

    var errorDescription: String? {
        switch self {
        case .directoryChanged: localized("finder.newTextFile.directory.changed")
        case .alreadyConsumed: localized("finder.newTextFile.already.consumed")
        case .journalDamaged: localized("finder.newTextFile.journal.damaged")
        case .createdButUnavailable: localized("finder.newTextFile.created.unavailable")
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .createdButUnavailable(let url, let error): url.path + "\n" + error.localizedDescription
        case .directoryChanged, .alreadyConsumed: localized("finder.newTextFile.retry.help")
        case .journalDamaged: localized("finder.newTextFile.journal.help")
        }
    }
}

actor NewTextFileService {
    static let shared = NewTextFileService()

    func create(
        _ request: FinderNewTextFileRequest, baseName: String,
        store: FinderConfigurationStore, now: Date = Date()
    ) throws -> URL {
        try request.validate(key: store.loadNewTextFileKey(), now: now)
        guard try store.load().newTextFileEnabled else {
            throw CocoaError(
                .featureUnsupported, userInfo: [NSLocalizedDescriptionKey: localized("finder.action.disabled")])
        }
        guard !baseName.isEmpty, !baseName.contains("/"), !baseName.contains("\0") else {
            throw FinderActionRequest.RequestError.invalidFiles
        }
        let target = request.target
        let directoryFD = open(target.directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw finderFileError() }
        defer { close(directoryFD) }
        var info = stat()
        guard fstat(directoryFD, &info) == 0 else { throw finderFileError() }
        guard FinderDirectoryIdentity(info) == target.identity,
            try FinderMenuContext.container(target.directory).directory() != nil
        else { throw NewTextFileError.directoryChanged }

        // Persist consumption before the side effect. A crash may lose this click, never repeat it.
        try consume(target.requestID, in: store.directory)
        var number = 1
        while true {
            let name = number == 1 ? baseName + ".txt" : "\(baseName) \(number).txt"
            let fd = openat(directoryFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
            if fd < 0 {
                if errno == EEXIST {
                    number += 1
                    continue
                }
                throw finderFileError()
            }
            let url = target.directory.appendingPathComponent(name)
            do {
                var created = stat()
                let status = fstat(fd, &created)
                let errorCode = errno
                let closeStatus = close(fd)
                guard status == 0 else { throw finderFileError(errorCode) }
                guard closeStatus == 0 else { throw finderFileError() }
                var liveDirectory = stat()
                var liveFile = stat()
                guard stat(target.directory.path, &liveDirectory) == 0, lstat(url.path, &liveFile) == 0,
                    FinderDirectoryIdentity(liveDirectory) == target.identity,
                    FinderDirectoryIdentity(liveFile) == FinderDirectoryIdentity(created)
                else { throw NewTextFileError.directoryChanged }
            } catch {
                // Never retry creation or delete a file after a successful O_EXCL create.
                throw NewTextFileError.createdButUnavailable(url, error)
            }
            return url
        }
    }

    private func consume(_ id: UUID, in directory: URL) throws {
        let file = directory.appendingPathComponent("new-text-file-consumed.log")
        let fd = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw finderFileError() }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw finderFileError() }
        defer { flock(fd, LOCK_UN) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let data = try handle.readToEnd() ?? Data()
        guard let text = String(data: data, encoding: .utf8), text.isEmpty || text.hasSuffix("\n") else {
            throw NewTextFileError.journalDamaged
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            guard let previous = UUID(uuidString: String(line)) else { throw NewTextFileError.journalDamaged }
            guard previous != id else { throw NewTextFileError.alreadyConsumed }
        }
        try finderWriteAll(fd, data: Data((id.uuidString + "\n").utf8))
        guard fsync(fd) == 0 else { throw finderFileError() }
    }
}
