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
    let request = try FinderAirDropRequest(files: files)
    #expect(try FinderAirDropRequest(url: request.url()).files == files)
}

@Test func finderAirDropRejectsRemoteFilesAndUnrecognizedCommands() throws {
    let routes = [
        "https://finder/airdrop?file=file:///tmp/a",
        "buckle://other/airdrop?file=file:///tmp/a",
        "buckle://finder/delete?file=file:///tmp/a",
        "buckle://finder/airdrop",
        "buckle://finder/airdrop?file",
        "buckle://finder/airdrop?file=https://example.com/a",
        "buckle://finder/airdrop?file=file://remote/tmp/a",
        "buckle://finder/airdrop?file=file:///tmp/a&command=anything",
        "buckle://finder/airdrop?file=file:///tmp/a#fragment",
    ]
    for route in routes {
        let url = try #require(URL(string: route))
        #expect(throws: FinderAirDropRequest.RequestError.self) { try FinderAirDropRequest(url: url) }
    }
    #expect(throws: FinderAirDropRequest.RequestError.self) { try FinderAirDropRequest(files: []) }
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
