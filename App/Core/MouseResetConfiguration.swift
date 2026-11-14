import Foundation

struct MouseResetTool: Codable, Equatable, Sendable {
    let identifier: String
    let name: String

    static let defaults = [
        MouseResetTool(identifier: "com.manytricks.Moom", name: "Moom"),
        MouseResetTool(identifier: "app.monitorcontrol.MonitorControl", name: "MonitorControl"),
        MouseResetTool(identifier: "com.naotanhaocan.BetterMouse", name: "BetterMouse"),
        MouseResetTool(identifier: "cn.better365.iShotPro", name: "iShot Pro"),
    ]

    init(identifier: String, name: String) {
        self.identifier = identifier
        self.name = name
    }

    init(applicationURL: URL) throws {
        guard applicationURL.isFileURL, applicationURL.pathExtension == "app",
            let bundle = Bundle(url: applicationURL),
            bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
            let identifier = bundle.bundleIdentifier, !identifier.isEmpty,
            identifier != "studio.slippindylan.Buckle"
        else { throw CocoaError(.fileReadCorruptFile) }
        self.identifier = identifier
        name = FileManager.default.displayName(atPath: applicationURL.path)
    }
}

struct MouseResetPreferences {
    let defaults: UserDefaults
    private let key = "mouseReset.applications"
    private let serviceWaitKey = "mouseReset.serviceWaitSeconds"
    static let defaultServiceWaitSeconds = 3
    static let serviceWaitRange = 0...60

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() throws -> [MouseResetTool] {
        guard let stored = defaults.object(forKey: key) else { return MouseResetTool.defaults }
        guard let data = stored as? Data else { throw CocoaError(.coderReadCorrupt) }
        let tools = try JSONDecoder().decode([MouseResetTool].self, from: data)
        try validate(tools)
        return tools
    }

    func save(_ tools: [MouseResetTool]) throws {
        try validate(tools)
        defaults.set(try JSONEncoder().encode(tools), forKey: key)
    }

    func loadServiceWaitSeconds() throws -> Int {
        guard let stored = defaults.object(forKey: serviceWaitKey) else { return Self.defaultServiceWaitSeconds }
        guard let seconds = stored as? Int, Self.serviceWaitRange.contains(seconds) else {
            throw CocoaError(.coderReadCorrupt)
        }
        return seconds
    }

    func saveServiceWaitSeconds(_ seconds: Int) throws {
        guard Self.serviceWaitRange.contains(seconds) else { throw CocoaError(.coderInvalidValue) }
        defaults.set(seconds, forKey: serviceWaitKey)
    }

    private func validate(_ tools: [MouseResetTool]) throws {
        guard Set(tools.map(\.identifier)).count == tools.count,
            tools.allSatisfy({
                !$0.identifier.isEmpty && !$0.name.isEmpty && $0.identifier != "studio.slippindylan.Buckle"
            })
        else { throw CocoaError(.coderReadCorrupt) }
    }
}
