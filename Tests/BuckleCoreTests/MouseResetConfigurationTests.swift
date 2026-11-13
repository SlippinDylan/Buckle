import Foundation
import Testing

@testable import BuckleCore

@Test func mouseResetPreferencesPreserveCustomAndEmptyListsAndRejectCorruption() throws {
    let suite = "Buckle.MouseResetTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = MouseResetPreferences(defaults: defaults)
    #expect(try preferences.load() == MouseResetTool.defaults)
    let custom = MouseResetTool(identifier: "example.InputUtility", name: "Input Utility")
    try preferences.save([custom])
    #expect(try MouseResetPreferences(defaults: defaults).load() == [custom])
    #expect(throws: CocoaError.self) { try preferences.save([custom, custom]) }
    #expect(try preferences.load() == [custom])
    try preferences.save([])
    #expect(try preferences.load().isEmpty)
    defaults.set(Data("invalid".utf8), forKey: "mouseReset.applications")
    #expect(throws: (any Error).self) { try preferences.load() }
    #expect(defaults.data(forKey: "mouseReset.applications") == Data("invalid".utf8))
}

@Test func mouseResetApplicationSelectionRejectsNonAppsAndBuckle() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
        do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) }
    }
    for identifier in ["example.InputUtility", "studio.slippindylan.Buckle"] {
        let app = directory.appendingPathComponent(identifier + ".app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL"],
            format: .xml, options: 0)
        try info.write(to: contents.appendingPathComponent("Info.plist"))
        if identifier == "studio.slippindylan.Buckle" {
            #expect(throws: CocoaError.self) { try MouseResetTool(applicationURL: app) }
        } else {
            #expect(try MouseResetTool(applicationURL: app).identifier == identifier)
        }
    }
    #expect(throws: CocoaError.self) { try MouseResetTool(applicationURL: directory) }
}
