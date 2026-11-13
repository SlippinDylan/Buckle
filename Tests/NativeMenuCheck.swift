import AppKit

@main
enum NativeMenuCheck {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let lifecycle = ApplicationLifecycle()
        let mouse = MouseResetController(operations: MenuCheckMouseOperations(), lifecycle: lifecycle)
        let restart = MenuBarRestartController(
            operations: MenuCheckRestartOperations(), lifecycle: lifecycle)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: directory) } catch {
                preconditionFailure("Cannot remove test configuration: \(error)")
            }
        }
        let store = FinderConfigurationStore(directory: directory)
        let finder = FinderExtensionController(configurationStore: { store })
        try verifyUpdateStartup(in: directory.appendingPathComponent("update-startup.bundle"))
        try await verifyFinderSaveFailure(in: directory.appendingPathComponent("read-only"))
        await verifySettingsRows(finder: FinderExtensionController(configurationStore: { store }))
        var openedCategories: [ApplicationSettingsViewController.Category?] = []
        var memoryRequests = 0
        var mouseRequests = 0
        let controller = StatusMenuController(
            memoryPanel: SystemMemoryPanel(lifecycle: lifecycle), mouseReset: mouse, menuBarRestart: restart,
            finder: finder, lifecycle: lifecycle,
            openMemory: { memoryRequests += 1 }, openSettings: { openedCategories.append($0) },
            resetMouse: { mouseRequests += 1 })
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        precondition(
            menu.items.filter(\.isSectionHeader).map(\.title) == [
                localized("menu.system"), localized("menu.applications"), localized("settings.finder.actions"),
            ])
        precondition(menu.items.first?.view == nil, "The primary surface must use native menu items")
        precondition(menu.item(withTitle: localized("browser.launch"))?.submenu != nil)
        precondition(menu.item(withTitle: localized("menubar.restart")) != nil)
        precondition(
            menu.item(withTitle: localized("finder.checking")) != nil, "Finder status stays in the primary menu")
        let finderItems = menu.items.filter { item in
            FinderAction.allCases.contains { $0.rawValue == item.identifier?.rawValue }
        }
        precondition(
            finderItems.count == 4 && finderItems.allSatisfy { !$0.isEnabled && $0.state == .mixed },
            "Unexpected Finder items: \(finderItems.map { ($0.title, $0.identifier?.rawValue, $0.state.rawValue, $0.isEnabled) })"
        )
        await finder.refresh()
        controller.menuNeedsUpdate(menu)
        for action in FinderAction.allCases {
            guard let item = menu.items.first(where: { $0.identifier?.rawValue == action.rawValue }) else {
                preconditionFailure("Missing Finder toggle")
            }
            precondition(item.isEnabled && item.state == .off)
            menu.performActionForItem(at: menu.index(of: item))
            let saved = try store.load()
            precondition(saved.isEnabled(action))
            controller.menuNeedsUpdate(menu)
            precondition(menu.items.first { $0.identifier == item.identifier }?.state == .on)
        }
        for action in FinderAction.allCases {
            guard let item = menu.items.first(where: { $0.identifier?.rawValue == action.rawValue }) else {
                preconditionFailure("Missing Finder toggle")
            }
            menu.performActionForItem(at: menu.index(of: item))
            let saved = try store.load()
            precondition(!saved.isEnabled(action))
            controller.menuNeedsUpdate(menu)
            precondition(menu.items.first { $0.identifier == item.identifier }?.state == .off)
        }
        let saved = try store.load()
        precondition(saved == .initial)
        invoke(localized("memory.open.system"), in: menu)
        invoke(localized("mouse.reset"), in: menu)
        invoke(localized("settings.title"), in: menu)
        precondition(memoryRequests == 1 && mouseRequests == 1)
        precondition(openedCategories.count == 1 && openedCategories[0] == nil)
        precondition(menu.item(withTitle: localized("update.check")) == nil)
        precondition(menu.item(withTitle: localized("settings.about")) == nil)
        precondition(menu.item(withTitle: localized("settings.permissions")) == nil)
        precondition(menu.items.filter { $0.keyEquivalent == "," }.count == 1)
        precondition(menu.item(withTitle: localized("settings.title"))?.keyEquivalent == ",")
        precondition(menu.item(withTitle: localized("buckle.quit"))?.keyEquivalent == "q")

        await mouse.run()
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("mouse.show.progress")) != nil)
        precondition(menu.item(withTitle: localized("mouse.reset")) == nil)
        mouse.dismiss()
        precondition(lifecycle.requestTermination())
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("memory.open.system"))?.isEnabled == false)
        precondition(menu.item(withTitle: localized("mouse.reset"))?.isEnabled == false)
        print(
            "Native status menu actions, settings routing, grouped commands, reset results and quit gating verified without showing UI."
        )
    }

    @MainActor private static func verifyUpdateStartup(in directory: URL) throws {
        let contents = directory.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "studio.slippindylan.Buckle.UpdateStartupCheck",
            "BuckleUpdaterEnabled": "YES",
            "SUFeedURL": "invalid-feed",
            "SUPublicEDKey": "invalid-key",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        guard let bundle = Bundle(url: directory) else { preconditionFailure("Missing test bundle") }
        let unconfigured = ApplicationUpdateController(bundle: bundle)
        guard case .disabled = unconfigured.state else {
            preconditionFailure(
                "Constructing the updater must not start it before application ownership is established")
        }
        unconfigured.start()
        guard case .unconfigured = unconfigured.state else {
            preconditionFailure("Application startup must validate update configuration without opening Settings")
        }
        precondition(!unconfigured.isAvailable && !unconfigured.canCheck)
        unconfigured.start()
        guard case .unconfigured = unconfigured.state else {
            preconditionFailure("Retrying invalid startup must preserve the configuration error")
        }

        let disabled = ApplicationUpdateController()
        disabled.start()
        disabled.start()
        guard case .disabled = disabled.state else { preconditionFailure("Test-binary updates must stay disabled") }
        precondition(disabled.status == nil && !disabled.isAvailable && !disabled.canCheck)
    }

    @MainActor private static func verifyFinderSaveFailure(in directory: URL) async throws {
        let store = FinderConfigurationStore(directory: directory)
        try store.save(.initial)
        let finder = FinderExtensionController(configurationStore: { store })
        await finder.refresh()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            do { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) } catch
            { preconditionFailure("Cannot restore test directory permissions: \(error)") }
        }
        do {
            try finder.setEnabled(true, for: .terminal)
            preconditionFailure("Saving to a read-only directory must throw")
        } catch CocoaError.fileWriteNoPermission {}
        let saved = try store.load()
        precondition(saved == .initial && finder.configuration == saved)
        if case .failed = finder.state {
            preconditionFailure("A configuration write error must not replace the extension registration state")
        }
        await finder.refresh()
        precondition(finder.configuration == saved)
    }

    @MainActor private static func verifySettingsRows(
        finder: FinderExtensionController
    ) async {
        precondition(ApplicationSettingsViewController.Category.allCases == [.general, .permissions, .about])
        let lifecycle = ApplicationLifecycle()
        let operations = MenuCheckPanelOperations()
        let panel = SystemMemoryPanel(operations: operations, lifecycle: lifecycle)
        await panel.refreshPermissions()
        let settings = ApplicationSettingsViewController(
            memoryPanel: panel, finder: finder,
            updates: ApplicationUpdateController(), lifecycle: lifecycle)
        settings.view.setFrameSize(NSSize(width: 400, height: 450))
        settings.view.layoutSubtreeIfNeeded()
        let generalButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(!generalButtons.contains { $0.title == localized("update.check") })
        guard let languages = descendants(of: settings.view).compactMap({ $0 as? NSPopUpButton }).first else {
            preconditionFailure("General settings must expose a language picker")
        }
        precondition(
            languages.itemArray.compactMap { $0.representedObject as? String }
                == ApplicationLanguage.allCases.map(\.rawValue))
        precondition(
            ApplicationUpdateController().status == nil, "Debug updates remain disabled without a development message")
        let switches = descendants(of: settings.view).compactMap { $0 as? NSSwitch }
        precondition(switches.count == 2)
        for control in switches {
            guard let row = control.superview as? NSStackView else {
                preconditionFailure("A switch must belong to a settings row")
            }
            precondition(
                row.arrangedSubviews.count == 3, "Settings rows need a flexible spacer between label and switch")
            precondition(
                abs(control.frame.maxX - row.bounds.maxX) < 0.5, "Settings switches must align to the trailing edge")
        }
        settings.selectCategory(.permissions)
        let permissionButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(!permissionButtons.contains { $0.action == NSSelectorFromString("checkPermissions") })
        var grantedLabels = descendants(of: settings.view).compactMap { $0 as? NSTextField }
            .filter { $0.textColor == .systemGreen }
        precondition(grantedLabels.count == 2, "Granted permissions must use green status labels")
        precondition(grantedLabels.allSatisfy { !$0.stringValue.isEmpty })

        let checks = operations.requests.count
        settings.refreshPermissionStatus()
        while operations.requests.count == checks { await Task.yield() }
        while panel.isCheckingPermissions { await Task.yield() }
        precondition(operations.requests.allSatisfy { !$0 }, "Automatic checks must not request authorization")
        operations.accessibilityGranted = false
        await panel.refreshPermissions()
        settings.refresh()
        grantedLabels = descendants(of: settings.view).compactMap { $0 as? NSTextField }
            .filter { $0.textColor == .systemGreen }
        precondition(grantedLabels.count == 1, "Revoked permissions must stop displaying a granted status")
        let grantButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(grantButtons.contains { $0.action == NSSelectorFromString("openAccessibility:") })
        precondition(lifecycle.requestTermination())
        settings.refresh()
        let pendingButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(pendingButtons.allSatisfy { !$0.isEnabled }, "Quit must disable permission actions")
        let finishedChecks = operations.requests.count
        settings.refreshPermissionStatus()
        await Task.yield()
        precondition(operations.requests.count == finishedChecks)
    }

    @MainActor private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor private static func invoke(_ title: String, in menu: NSMenu) {
        let index = menu.indexOfItem(withTitle: title)
        precondition(index >= 0, "Expected native menu item: \(title)")
        menu.performActionForItem(at: index)
    }
}

@MainActor
private struct MenuCheckMouseOperations: MouseResetOperations {
    func perform(_ step: MouseResetStep) async throws {}
    func restoreApps() async throws {}
}

@MainActor
private struct MenuCheckRestartOperations: MenuBarRestartOperations {
    func restart() async throws { preconditionFailure("Menu checks must not restart system services") }
}

@MainActor
private final class MenuCheckPanelOperations: SystemMemoryPanelOperations {
    var accessibilityGranted = true
    var requests: [Bool] = []

    func debugValue() -> CFPropertyList? { nil }
    func setDebugValue(_ value: CFPropertyList?) throws {
        preconditionFailure("Settings checks must not change system preferences")
    }
    func trigger() async throws { preconditionFailure("Settings checks must not open system windows") }
    func permissions(requestPermission: Bool) async throws -> MemoryPanelPermissions {
        requests.append(requestPermission)
        return MemoryPanelPermissions(accessibilityGranted: accessibilityGranted, automationGranted: true)
    }
}
