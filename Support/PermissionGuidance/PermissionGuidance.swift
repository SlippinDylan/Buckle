import AppKit
import ApplicationServices
import Combine
import PermissionFlow
import SystemSettingsKit

@MainActor
public final class PermissionGuidance {
    public enum Status { case checking, granted, notGranted, unknown }

    private let authorizeAccessibility: (CGRect?) -> Void
    private let closePanel: () -> Void
    private let accessibilityGranted: () -> Bool
    private let localeIdentifier: String
    private var observers: Set<AnyCancellable> = []

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

    public convenience init(
        appURL: URL = Bundle.main.bundleURL, localeIdentifier: String? = Bundle.main.preferredLocalizations.first
    ) {
        _ = Self.registeredResources
        let controller = PermissionFlow.makeController(
            configuration: .init(
                requiredAppURLs: [appURL], promptForAccessibilityTrust: false,
                localeIdentifier: localeIdentifier ?? "en"))
        self.init(
            localeIdentifier: localeIdentifier ?? "en",
            authorizeAccessibility: { controller.authorize(pane: .accessibility, sourceFrameInScreen: $0) },
            closePanel: { controller.closePanel() }, accessibilityGranted: { AXIsProcessTrusted() })
    }

    init(
        localeIdentifier: String = "en", authorizeAccessibility: @escaping (CGRect?) -> Void,
        closePanel: @escaping () -> Void, accessibilityGranted: @escaping () -> Bool
    ) {
        self.localeIdentifier = localeIdentifier
        self.authorizeAccessibility = authorizeAccessibility
        self.closePanel = closePanel
        self.accessibilityGranted = accessibilityGranted
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
        close()
        let sourceFrame = view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) }
        authorizeAccessibility(sourceFrame)
        guard !accessibilityGranted() else {
            close()
            return
        }

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.close() }
            .store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .sink { [weak self] in self?.applicationTerminated(bundleIdentifier: $0.bundleIdentifier) }
            .store(in: &observers)
        Timer.publish(every: 0.5, tolerance: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if self.accessibilityGranted() { self.close() }
            }
            .store(in: &observers)
    }

    func applicationTerminated(bundleIdentifier: String?) {
        if bundleIdentifier == "com.apple.systempreferences" { close() }
    }

    public func showAutomation() {
        // Automation permissions are created by Apple Events, not by dragging an app into a list.
        close()
        SystemSettings.open(.privacy(anchor: .privacyAutomation))
    }

    public func close() {
        observers.removeAll()
        closePanel()
    }
}
