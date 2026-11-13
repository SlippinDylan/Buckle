import AppKit
import PermissionFlow
import SystemSettingsKit

@MainActor
public final class PermissionGuidance {
    public enum Status { case checking, granted, notGranted, unknown }

    private let controller: PermissionFlowController
    private let localeIdentifier: String

    // Register the SwiftPM resource bundle before upstream caches its lookup. The native test
    // runner lives in Xcode's toolchain, while resources sit beside the loaded test bundle.
    // Bundle.allBundles includes dynamically created resource bundles without loading executable code.
    private static let registeredResources: Bundle? = {
        let host = Bundle(for: PermissionGuidance.self)
        let directories = [host.resourceURL, host.bundleURL.deletingLastPathComponent(), Bundle.main.resourceURL]
        for directory in directories.compactMap({ $0 }) {
            if let bundle = Bundle(
                url: directory.appendingPathComponent(
                    PermissionFlowResources.resourceBundleName + ".bundle"))
            {
                return bundle
            }
        }
        return nil
    }()

    public init(
        appURL: URL = Bundle.main.bundleURL, localeIdentifier: String? = Bundle.main.preferredLocalizations.first
    ) {
        _ = Self.registeredResources
        self.localeIdentifier = localeIdentifier ?? "en"
        controller = PermissionFlow.makeController(
            configuration: .init(
                requiredAppURLs: [appURL], promptForAccessibilityTrust: false, localeIdentifier: self.localeIdentifier))
    }

    public var accessibilityTitle: String {
        PermissionFlowResources.localizedString(
            for: PermissionFlowResources.accessibilityName(), defaultValue: "Accessibility",
            localeIdentifier: localeIdentifier)
    }

    public func configure(_ button: NSButton, status: Status) {
        let authorizationState: PermissionAuthorizationState
        switch status {
        case .checking: authorizationState = .checking
        case .granted: authorizationState = .granted
        case .notGranted: authorizationState = .notGranted
        case .unknown: authorizationState = .unknown
        }
        let state = PermissionFlowButtonState.make(from: authorizationState)
        button.title = PermissionFlowResources.localizedString(
            for: state.titleKey, defaultValue: state.defaultTitle, localeIdentifier: localeIdentifier)
        button.image = NSImage(systemSymbolName: state.systemImage, accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.contentTintColor = state.isGranted ? .systemGreen : .systemBlue
    }

    public func showAccessibility(from view: NSView) {
        let sourceFrame = view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) }
        controller.authorize(pane: .accessibility, sourceFrameInScreen: sourceFrame)
    }

    public func showAutomation() {
        // Automation permissions are created by Apple Events, not by dragging an app into a list.
        close()
        SystemSettings.open(.privacy(anchor: .privacyAutomation))
    }

    public func close() { controller.closePanel() }
}
