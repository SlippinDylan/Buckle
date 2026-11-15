import AppKit
import BucklePermissionSupport

@MainActor
final class ApplicationSettingsWindowController: NSWindowController, NSToolbarDelegate {
    private let settingsViewController: ApplicationSettingsViewController
    private let settingsToolbar = NSToolbar(identifier: "application-settings")

    init(
        memoryPanel: SystemMemoryPanel, finder: FinderExtensionController,
        updates: ApplicationUpdateController, lifecycle: ApplicationLifecycle,
        permissionGuidance: PermissionGuidance = PermissionGuidance()
    ) {
        settingsViewController = ApplicationSettingsViewController(
            memoryPanel: memoryPanel, finder: finder, updates: updates, lifecycle: lifecycle,
            permissionGuidance: permissionGuidance
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 450),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentViewController = settingsViewController
        window.setContentSize(NSSize(width: 400, height: 450))
        window.title = ""
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: window)
        shouldCascadeWindows = false
        settingsToolbar.delegate = self
        settingsToolbar.displayMode = .iconAndLabel
        settingsToolbar.allowsUserCustomization = false
        settingsToolbar.autosavesConfiguration = false
        window.toolbarStyle = .preference
        window.toolbar = settingsToolbar
        window.titlebarSeparatorStyle = .none
        settingsToolbar.selectedItemIdentifier =
            ApplicationSettingsViewController.Category.general.toolbarItemIdentifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func present(category: ApplicationSettingsViewController.Category? = nil) {
        guard let window else { return }
        if let category {
            settingsViewController.selectCategory(category)
            settingsToolbar.selectedItemIdentifier = category.toolbarItemIdentifier
        }
        settingsViewController.refresh()
        settingsViewController.refreshPermissionStatus()
        if !window.isVisible { window.center() }
        NSApp.activate()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func requestPermission(_ requirement: PermissionRequirement, from view: NSView) {
        settingsViewController.requestPermission(requirement, from: view)
    }

    func refresh() {
        if window?.isVisible == true {
            settingsViewController.refresh()
            settingsViewController.refreshPermissionStatus()
        }
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        ApplicationSettingsViewController.Category.allCases.map(\.toolbarItemIdentifier)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarAllowedItemIdentifiers(toolbar)
    }

    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        guard
            let category = ApplicationSettingsViewController.Category.allCases.first(where: {
                $0.toolbarItemIdentifier == identifier
            })
        else { return nil }
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = category.title
        item.paletteLabel = category.title
        item.toolTip = category.title
        item.image = NSImage(systemSymbolName: category.symbol, accessibilityDescription: category.title)?
            .withSymbolConfiguration(.init(pointSize: 18, weight: .regular))
        item.target = self
        item.action = #selector(selectCategory(_:))
        item.tag = category.rawValue
        item.isBordered = false
        return item
    }

    @objc private func selectCategory(_ sender: NSToolbarItem) {
        guard let category = ApplicationSettingsViewController.Category(rawValue: sender.tag) else {
            preconditionFailure("Settings toolbar items must identify a category")
        }
        settingsViewController.selectCategory(category)
        settingsViewController.refreshPermissionStatus()
        settingsToolbar.selectedItemIdentifier = category.toolbarItemIdentifier
    }
}
