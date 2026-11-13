import Foundation

enum ApplicationLanguage: String, CaseIterable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case german = "de"
    case french = "fr"
    case spanish = "es"

    var nativeName: String {
        switch self {
        case .system: "System"
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
}

struct ApplicationLanguagePreferences {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var selection: ApplicationLanguage {
        defaults.string(forKey: "application.language").flatMap(ApplicationLanguage.init(rawValue:)) ?? .system
    }

    func select(_ language: ApplicationLanguage) {
        defaults.set(language.rawValue, forKey: "application.language")
        // Remove only the application's override so Foundation can use the system preferences again.
        if language == .system {
            defaults.removeObject(forKey: "AppleLanguages")
        } else {
            defaults.set([language.rawValue], forKey: "AppleLanguages")
        }
    }
}
