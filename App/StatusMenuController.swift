import AppKit

@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let memoryPanel: SystemMemoryPanel
    private let mouseReset: MouseResetController
    private let menuBarRestart: MenuBarRestartController
    private let finder: FinderExtensionController
    private let lifecycle: ApplicationLifecycle
    private let openMemory: () -> Void
    private let openSettings: (ApplicationSettingsViewController.Category?) -> Void
    private let resetMouse: () -> Void
    private var actionTargets: [StatusMenuActionTarget] = []
    private(set) var statusItem: NSStatusItem?

    init(
        memoryPanel: SystemMemoryPanel, mouseReset: MouseResetController,
        menuBarRestart: MenuBarRestartController, finder: FinderExtensionController,
        lifecycle: ApplicationLifecycle,
        openMemory: @escaping () -> Void,
        openSettings: @escaping (ApplicationSettingsViewController.Category?) -> Void,
        resetMouse: @escaping () -> Void
    ) {
        self.memoryPanel = memoryPanel
        self.mouseReset = mouseReset
        self.menuBarRestart = menuBarRestart
        self.finder = finder
        self.lifecycle = lifecycle
        self.openMemory = openMemory
        self.openSettings = openSettings
        self.resetMouse = resetMouse
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(title: localized("tools"))
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateStatusImage()
    }

    func updateStatusImage() {
        guard let button = statusItem?.button else { return }
        let label = mouseReset.accessibilityLabel
        let image: NSImage?
        if mouseReset.isPresented {
            image = NSImage(systemSymbolName: mouseReset.symbol, accessibilityDescription: label)
        } else {
            guard let logo = NSImage(named: "MenuBarIconTemplate") else {
                preconditionFailure("The application bundle must contain the menu-bar logo")
            }
            logo.size = NSSize(width: 18, height: 18)
            image = logo
        }
        image?.isTemplate = true
        button.image = image
        button.toolTip = localized("memory.menu.help")
        button.setAccessibilityLabel(label)
        if mouseReset.isPresented && !mouseReset.isRunning {
            NSAccessibility.post(
                element: button, notification: .announcementRequested,
                userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        actionTargets.removeAll(keepingCapacity: true)
        menu.autoenablesItems = false
        let acceptingWork = !lifecycle.terminationRequested
        menu.addItem(.sectionHeader(title: localized("menu.system")))
        menu.addItem(
            action(
                localized("memory.open.system"), symbol: "macwindow", enabled: acceptingWork && !memoryPanel.isOpening
            ) {
                $0.openMemory()
            })
        menu.addItem(
            action(
                mouseReset.isPresented ? localized("mouse.show.progress") : localized("mouse.reset"),
                symbol: "computermouse", enabled: acceptingWork
            ) { $0.resetMouse() })
        menu.addItem(
            action(
                menuBarRestart.isRunning ? localized("menubar.restart.running") : localized("menubar.restart"),
                symbol: "menubar.rectangle", enabled: acceptingWork && !menuBarRestart.isRunning
            ) { owner in
                Task {
                    await owner.menuBarRestart.run()
                    if !owner.lifecycle.terminationRequested, let error = owner.menuBarRestart.error {
                        owner.showErrorMessage(error)
                    }
                }
            })
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: localized("menu.applications")))
        menu.addItem(browserMenu(enabled: acceptingWork))
        menu.addItem(.separator())
        addFinderToggles(to: menu, enabled: acceptingWork)
        menu.addItem(.separator())
        menu.addItem(
            action(localized("settings.title"), symbol: "gearshape", key: ",") {
                $0.openSettings(nil)
            })
        menu.addItem(action(localized("buckle.quit"), symbol: "power", key: "q") { _ in NSApp.terminate(nil) })
        addFinderNotice(to: menu)
        Task { await finder.refresh() }
    }

    private func addFinderToggles(to menu: NSMenu, enabled: Bool) {
        menu.addItem(.sectionHeader(title: localized("settings.finder.actions")))
        for finderAction in FinderAction.allCases {
            let title: String
            switch finderAction {
            case .airDrop: title = localized("finder.airdrop.toggle")
            case .terminal: title = localized("finder.terminal.toggle")
            case .copyPath: title = localized("finder.copyPath.toggle")
            case .move: title = localized("finder.move.toggle")
            }
            let item = action(title, enabled: enabled && finder.configuration != nil) { owner in
                guard !owner.lifecycle.terminationRequested, let configuration = owner.finder.configuration else {
                    return
                }
                do {
                    try owner.finder.setEnabled(!configuration.isEnabled(finderAction), for: finderAction)
                } catch {
                    NSApp.activate()
                    NSAlert(error: error).runModal()
                }
            }
            item.identifier = NSUserInterfaceItemIdentifier(finderAction.rawValue)
            item.state = finder.configuration.map { $0.isEnabled(finderAction) ? .on : .off } ?? .mixed
            menu.addItem(item)
        }
    }

    private func browserMenu(enabled: Bool) -> NSMenuItem {
        let item = NSMenuItem(title: localized("browser.launch"), action: nil, keyEquivalent: "")
        item.image = image("globe", title: item.title)
        let submenu = NSMenu(title: item.title)
        submenu.autoenablesItems = false
        let browsers = BrowserLauncher.installed()
        if browsers.isEmpty {
            let empty = NSMenuItem(title: localized("browser.none"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        for browser in browsers {
            let browserItem = NSMenuItem(title: browser.name, action: nil, keyEquivalent: "")
            let languages = NSMenu(title: browser.name)
            languages.autoenablesItems = false
            for language in BrowserLanguage.allCases {
                languages.addItem(
                    action(language.name, enabled: enabled) { owner in
                        Task {
                            guard !owner.lifecycle.terminationRequested else { return }
                            do { try await BrowserLauncher.launch(browser, language: language) } catch {
                                guard owner.lifecycle.shouldPresentUserActionError(error) else { return }
                                NSApp.activate()
                                NSAlert(error: error).runModal()
                            }
                        }
                    })
            }
            browserItem.submenu = languages
            submenu.addItem(browserItem)
        }
        item.submenu = submenu
        return item
    }

    private func addFinderNotice(to menu: NSMenu) {
        let title: String
        switch finder.state {
        case .enabled: return
        case .checking: title = localized("finder.checking")
        case .missing: title = localized("finder.missing")
        case .unregistered: title = localized("finder.unregistered")
        case .disabled: title = localized("finder.disabled")
        case .invalidConfiguration: title = localized("finder.configuration.invalid")
        case .failed: title = localized("finder.operation.failed")
        }
        menu.addItem(.separator())
        let notice = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        notice.isEnabled = false
        menu.addItem(notice)
    }

    private func action(
        _ title: String, symbol: String? = nil, key: String = "", enabled: Bool = true,
        perform: @escaping (StatusMenuController) -> Void
    ) -> NSMenuItem {
        let target = StatusMenuActionTarget(owner: self, perform: perform)
        actionTargets.append(target)
        let item = NSMenuItem(
            title: title, action: #selector(StatusMenuActionTarget.performAction(_:)), keyEquivalent: key)
        item.target = target
        item.isEnabled = enabled
        if let symbol { item.image = image(symbol, title: title) }
        return item
    }

    private func image(_ symbol: String, title: String) -> NSImage? {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        image?.isTemplate = true
        return image
    }

    private func showErrorMessage(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = localized("menubar.restart")
        alert.informativeText = message
        alert.runModal()
    }
}

@MainActor
private final class StatusMenuActionTarget: NSObject {
    private weak var owner: StatusMenuController?
    private let perform: (StatusMenuController) -> Void

    init(owner: StatusMenuController, perform: @escaping (StatusMenuController) -> Void) {
        self.owner = owner
        self.perform = perform
    }

    @objc func performAction(_ sender: NSMenuItem) {
        if let owner { perform(owner) }
    }
}
