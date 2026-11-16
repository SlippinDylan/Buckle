import AppKit

@main
enum NativeMenuCheck {
    @MainActor static func main() async throws {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let lifecycle = ApplicationLifecycle()
        let mouse = MouseResetController(operations: MenuCheckMouseOperations(), lifecycle: lifecycle)
        let restart = MenuBarRestartController(
            operations: MenuCheckRestartOperations(), lifecycle: lifecycle)
        let panelOperations = MenuCheckPanelOperations()
        let panel = SystemMemoryPanel(operations: panelOperations, lifecycle: lifecycle)
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
        try await verifyMoveKeyIsolation(in: directory.appendingPathComponent("damaged-move-key"))
        try await verifyOnboardingFailureRouting(in: directory.appendingPathComponent("onboarding-errors"))
        verifyOnboardingTerminationRecovery()
        await verifySettingsRows(finder: FinderExtensionController(configurationStore: { store }))
        var openedCategories: [ApplicationSettingsViewController.Category?] = []
        var memoryRequests = 0
        var mouseRequests = 0
        let dockSuite = "Buckle.NativeMenuCheck.Dock.\(UUID().uuidString)"
        guard let dockDefaults = UserDefaults(suiteName: dockSuite) else {
            preconditionFailure("Cannot create isolated Dock preferences")
        }
        defer { dockDefaults.removePersistentDomain(forName: dockSuite) }
        let dock = DockMiddleClickController(
            lifecycle: lifecycle, defaults: dockDefaults, accessibilityGranted: { false })
        let controller = StatusMenuController(
            memoryPanel: panel, mouseReset: mouse, menuBarRestart: restart,
            finder: finder, lifecycle: lifecycle, dock: dock,
            openMemory: { memoryRequests += 1 }, openSettings: { openedCategories.append($0) },
            resetMouse: { mouseRequests += 1 })
        let menu = NSMenu()
        controller.menuNeedsUpdate(menu)
        guard let quitActions = menu.item(withTitle: localized("dock.quit.action"))?.submenu else {
            preconditionFailure("Missing Dock action submenu")
        }
        precondition(quitActions.items.map(\.title) == [localized("dock.quit.normal"), localized("dock.quit.force")])
        precondition(quitActions.items.map(\.state) == [.on, .off])
        quitActions.performActionForItem(at: 1)
        precondition(dock.quitAction == .force)
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("dock.quit.action"))?.submenu?.items.map(\.state) == [.off, .on])
        precondition(!dock.isEnabled, "Selecting an action must not enable event filtering")
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
            finderItems.count == FinderAction.allCases.count
                && finderItems.allSatisfy { !$0.isEnabled && $0.state == .mixed },
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
        precondition(saved == FinderConfiguration(language: Bundle.main.preferredLocalizations.first))
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

        panelOperations.suspends = true
        let authorization = Task { try await panel.requestAutomationPermission() }
        while panelOperations.continuation == nil { await Task.yield() }
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("memory.open.system"))?.isEnabled == false)
        panelOperations.continuation?.resume()
        try await authorization.value
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("memory.open.system"))?.isEnabled == true)

        precondition(lifecycle.begin(.mouseReset))
        controller.menuNeedsUpdate(menu)
        precondition(
            menu.item(withTitle: localized("mouse.reset"))?.isEnabled == false,
            "An idle reset controller cannot start work while startup recovery owns the operation")
        lifecycle.end(.mouseReset)
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("mouse.reset"))?.isEnabled == true)

        await mouse.run()
        controller.menuNeedsUpdate(menu)
        precondition(menu.item(withTitle: localized("mouse.show.progress")) != nil)
        precondition(menu.item(withTitle: localized("mouse.show.progress"))?.isEnabled == true)
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
            "AppUpdaterEnabled": "YES",
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

        let lifecycle = ApplicationLifecycle()
        let panel = SystemMemoryPanel(operations: MenuCheckPanelOperations(), lifecycle: lifecycle)
        let finder = FinderExtensionController(configurationStore: { FinderConfigurationStore(directory: directory) })
        for updates in [unconfigured, disabled] {
            let settings = ApplicationSettingsViewController(
                memoryPanel: panel, finder: finder, updates: updates, lifecycle: lifecycle)
            settings.view.setFrameSize(NSSize(width: 400, height: 450))
            settings.selectCategory(.about)
            settings.view.layoutSubtreeIfNeeded()
            let views = descendants(of: settings.view)
            let labels = views.compactMap { ($0 as? NSTextField)?.stringValue }
            let checks = views.compactMap { $0 as? NSButton }.filter { $0.title == localized("update.check") }
            precondition(checks.count == 1 && !checks[0].isEnabled)
            precondition(
                labels.contains(localized("update.unconfigured")) == (updates.status != nil),
                "About must explain update configuration errors without adding a Debug-mode message")
        }
    }

    @MainActor private static func verifyFinderSaveFailure(in directory: URL) async throws {
        let store = FinderConfigurationStore(directory: directory)
        try store.save(.initial)
        let finder = FinderExtensionController(configurationStore: { store })
        await finder.refresh()
        let beforeFailure = try store.load()
        precondition(beforeFailure == FinderConfiguration(language: Bundle.main.preferredLocalizations.first))
        precondition(finder.configuration == beforeFailure)
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
        precondition(saved == beforeFailure && finder.configuration == beforeFailure)
        if case .failed = finder.state {
            preconditionFailure("A configuration write error must not replace the extension registration state")
        }
        await finder.refresh()
        precondition(finder.configuration == saved)
    }

    @MainActor private static func verifyMoveKeyIsolation(in directory: URL) async throws {
        let store = FinderConfigurationStore(directory: directory)
        try store.save(FinderConfiguration(airDropEnabled: true, copyPathEnabled: true, moveEnabled: true))
        let keyFile = directory.appendingPathComponent("move-request.key")
        try Data().write(to: keyFile)
        let finder = FinderExtensionController(configurationStore: { store })
        await finder.refresh()
        precondition(finder.configuration != nil, "A damaged move key must not discard menu configuration")
        precondition(finder.moveAuthorizationError != nil)
        if case .failed = finder.state { preconditionFailure("A move key failure must not replace extension state") }
        try finder.setEnabled(false, for: .copyPath)
        try finder.setEnabled(false, for: .airDrop)
        try finder.setEnabled(false, for: .move)
        let disabled = try store.load()
        precondition(!disabled.moveEnabled && !disabled.copyPathEnabled && !disabled.airDropEnabled)
        precondition(finder.moveAuthorizationError == nil)
        do {
            try finder.setEnabled(true, for: .move)
            preconditionFailure("A damaged key must still prevent enabling moves")
        } catch CocoaError.fileReadCorruptFile {}
        let afterFailure = try store.load()
        precondition(afterFailure == disabled && finder.configuration == disabled)
        try finder.setEnabled(true, for: .terminal)
        await finder.restoreConfiguration()
        let restored = try store.load()
        precondition(!restored.terminalEnabled && !restored.moveEnabled)
        precondition(finder.configuration != nil, "Restoring menu defaults must not depend on the move key")
        precondition(finder.moveAuthorizationError == nil)
        // Missing keys are prepared when moving is enabled; unrelated switches must not create one.
        try FileManager.default.removeItem(at: keyFile)
        try finder.setEnabled(true, for: .terminal)
        precondition(!FileManager.default.fileExists(atPath: keyFile.path))
        try finder.setEnabled(true, for: .move)
        _ = try store.loadMoveKey()
    }

    @MainActor private static func verifyOnboardingFailureRouting(in directory: URL) async throws {
        let store = FinderConfigurationStore(directory: directory)
        try store.save(.initial)
        let finder = FinderExtensionController(configurationStore: { store })
        await finder.refresh()
        let lifecycle = ApplicationLifecycle()
        let panel = SystemMemoryPanel(operations: MenuCheckPanelOperations(), lifecycle: lifecycle)
        var errorWindows: [NSWindow?] = []
        let settings = ApplicationSettingsViewController(
            memoryPanel: panel, finder: finder, updates: ApplicationUpdateController(), lifecycle: lifecycle,
            presentError: { _, window in errorWindows.append(window) })
        let settingsHost = NSWindow(contentViewController: settings)
        let guide = OnboardingWindowController(
            lifecycle: lifecycle, rows: { settings.onboardingRows(for: $0) },
            didChangeStep: { _ in }, didDismiss: {}, didComplete: {})
        guide.advance()
        guide.advance()
        guard let guideContent = guide.window?.contentView,
            let control = descendants(of: guideContent).compactMap({ $0 as? NSSwitch }).first
        else { preconditionFailure("The guide must expose the saved Finder configuration") }
        precondition(control.window === guide.window && settings.view.window === settingsHost)
        // Rendering can detach the sender before an error is presented.
        settings.onChange = { control.removeFromSuperview() }
        try Data("invalid json".utf8).write(to: directory.appendingPathComponent("menus.json"))
        control.state = .on
        control.sendAction(control.action, to: control.target)
        precondition(control.window == nil)
        precondition(
            errorWindows.count == 1 && errorWindows[0] === guide.window,
            "Save failures must remain attached to their originating guide, even after refresh")
        await finder.refresh()
        let invalidViews = settings.onboardingRows(for: .finder).flatMap { [$0] + descendants(of: $0) }
        precondition(
            invalidViews.compactMap { $0 as? NSButton }.contains {
                $0.action == NSSelectorFromString("restoreFinder:")
            }, "A damaged configuration must expose the existing restore action on the feature page")
        precondition(
            invalidViews.compactMap { ($0 as? NSTextField)?.stringValue }.contains {
                $0.contains(localized("finder.configuration.invalid"))
            }, "An unavailable configuration must explain why feature switches cannot be shown")
        await finder.restoreConfiguration()
        let restoredViews = settings.onboardingRows(for: .finder).flatMap { [$0] + descendants(of: $0) }
        precondition(restoredViews.compactMap { $0 as? NSSwitch }.count == FinderAction.allCases.count)
        let unreadableFinder = FinderExtensionController(configurationStore: { throw CocoaError(.fileReadNoPermission) }
        )
        await unreadableFinder.refresh()
        let unreadableSettings = ApplicationSettingsViewController(
            memoryPanel: panel, finder: unreadableFinder, updates: ApplicationUpdateController(), lifecycle: lifecycle)
        let failedViews = unreadableSettings.onboardingRows(for: .finder).flatMap { [$0] + descendants(of: $0) }
        precondition(
            failedViews.compactMap { $0 as? NSButton }.contains {
                $0.action == NSSelectorFromString("checkFinder")
            }, "Read failures must expose the existing retry action")
    }

    @MainActor private static func verifyOnboardingTerminationRecovery() {
        let lifecycle = ApplicationLifecycle()
        var dismissals = 0
        let guide = OnboardingWindowController(
            lifecycle: lifecycle, rows: { _ in [] },
            didChangeStep: { _ in }, didDismiss: { dismissals += 1 }, didComplete: {})
        let window = MenuCheckOnboardingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = guide.window?.contentView
        guide.window = window
        window.delegate = guide
        guide.advance()
        guide.advance()
        window.makeKeyAndOrderFront(nil)
        guide.suspendForTermination()
        precondition(!window.isVisible && dismissals == 0)
        precondition(lifecycle.requestTermination())
        guide.suspendForTermination()
        guide.resumeAfterCancelledTermination()
        precondition(!window.isVisible, "A pending quit must never reopen the guide")
        lifecycle.cancelTermination()
        guide.resumeAfterCancelledTermination()
        precondition(
            window.isVisible && guide.step == .finder && dismissals == 0,
            "Canceling quit must restore the existing window and step without dismissing setup")
        window.orderOut(nil)
        guide.suspendForTermination()
        precondition(lifecycle.requestTermination())
        lifecycle.cancelTermination()
        guide.resumeAfterCancelledTermination()
        precondition(!window.isVisible, "Canceling quit must not open a guide that was already hidden")
    }

    @MainActor private static func verifySettingsRows(
        finder: FinderExtensionController
    ) async {
        precondition(
            ApplicationSettingsViewController.Category.allCases == [.general, .permissions, .mouseReset, .about])
        let lifecycle = ApplicationLifecycle()
        let operations = MenuCheckPanelOperations()
        let panel = SystemMemoryPanel(operations: operations, lifecycle: lifecycle)
        await panel.refreshPermissions()
        let suite = "Buckle.MouseResetMenuTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("Missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = MouseResetPreferences(defaults: defaults)
        let finderAnswer = MenuCheckFinderPermission()
        let finderAutomation = FinderAutomationPermission(query: { request in
            finderAnswer.requests.append(request)
            return finderAnswer.granted
        })
        await finderAutomation.refresh()
        let settings = ApplicationSettingsViewController(
            memoryPanel: panel, finder: finder,
            updates: ApplicationUpdateController(), lifecycle: lifecycle,
            finderAutomation: finderAutomation, mouseResetPreferences: preferences)
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
        precondition(switches.count == 3)
        for control in switches {
            guard let row = control.superview as? NSStackView else {
                preconditionFailure("A switch must belong to a settings row")
            }
            precondition(
                row.arrangedSubviews.count == 3, "Settings rows need a flexible spacer between label and switch")
            precondition(
                abs(control.frame.maxX - row.bounds.maxX) < 0.5, "Settings switches must align to the trailing edge")
        }
        await finder.refresh()
        let finderRows = settings.onboardingRows(for: .finder)
        let finderViews = finderRows.flatMap { [$0] + descendants(of: $0) }
        precondition(finderViews.compactMap { $0 as? NSSwitch }.count == FinderAction.allCases.count)
        for control in finderViews.compactMap({ $0 as? NSSwitch }) {
            guard let identifier = control.identifier, let action = FinderAction(rawValue: identifier.rawValue) else {
                preconditionFailure("Each guide switch must identify its existing Finder action")
            }
            let wasEnabled = finder.configuration?.isEnabled(action) == true
            control.state = wasEnabled ? .off : .on
            control.sendAction(control.action, to: control.target)
            await finder.refresh()
            precondition(
                finder.configuration?.isEnabled(action) == !wasEnabled,
                "Guide switches must persist through the existing Finder configuration service")
            control.state = wasEnabled ? .on : .off
            control.sendAction(control.action, to: control.target)
        }

        precondition(
            !finderViews.compactMap { ($0 as? NSTextField)?.stringValue }.contains(
                localized("permissions.finderAutomation.title")),
            "Feature switches must remain separate from permission controls")
        let permissionViews = settings.onboardingRows(for: .permissions).flatMap { [$0] + descendants(of: $0) }
        let permissionTitles = permissionViews.compactMap { ($0 as? NSTextField)?.stringValue }
        precondition(permissionTitles.contains(localized("permissions.finderAutomation.title")))
        precondition(
            permissionTitles.contains(localized("permissions.systemEvents.title")),
            "All permissions must be available before selecting features")
        precondition(
            permissionViews.compactMap { $0 as? NSSwitch }.isEmpty,
            "Permissions must be separate from feature switches")
        settings.selectCategory(.permissions)
        let settingsPermissionButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        for control in permissionViews.compactMap({ $0 as? NSButton }) {
            precondition(
                control.target === settings,
                "Guide permissions must use the existing settings controller")
            precondition(
                settingsPermissionButtons.contains { $0.action == control.action },
                "Guide permissions must use the same authorization and extension actions as Settings")
        }
        let preferenceViews = settings.onboardingRows(for: .preferences).flatMap { [$0] + descendants(of: $0) }
        precondition(preferenceViews.compactMap { $0 as? NSSwitch }.count == 2)
        for control in preferenceViews.compactMap({ $0 as? NSSwitch }) {
            precondition(
                control.target === settings && switches.contains { $0.action == control.action },
                "Startup and updates must reuse the Settings actions without a separate preference store")
        }

        precondition(
            preferenceViews.compactMap { ($0 as? NSTextField)?.stringValue }.contains(
                localized("onboarding.updates.disabled")))
        let guideLifecycle = ApplicationLifecycle()
        var steps: [OnboardingStep] = []
        var completedGuides = 0
        var guideClosed = false
        let guide = OnboardingWindowController(
            lifecycle: guideLifecycle, rows: { settings.onboardingRows(for: $0) },
            didChangeStep: { steps.append($0) }, didDismiss: { guideClosed = true },
            didComplete: {
                precondition(guideClosed, "The guide must close before the menu-opening callback runs")
                completedGuides += 1
            })
        precondition(guide.step == .welcome)
        guide.advance()
        precondition(guide.step == .permissions && steps == [.permissions])
        guard let guideContent = guide.window?.contentView else {
            preconditionFailure("The guide must have a content view")
        }
        guideContent.layoutSubtreeIfNeeded()
        let navigation = descendants(of: guideContent).compactMap { $0 as? NSButton }.filter {
            $0.identifier?.rawValue.hasPrefix("onboarding.") == true
        }
        precondition(navigation.count == 2, "Only back and forward belong in guide navigation")
        guard let back = navigation.first(where: { $0.identifier?.rawValue == "onboarding.back" }),
            let next = navigation.first(where: { $0.identifier?.rawValue == "onboarding.next" })
        else {
            preconditionFailure("The guide needs both navigation buttons")
        }
        precondition(back.frame.maxX < next.frame.minX, "Back must be left of forward")
        precondition(
            next.keyEquivalent == "\r" && back.keyEquivalent.isEmpty,
            "Continue must be the primary action")
        precondition(abs(next.frame.width - 52) < 0.5 && abs(next.frame.height - 52) < 0.5)
        precondition(
            abs(back.frame.width - 40) < 0.5 && abs(back.frame.height - 40) < 0.5,
            "Both navigation buttons must be circular, with Continue more prominent")
        precondition(next.frame.minX - back.frame.maxX < 30, "Navigation controls must stay grouped")
        back.performClick(nil)
        precondition(guide.step == .welcome)
        guide.advance()
        guide.advance()
        guide.advance()
        precondition(
            guide.step == .preferences && steps == [.permissions, .welcome, .permissions, .finder, .preferences])
        guide.advance()
        precondition(guide.step == .complete && completedGuides == 0)
        precondition(guide.window?.attachedSheet == nil, "Completion belongs inside the guide")
        guide.advance()
        precondition(completedGuides == 1, "Start Using Buckle must open the menu once")
        precondition(guideLifecycle.requestTermination())
        guide.advance()
        precondition(completedGuides == 1, "Quitting must prevent opening the menu")
        settings.selectCategory(.mouseReset)
        guard let wait = descendants(of: settings.view).compactMap({ $0 as? NSStepper }).first else {
            preconditionFailure("Mouse reset settings must expose a service wait control")
        }
        precondition(wait.integerValue == 3 && wait.minValue == 0 && wait.maxValue == 60 && !wait.valueWraps)
        wait.integerValue = 7
        wait.sendAction(wait.action, to: wait.target)
        do {
            let savedWait = try preferences.loadServiceWaitSeconds()
            precondition(savedWait == 7)
        } catch { preconditionFailure("\(error)") }
        let mouseButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(mouseButtons.contains { $0.identifier?.rawValue == "mouse-reset.add" })
        let removals = mouseButtons.filter { $0.action == NSSelectorFromString("removeMouseResetApplication:") }
        precondition(removals.count == MouseResetTool.defaults.count)
        guard let remove = removals.first else { preconditionFailure("Missing application removal") }
        remove.performClick(nil)
        do {
            let saved = try preferences.load()
            precondition(saved == Array(MouseResetTool.defaults.dropFirst()))
        } catch { preconditionFailure("\(error)") }
        precondition(lifecycle.begin(.mouseReset))
        settings.refresh()
        let busyButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(busyButtons.allSatisfy { !$0.isEnabled })
        let busyWaits = descendants(of: settings.view).compactMap { $0 as? NSStepper }
        precondition(busyWaits.count == 1 && busyWaits.allSatisfy { !$0.isEnabled })
        lifecycle.end(.mouseReset)
        settings.selectCategory(.permissions)
        let permissionButtons = descendants(of: settings.view).compactMap { $0 as? NSButton }
        precondition(!permissionButtons.contains { $0.action == NSSelectorFromString("checkPermissions") })
        var grantedLabels = descendants(of: settings.view).compactMap { $0 as? NSTextField }
            .filter { $0.textColor == .systemGreen }
        precondition(grantedLabels.count == 2, "Granted permissions must use green status labels")
        precondition(grantedLabels.allSatisfy { !$0.stringValue.isEmpty })
        precondition(
            permissionButtons.contains { $0.action == NSSelectorFromString("openFinderAutomation:") },
            "Denied Finder automation needs its own grant action even when System Events is authorized")
        finderAnswer.granted = true
        await finderAutomation.refresh()
        settings.refresh()
        precondition(
            descendants(of: settings.view).compactMap { $0 as? NSTextField }
                .filter { $0.textColor == .systemGreen }.count == 3)
        finderAnswer.granted = false
        await finderAutomation.refresh()
        settings.refresh()

        let checks = operations.requests.count
        let finderChecks = finderAnswer.requests.count
        settings.refreshPermissionStatus()
        while operations.requests.count == checks { await Task.yield() }
        while panel.isCheckingPermissions { await Task.yield() }
        while finderAnswer.requests.count == finderChecks { await Task.yield() }
        while finderAutomation.state == .checking { await Task.yield() }
        precondition(finderAutomation.state == .required)
        precondition(finderAnswer.requests.allSatisfy { !$0 }, "Silent Finder checks requested consent")
        precondition(operations.requests.allSatisfy { !$0 }, "Automatic checks must not request authorization")
        // Finder error prompts must reuse the Settings authorization actions, even on another category.
        finderAnswer.granted = true
        let finderRequests = finderAnswer.requests.count
        settings.requestPermission(.automation(.finder), from: NSView())
        while finderAnswer.requests.count == finderRequests { await Task.yield() }
        while lifecycle.isActive(.finderPermissions) { await Task.yield() }
        precondition(finderAnswer.requests.last == true)
        precondition(finderAutomation.state == .granted)
        let automationRequests = operations.requests.count
        settings.requestPermission(.automation(.systemEvents), from: NSView())
        while operations.requests.count == automationRequests { await Task.yield() }
        while panel.isCheckingPermissions { await Task.yield() }
        precondition(operations.requests.last == true)
        finderAnswer.granted = false
        await finderAutomation.refresh()
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
    var suspends = false
    var continuation: CheckedContinuation<Void, Never>?

    func debugValue() -> CFPropertyList? { nil }
    func setDebugValue(_ value: CFPropertyList?) throws {
        preconditionFailure("Settings checks must not change system preferences")
    }
    func trigger() async throws { preconditionFailure("Settings checks must not open system windows") }
    func permissions(requestPermission: Bool) async throws -> MemoryPanelPermissions {
        requests.append(requestPermission)
        if suspends { await withCheckedContinuation { continuation = $0 } }
        return MemoryPanelPermissions(accessibilityGranted: accessibilityGranted, automationGranted: true)
    }
}

@MainActor
private final class MenuCheckFinderPermission {
    var granted = false
    var requests: [Bool] = []
}

@MainActor private final class MenuCheckOnboardingWindow: NSWindow {
    private var visibleForCheck = false
    override var isVisible: Bool { visibleForCheck }
    override func makeKeyAndOrderFront(_ sender: Any?) { visibleForCheck = true }
    override func orderFront(_ sender: Any?) { visibleForCheck = true }
    override func orderOut(_ sender: Any?) { visibleForCheck = false }
}
