import AppKit

struct Browser: Identifiable {
    let id: String
    let name: String
    let url: URL
    let chromium: Bool
}

@MainActor
enum BrowserLauncher {
    static func installed() -> [Browser] {
        let candidates: [(String, String, Bool)] = [
            ("com.google.Chrome", "Google Chrome", true),
            ("com.google.Chrome.beta", "Google Chrome Beta", true),
            ("com.google.Chrome.canary", "Google Chrome Canary", true),
            ("org.chromium.Chromium", "Chromium", true),
            ("com.microsoft.edgemac", "Microsoft Edge", true),
            ("com.brave.Browser", "Brave", true),
            ("com.vivaldi.Vivaldi", "Vivaldi", true),
            ("com.operasoftware.Opera", "Opera", true),
            ("com.apple.Safari", "Safari", false),
            ("com.apple.SafariTechnologyPreview", "Safari Technology Preview", false),
        ]
        return candidates.compactMap { id, name, chromium in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return nil }
            return Browser(id: id, name: name, url: url, chromium: chromium)
        }
    }

    static func launch(_ browser: Browser, language: BrowserLanguage) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = true
        if browser.chromium {
            let profile = URL.applicationSupportDirectory.appending(
                path: "Buckle/BrowserProfiles/\(browser.id)/\(language.rawValue)")
            try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
            configuration.arguments = language.arguments(profile: profile)
        } else {
            // Safari owns a single profile process; a running instance cannot change language.
            guard NSRunningApplication.runningApplications(withBundleIdentifier: browser.id).isEmpty else {
                throw NSError(
                    domain: "Buckle.Browser", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: localized("browser.safari.running")])
            }
            configuration.arguments = ["-AppleLanguages", "(\(language.rawValue))"]
        }
        _ = try await NSWorkspace.shared.openApplication(at: browser.url, configuration: configuration)
    }
}
