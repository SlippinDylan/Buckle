import CryptoKit
import Darwin
import Foundation

struct FinderDirectoryIdentity: Codable, Equatable, Sendable {
    let device: Int32
    let inode: UInt64
    let birthSeconds: Int64
    let birthNanoseconds: Int64

    init(_ info: stat) {
        device = info.st_dev
        inode = info.st_ino
        birthSeconds = Int64(info.st_birthtimespec.tv_sec)
        birthNanoseconds = Int64(info.st_birthtimespec.tv_nsec)
    }
}

struct FinderNewTextFileTarget: Codable, Equatable, Sendable {
    let directory: URL
    let identity: FinderDirectoryIdentity
    let requestID: UUID

    init(directory: URL) throws {
        let resolved = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard try FinderMenuContext.container(resolved).directory() != nil else {
            throw FinderActionRequest.RequestError.invalidFiles
        }
        var info = stat()
        guard stat(resolved.path, &info) == 0 else { throw finderFileError() }
        self.directory = resolved
        identity = FinderDirectoryIdentity(info)
        requestID = UUID()
    }
}

struct FinderNewTextFileRequest: Sendable {
    private struct Payload: Codable, Sendable {
        let target: FinderNewTextFileTarget
        let issuedAt: Int64
    }

    private let data: Data
    private let signature: Data
    private let payload: Payload
    var target: FinderNewTextFileTarget { payload.target }
    static let lifetime: TimeInterval = 300
    private static let domain = Data("buckle.finder.new-text-file.v1\0".utf8)

    init(target: FinderNewTextFileTarget, key: SymmetricKey, now: Date = Date()) throws {
        payload = Payload(target: target, issuedAt: Int64(now.timeIntervalSince1970))
        data = try JSONEncoder().encode(payload)
        signature = Data(HMAC<SHA256>.authenticationCode(for: Self.domain + data, using: key))
    }

    init(url: URL) throws {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme == "buckle", parts.host == "finder", parts.path == "/new-text-file",
            parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
            let items = parts.queryItems, items.count == 2,
            items.filter({ $0.name == "payload" }).count == 1,
            items.filter({ $0.name == "signature" }).count == 1,
            let encoded = items.first(where: { $0.name == "payload" })?.value, encoded.utf8.count <= 16_384,
            let data = Data(base64Encoded: encoded),
            let signed = items.first(where: { $0.name == "signature" })?.value, signed.utf8.count <= 44,
            let signature = Data(base64Encoded: signed), signature.count == 32
        else { throw FinderActionRequest.RequestError.invalidRoute }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let directory = payload.target.directory
        guard directory.isFileURL, directory.path.hasPrefix("/"),
            directory.host == nil || directory.host == "" || directory.host == "localhost",
            directory.query == nil, directory.fragment == nil
        else { throw FinderActionRequest.RequestError.invalidFiles }
        self.data = data
        self.signature = signature
        self.payload = payload
    }

    func validate(key: SymmetricKey, now: Date) throws {
        let age = now.timeIntervalSince1970 - Double(payload.issuedAt)
        guard age >= -5, age <= Self.lifetime,
            HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: Self.domain + data, using: key)
        else { throw FinderActionRequest.RequestError.invalidRoute }
    }

    func url() throws -> URL {
        var parts = URLComponents()
        parts.scheme = "buckle"
        parts.host = "finder"
        parts.path = "/new-text-file"
        parts.queryItems = [
            URLQueryItem(name: "payload", value: data.base64EncodedString()),
            URLQueryItem(name: "signature", value: signature.base64EncodedString()),
        ]
        guard let url = parts.url else { throw FinderActionRequest.RequestError.invalidRoute }
        return url
    }
}

extension FinderConfigurationStore {
    private var newTextFileKey: URL { directory.appendingPathComponent("new-text-file-request.key") }

    func loadNewTextFileKey() throws -> SymmetricKey {
        let data = try Data(contentsOf: newTextFileKey)
        guard data.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
        return SymmetricKey(data: data)
    }

    func prepareNewTextFileKey() throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(newTextFileKey.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            if errno == EEXIST {
                _ = try loadNewTextFileKey()
                return
            }
            throw finderFileError()
        }
        defer { close(fd) }
        let key = SymmetricKey(size: .bits256)
        try key.withUnsafeBytes { try finderWriteAll(fd, data: Data($0)) }
        guard fsync(fd) == 0 else { throw finderFileError() }
    }
}

func finderFileError(_ code: Int32 = errno) -> NSError {
    NSError(domain: NSPOSIXErrorDomain, code: Int(code))
}

func finderWriteAll(_ fd: Int32, data: Data) throws {
    try data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = write(fd, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
            if count < 0 && errno == EINTR { continue }
            guard count > 0 else { throw finderFileError(count == 0 ? EIO : errno) }
            offset += count
        }
    }
}
