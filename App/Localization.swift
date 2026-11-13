import Foundation

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func localizedFormat(_ key: String, _ value: String) -> String {
    String(format: localized(key), locale: Locale.current, value)
}
