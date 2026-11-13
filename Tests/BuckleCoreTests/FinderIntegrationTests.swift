import Foundation
import Testing

@testable import BuckleCore

@Test func finderSettingsPersistAndRejectCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
    }
    let store = FinderConfigurationStore(directory: directory)
    #expect(try store.load() == .initial)
    let initial = try store.load()
    #expect(FinderAction.allCases.allSatisfy { !initial.isEnabled($0) })
    try store.save(FinderConfiguration(airDropEnabled: false))
    #expect(try store.load().airDropEnabled == false)
    try Data("invalid JSON".utf8).write(to: directory.appendingPathComponent("menus.json"))
    #expect(throws: DecodingError.self) { try store.load() }
    let backup = try store.restoreDefaults()
    #expect(try Data(contentsOf: backup) == Data("invalid JSON".utf8))
    #expect(try store.load() == .initial)
    #expect(backup.deletingLastPathComponent().path == directory.path)
}

@Test func finderAirDropRequestPreservesMultipleLiteralPaths() throws {
    let files = [
        URL(fileURLWithPath: "/tmp/文件夹/a b+#?.pdf"),
        URL(fileURLWithPath: "/tmp/'$(literal);.txt"),
    ]
    let request = try FinderActionRequest(action: .airDrop, files: files)
    #expect(try FinderActionRequest(url: request.url()).files == files)
}

@Test func finderAirDropRejectsRemoteFilesAndUnrecognizedCommands() throws {
    let routes = [
        "https://finder/airdrop?file=file:///tmp/a",
        "buckle://other/airdrop?file=file:///tmp/a",
        "buckle://finder/delete?file=file:///tmp/a",
        "buckle://finder/copy-path?file=file:///tmp/a",
        "buckle://finder/move?file=file:///tmp/a",
        "buckle://finder/move?file=file:///tmp/a&clipboard=-1",
        "buckle://finder/move?file=file:///tmp/a&clipboard=1&clipboard=2",
        "buckle://finder/airdrop?file=file:///tmp/a&clipboard=1",
        "buckle://finder/airdrop",
        "buckle://finder/airdrop?file",
        "buckle://finder/airdrop?file=https://example.com/a",
        "buckle://finder/airdrop?file=file://remote/tmp/a",
        "buckle://finder/airdrop?file=file:///tmp/a&command=anything",
        "buckle://finder/airdrop?file=file:///tmp/a#fragment",
    ]
    for route in routes {
        let url = try #require(URL(string: route))
        #expect(throws: FinderActionRequest.RequestError.self) { try FinderActionRequest(url: url) }
    }
    #expect(throws: FinderActionRequest.RequestError.self) { try FinderActionRequest(action: .airDrop, files: []) }
}

@Test func finderRegistrationMatchesExactIdentifierAndBundlePaths() throws {
    let output = """
        +    studio.slippindylan.Buckle.Finder(0.1.0)\tUUID\t2026-11-13\t/Applications/Buckle.app/Contents/PlugIns/BuckleFinder.appex
        -    studio.slippindylan.Buckle.Finder(0.1.0)\tUUID\t2026-11-13\t/tmp/Test App.app/Contents/PlugIns/BuckleFinder.appex
        +    other.studio.slippindylan.Buckle.Finder(0.1.0)\tUUID\t2026-11-13\t/tmp/Other.appex
          (3 plug-ins)
        """
    let paths = try FinderRegistration.paths(in: output)
    #expect(paths.count == 2)
    #expect(paths[1].path == "/tmp/Test App.app/Contents/PlugIns/BuckleFinder.appex")
    #expect(try FinderRegistration.paths(in: "  (no matches)\n").isEmpty)
    #expect(throws: FinderRegistration.ParseError.self) {
        try FinderRegistration.paths(in: "studio.slippindylan.Buckle.Finder(0.1.0) no bundle path")
    }
}

@Test func finderSettingsUpgradeWithoutResettingExistingSwitches() throws {
    let decoder = JSONDecoder()
    let old = try decoder.decode(FinderConfiguration.self, from: Data(#"{"airDropEnabled":false}"#.utf8))
    #expect(old == .initial)
    let oldEnabled = try decoder.decode(FinderConfiguration.self, from: Data(#"{"airDropEnabled":true}"#.utf8))
    #expect(oldEnabled.airDropEnabled)
    #expect(!oldEnabled.terminalEnabled && !oldEnabled.copyPathEnabled && !oldEnabled.moveEnabled)
    #expect(FinderConfiguration(airDropEnabled: true) == oldEnabled)
    let explicit = try decoder.decode(
        FinderConfiguration.self,
        from: Data(#"{"airDropEnabled":false,"terminalEnabled":true,"copyPathEnabled":false,"moveEnabled":true}"#.utf8))
    #expect(!explicit.airDropEnabled && explicit.terminalEnabled && !explicit.copyPathEnabled && explicit.moveEnabled)
    for key in ["airDropEnabled", "terminalEnabled", "copyPathEnabled", "moveEnabled"] {
        for invalid in ["null", #""yes""#] {
            let json =
                key == "airDropEnabled" ? "{\"\(key)\":\(invalid)}" : "{\"airDropEnabled\":false,\"\(key)\":\(invalid)}"
            #expect(throws: DecodingError.self) {
                try decoder.decode(FinderConfiguration.self, from: Data(json.utf8))
            }
        }
    }
    #expect(old.language == nil)
    var updated = explicit
    updated.language = "ja"
    updated.setEnabled(false, for: .terminal)
    #expect(!updated.airDropEnabled && !updated.terminalEnabled && !updated.copyPathEnabled && updated.moveEnabled)
    #expect(try decoder.decode(FinderConfiguration.self, from: JSONEncoder().encode(updated)) == updated)
}

@Test func finderFolderActionsUseExactlyOneRealDirectory() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
    let file = root.appendingPathComponent("中文 '$(literal);+#?.txt")
    try Data().write(to: file)
    #expect(try FinderMenuContext.items([root]).directory() == root)
    #expect(try FinderMenuContext.container(root).directory() == root)
    #expect(try FinderMenuContext.items([file]).directory() == nil)
    #expect(try FinderMenuContext.items([root, file]).directory() == nil)
    let request = try FinderActionRequest(action: .terminal, files: [root])
    #expect(try FinderActionRequest(url: request.url()) == request)
    #expect(throws: FinderActionRequest.RequestError.self) {
        try FinderActionRequest(action: .terminal, files: [root, file])
    }
}

@Test func finderMoveRequestCapturesClipboardVersionAndPreservesDestination() throws {
    let destination = URL(fileURLWithPath: "/tmp/中文 '$(literal); #?")
    let request = try FinderActionRequest(action: .move, files: [destination], clipboardChangeCount: 123)
    #expect(try FinderActionRequest(url: request.url()) == request)
    #expect(throws: FinderActionRequest.RequestError.self) {
        try FinderActionRequest(action: .move, files: [destination])
    }
}
