import CryptoKit
import Darwin
import Foundation

enum FinderIntegration {
    static let identifier = "studio.slippindylan.Buckle.Finder"
    static let bundleName = "BuckleFinder.appex"
}

struct FinderConfiguration: Codable, Equatable {
    var airDropEnabled: Bool
    var terminalEnabled: Bool
    var copyPathEnabled: Bool
    var moveEnabled: Bool
    var language: String?
    static let initial = FinderConfiguration()

    private enum CodingKeys: String, CodingKey {
        case airDropEnabled, terminalEnabled, copyPathEnabled, moveEnabled, language
    }

    init(
        airDropEnabled: Bool = false, terminalEnabled: Bool = false, copyPathEnabled: Bool = false,
        moveEnabled: Bool = false, language: String? = nil
    ) {
        self.airDropEnabled = airDropEnabled
        self.terminalEnabled = terminalEnabled
        self.copyPathEnabled = copyPathEnabled
        self.moveEnabled = moveEnabled
        self.language = language
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        airDropEnabled = try values.decode(Bool.self, forKey: .airDropEnabled)
        terminalEnabled =
            values.contains(.terminalEnabled)
            ? try values.decode(Bool.self, forKey: .terminalEnabled) : Self.initial.terminalEnabled
        copyPathEnabled =
            values.contains(.copyPathEnabled)
            ? try values.decode(Bool.self, forKey: .copyPathEnabled) : Self.initial.copyPathEnabled
        moveEnabled =
            values.contains(.moveEnabled)
            ? try values.decode(Bool.self, forKey: .moveEnabled) : Self.initial.moveEnabled
    }

    func isEnabled(_ action: FinderAction) -> Bool {
        switch action {
        case .airDrop: airDropEnabled
        case .terminal: terminalEnabled
        case .copyPath: copyPathEnabled
        case .move: moveEnabled
        }
    }

    mutating func setEnabled(_ enabled: Bool, for action: FinderAction) {
        switch action {
        case .airDrop: airDropEnabled = enabled
        case .terminal: terminalEnabled = enabled
        case .copyPath: copyPathEnabled = enabled
        case .move: moveEnabled = enabled
        }
    }
}

