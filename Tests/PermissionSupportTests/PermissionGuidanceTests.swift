import AppKit
import BucklePermissionSupport
import Testing

@Test @MainActor func permissionGuidanceUsesUpstreamTranslationsForAllAppLanguages() throws {
    let grantedTitles = [
        "en": "Granted", "zh-Hans": "已授权", "zh-Hant": "已授權", "ja": "許可済み",
        "ko": "허용됨", "de": "Erlaubt", "fr": "Autorisé", "es": "Concedido",
    ]
    let accessibilityTitles = [
        "en": ["Accessibility", "Device Control and Data Access"],
        "zh-Hans": ["辅助功能", "设备控制和数据访问"],
        "zh-Hant": ["輔助使用", "裝置控制和資料取用"],
        "ja": ["アクセシビリティ", "デバイスの制御とデータへのアクセス"],
        "ko": ["손쉬운 사용", "기기 제어 및 데이터 접근"],
        "de": ["Bedienungshilfen", "Gerätesteuerung und Datenzugriff"],
        "fr": ["Accessibilité", "Contrôle de l’appareil et accès aux données"],
        "es": ["Accesibilidad", "Control de dispositivos y acceso a datos"],
    ]
    for (language, title) in grantedTitles {
        let guidance = PermissionGuidance(localeIdentifier: language)
        let button = NSButton()
        guidance.configure(button, status: .granted)
        #expect(button.title == title)
        #expect(button.image != nil)
        #expect(button.contentTintColor == .systemGreen)
        let titles = try #require(accessibilityTitles[language])
        #expect(
            guidance.accessibilityTitle
                == titles[ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? 1 : 0])
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
