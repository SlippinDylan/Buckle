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
        case .japanese: "ja-JP"
        default: rawValue
        }
    }

    public var arguments: [String] {
        // Chromium treats positional arguments as startup URLs; pass language switches only.
        let acceptedLanguages = self == .japanese ? "ja-JP,ja" : chromiumLocale
        return ["--lang=\(chromiumLocale)", "--accept-lang=\(acceptedLanguages)"]
    }

    public var environment: [String: String] {
        self == .japanese ? ["TZ": "Asia/Tokyo"] : [:]
    }
}
