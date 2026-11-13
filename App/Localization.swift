import Foundation

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func localizedFormat(_ key: String, _ value: String) -> String {
    String(format: localized(key), locale: Locale.current, value)
}

func localized(_ key: String, language: String?, bundle: Bundle = .main) -> String {
    guard let language else { return bundle.localizedString(forKey: key, value: nil, table: nil) }
    let supported = Bundle.preferredLocalizations(from: bundle.localizations, forPreferences: [language])
    guard let resolved = supported.first,
        let path = bundle.path(forResource: resolved, ofType: "lproj"), let localizedBundle = Bundle(path: path)
    else { return bundle.localizedString(forKey: key, value: nil, table: nil) }
    return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
}
