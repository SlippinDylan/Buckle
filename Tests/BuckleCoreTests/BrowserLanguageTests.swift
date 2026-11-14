import Testing

@testable import BuckleCore

@Test func browserLanguagesDoNotAddStartupPagesOrChangeProfiles() {
    #expect(BrowserLanguage.allCases.map(\.rawValue) == ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es"])
    let locales = ["en", "zh-CN", "zh-TW", "ja", "ko", "de", "fr", "es"]
    for (language, locale) in zip(BrowserLanguage.allCases, locales) {
        #expect(
            language.arguments == [
                "--lang=\(locale)", "--accept-lang=\(locale)",
            ])
        #expect(!language.arguments.contains(where: { $0.hasPrefix("--user-data-dir") }))
        #expect(!language.arguments.contains(where: { $0.hasPrefix("--profile-directory") }))
    }
}
