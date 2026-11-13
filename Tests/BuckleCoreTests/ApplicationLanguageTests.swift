import Foundation
import Testing

@testable import BuckleCore

@Test func languageSelectionPersistsOverridesAndRestoresSystemPreferences() throws {
    let suite = "Buckle.LanguageTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = ApplicationLanguagePreferences(defaults: defaults)
    #expect(preferences.selection == .system)
    #expect(
        ApplicationLanguage.allCases.filter { $0 != .system }.map(\.rawValue)
            == BrowserLanguage.allCases.map(\.rawValue))
    for language in ApplicationLanguage.allCases where language != .system {
        preferences.select(language)
        #expect(defaults.stringArray(forKey: "AppleLanguages") == [language.rawValue])
        #expect(ApplicationLanguagePreferences(defaults: defaults).selection == language)
    }
    preferences.select(.system)
    #expect(preferences.selection == .system)
    #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
}
