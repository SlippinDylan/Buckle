import Darwin
import Foundation

enum FinderIntegration {
    static let identifier = "studio.slippindylan.Buckle.Finder"
    static let bundleName = "BuckleFinder.appex"
}

struct FinderConfiguration: Codable, Equatable {
    var airDropEnabled: Bool
    static let initial = FinderConfiguration(airDropEnabled: true)
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

    @discardableResult
    func restoreDefaults() throws -> URL {
        let backup = directory.appendingPathComponent("menus-backup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: file, to: backup)
        try save(.initial)
        return backup
    }
}

struct FinderAirDropRequest: Equatable {
    let files: [URL]

    init(files: [URL]) throws {
        guard !files.isEmpty,
            files.allSatisfy({
                $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost")
            })
        else { throw RequestError.invalidFiles }
        self.files = files
    }

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == "buckle", components.host == "finder", components.path == "/airdrop",
            components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
            let items = components.queryItems, items.allSatisfy({ $0.name == "file" })
        else { throw RequestError.invalidRoute }
        let files = try items.map { item in
            guard let value = item.value, let url = URL(string: value) else { throw RequestError.invalidFiles }
            return url
        }
        try self.init(files: files)
    }

    func url() throws -> URL {
        var components = URLComponents()
        components.scheme = "buckle"
        components.host = "finder"
        components.path = "/airdrop"
        components.queryItems = files.map { URLQueryItem(name: "file", value: $0.absoluteString) }
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