struct FinderConfigurationStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("menus.json") }

    static func standard() throws -> FinderConfigurationStore {
        // Foundation home-directory APIs redirect into the extension container; passwd retains the real home.
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        var status = getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result)
        while status == ERANGE {
            buffer = [CChar](repeating: 0, count: buffer.count * 2)
            status = getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result)
        }
        guard status == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(status)) }
        guard result != nil, let homePath = entry.pw_dir else { throw CocoaError(.fileReadUnknown) }
        let home = withExtendedLifetime(buffer) { String(cString: homePath) }
        return FinderConfigurationStore(
            directory: URL(fileURLWithPath: home).appending(path: "Library/Application Support/Buckle/Finder"))
    }

    func load() throws -> FinderConfiguration {
        let data: Data
        do { data = try Data(contentsOf: file) } catch CocoaError.fileReadNoSuchFile { return .initial }
        return try JSONDecoder().decode(FinderConfiguration.self, from: data)
    }

    func save(_ configuration: FinderConfiguration) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(configuration).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private var moveKeyFile: URL { directory.appendingPathComponent("move-request.key") }

    func loadMoveKey() throws -> SymmetricKey {
        let data = try Data(contentsOf: moveKeyFile)
        guard data.count == 32 else { throw CocoaError(.fileReadCorruptFile) }
        return SymmetricKey(data: data)
    }

    // Only the host writes this key. The sandboxed extension has read-only access to this directory.
    func prepareMoveKey() throws {
        if FileManager.default.fileExists(atPath: moveKeyFile.path) {
            _ = try loadMoveKey()
            return
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        guard
            FileManager.default.createFile(
                atPath: moveKeyFile.path, contents: data, attributes: [.posixPermissions: 0o600])
        else { throw CocoaError(.fileWriteUnknown) }
    }

    @discardableResult
    func restoreDefaults() throws -> URL {
        let backup = directory.appendingPathComponent("menus-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: file, to: backup)
        try save(.initial)
        return backup
    }
}

enum FinderAction: String, CaseIterable {
    case airDrop = "airdrop"
    case terminal
    case copyPath = "copy-path"
    case move
}

enum FinderMenuContext {
    case items([URL])
    case container(URL)

    var files: [URL] {
        switch self {
        case .items(let files): files
        case .container(let directory): [directory]
        }
    }

    func directory() throws -> URL? {
        guard files.count == 1 else { return nil }
        let url = files[0]
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values.isDirectory == true && values.isPackage != true ? url : nil
    }
}

struct FinderActionRequest: Equatable {
    let action: FinderAction
    let files: [URL]
    let clipboardChangeCount: Int?
    let signature: Data?

    init(action: FinderAction, files: [URL], clipboardChangeCount: Int? = nil, signature: Data? = nil) throws {
        // Clipboard writes stay inside the extension and are never accepted through the public URL scheme.
        guard action != .copyPath else { throw RequestError.invalidRoute }
        guard !files.isEmpty,
            files.allSatisfy({
                $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")
            })
        else { throw RequestError.invalidFiles }
        guard action == .airDrop || files.count == 1 else { throw RequestError.invalidFiles }
        guard (action == .move) == (clipboardChangeCount != nil), clipboardChangeCount.map({ $0 >= 0 }) != false else {
            throw RequestError.invalidRoute
        }
        guard signature == nil || (action == .move && signature?.count == 32) else { throw RequestError.invalidRoute }
        self.signature = signature
        self.action = action
        self.files = files
        self.clipboardChangeCount = clipboardChangeCount
    }

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "buckle", components.host == "finder",
            let action = FinderAction(rawValue: String(components.path.dropFirst())),
            components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
            let items = components.queryItems,
            items.allSatisfy({ $0.name == "file" || $0.name == "clipboard" || $0.name == "signature" })
        else { throw RequestError.invalidRoute }
        let signatures = items.filter { $0.name == "signature" }
        guard signatures.count <= 1 else { throw RequestError.invalidRoute }
        let signature = try signatures.first.map { item -> Data in
            guard let value = item.value, let data = Data(base64Encoded: value), data.count == 32 else {
                throw RequestError.invalidRoute
            }
            return data
        }
        let counts = items.filter { $0.name == "clipboard" }
        guard counts.count <= 1 else { throw RequestError.invalidRoute }
        let count = try counts.first.map { item -> Int in
            guard let text = item.value, let value = Int(text), value >= 0 else { throw RequestError.invalidRoute }
            return value
        }
        let files = try items.filter { $0.name == "file" }.map { item in
            guard let value = item.value, let url = URL(string: value) else { throw RequestError.invalidFiles }
            return url
        }
        try self.init(action: action, files: files, clipboardChangeCount: count, signature: signature)
    }

    func signed(using key: SymmetricKey) throws -> Self {
        guard action == .move else { throw RequestError.invalidRoute }
        let signature = HMAC<SHA256>.authenticationCode(for: try signingData(), using: key)
        return try Self(
            action: action, files: files, clipboardChangeCount: clipboardChangeCount, signature: Data(signature))
    }

    func authenticates(using key: SymmetricKey) throws -> Bool {
        guard action == .move, let signature else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: try signingData(), using: key)
    }

    private func signingData() throws -> Data { Data(try url(includeSignature: false).absoluteString.utf8) }

    func url() throws -> URL { try url(includeSignature: true) }

    private func url(includeSignature: Bool) throws -> URL {
        var components = URLComponents()
        components.scheme = "buckle"
        components.host = "finder"
        components.path = "/" + action.rawValue
        components.queryItems = files.map { URLQueryItem(name: "file", value: $0.absoluteString) }
        if let clipboardChangeCount {
            components.queryItems?.append(URLQueryItem(name: "clipboard", value: String(clipboardChangeCount)))
        }
        if includeSignature, let signature {
            components.queryItems?.append(URLQueryItem(name: "signature", value: signature.base64EncodedString()))
        }
        guard let url = components.url else { throw RequestError.invalidRoute }
        return url
    }

    enum RequestError: Error { case invalidFiles, invalidRoute }
}

enum FinderRegistration {
    static func paths(in output: String) throws -> [URL] {
        try output.split(separator: "\n").compactMap { line in
            var entry = line.trimmingCharacters(in: .whitespaces)
            if let first = entry.first, "+-!=?".contains(first) {
                entry.removeFirst()
                entry = entry.trimmingCharacters(in: .whitespaces)
            }
            guard entry.hasPrefix(FinderIntegration.identifier + "(") else { return nil }
            let columns = entry.split(separator: "\t")
            guard columns.count >= 4, let path = columns.last, path.hasPrefix("/") else {
                throw ParseError.invalidRegistration
            }
            return URL(fileURLWithPath: String(path)).standardizedFileURL.resolvingSymlinksInPath()
        }
    }

    enum ParseError: Error { case invalidRegistration }
}
