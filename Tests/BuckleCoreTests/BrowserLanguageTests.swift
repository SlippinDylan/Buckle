import Foundation
import Testing

@testable import BuckleCore

@Test func browserLanguagesMatchAppAndSeparateProfiles() {
    #expect(BrowserLanguage.allCases.map(\.rawValue) == ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es"])
    let arguments = BrowserLanguage.simplifiedChinese.arguments(
        profile: URL(fileURLWithPath: "/tmp/profile with spaces"))
    #expect(arguments.contains("--lang=zh-CN"))
    #expect(arguments.contains("--user-data-dir=/tmp/profile with spaces"))
    #expect(arguments.contains("(zh-Hans)"))
}
