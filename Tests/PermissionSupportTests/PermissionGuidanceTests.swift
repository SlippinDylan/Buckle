import AppKit
import BucklePermissionSupport
import Testing

@Test @MainActor func permissionGuidanceUsesUpstreamTranslationsForAllAppLanguages() {
    let grantedTitles = [
        "en": "Granted", "zh-Hans": "已授权", "zh-Hant": "已授權", "ja": "許可済み",
        "ko": "허용됨", "de": "Erlaubt", "fr": "Autorisé", "es": "Concedido",
    ]
    for (language, title) in grantedTitles {
        let guidance = PermissionGuidance(localeIdentifier: language)
        let button = NSButton()
        guidance.configure(button, status: .granted)
        #expect(button.title == title)
        #expect(button.image != nil)
        #expect(button.contentTintColor == .systemGreen)
        #expect(!guidance.accessibilityTitle.hasPrefix("permission_flow."))
        guidance.close()
    }
}

@Test @MainActor func permissionGuidanceKeepsUnknownAndDeniedDistinctFromGranted() {
    let guidance = PermissionGuidance(localeIdentifier: "en")
    let button = NSButton()
    for (status, title) in [
        (PermissionGuidance.Status.checking, "Checking..."), (.notGranted, "Grant"), (.unknown, "Open"),
    ] {
        guidance.configure(button, status: status)
        #expect(button.title == title)
        #expect(button.contentTintColor == .systemBlue)
    }
    guidance.close()
}
