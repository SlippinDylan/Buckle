import Foundation

public enum BrowserLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"

    public var name: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        case .traditionalChinese: "繁體中文"
        case .japanese: "日本語"
        case .korean: "한국어"
        case .german: "Deutsch"
        case .french: "Français"
        case .spanish: "Español"
        }
    }

    public var chromiumLocale: String {
        switch self {
        case .simplifiedChinese: "zh-CN"
        case .traditionalChinese: "zh-TW"
        default: rawValue
        }
    }

    public func arguments(profile: URL) -> [String] {
        [
            "--user-data-dir=\(profile.path)", "--lang=\(chromiumLocale)", "--accept-lang=\(chromiumLocale)",
            "--no-first-run", "-AppleLanguages",
            "(\(rawValue))",
        ]
    }
}
