import AppKit
import BucklePermissionSupport
import Observation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class ApplicationSettingsViewController: NSViewController {
    enum Category: Int, CaseIterable {
        case general, mouseReset, permissions, about

        var title: String {
            switch self {
            case .general: localized("settings.general")
            case .mouseReset: localized("mouse.settings.title")
            case .permissions: localized("settings.permissions")
            case .about: localized("settings.about")
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .mouseReset: "computermouse"
            case .permissions: "hand.raised"
            case .about: "info.circle"
            }
        }

        var toolbarItemIdentifier: NSToolbarItem.Identifier {
            NSToolbarItem.Identifier("application-settings.\(rawValue)")
        }
    }

    private let lifecycle: ApplicationLifecycle
    private let memoryPanel: SystemMemoryPanel
    private let finder: FinderExtensionController
    private let languagePreferences: ApplicationLanguagePreferences
    private let mouseResetPreferences: MouseResetPreferences
    private let updates: ApplicationUpdateController
    private let permissionGuidance: PermissionGuidance
    private let contentStack = NSStackView()
    private let mouseResetWaitLabel = NSTextField(labelWithString: "")
    private var loginStatus = SMAppService.mainApp.status
    private(set) var selectedCategory = Category.general

    init(
        memoryPanel: SystemMemoryPanel, finder: FinderExtensionController,
        updates: ApplicationUpdateController, lifecycle: ApplicationLifecycle,
        languagePreferences: ApplicationLanguagePreferences = ApplicationLanguagePreferences(),
        permissionGuidance: PermissionGuidance = PermissionGuidance(),
        mouseResetPreferences: MouseResetPreferences = MouseResetPreferences()
    ) {
        self.lifecycle = lifecycle
        self.memoryPanel = memoryPanel
        self.finder = finder
        self.updates = updates
        self.languagePreferences = languagePreferences
        self.mouseResetPreferences = mouseResetPreferences
        self.permissionGuidance = permissionGuidance
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(separator)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)
        let document = SettingsDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        contentStack.orientation = .vertical
        contentStack.alignment = .width
        contentStack.distribution = .fill
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(contentStack)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            separator.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            contentStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -20),
            contentStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
            contentStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
        ])
        view = root
        refresh()
        observeState()
    }

    func selectCategory(_ category: Category) {
        selectedCategory = category
        if isViewLoaded { showCategory() }
    }

    func refresh() {
        loginStatus = SMAppService.mainApp.status
        showCategory()
    }

    private func observeState() {
        withObservationTracking {
            _ = lifecycle.terminationRequested
            _ = lifecycle.isActive(.mouseReset)
            _ = memoryPanel.permissionStatus
            _ = memoryPanel.error
            _ = memoryPanel.isOpening
            _ = memoryPanel.isCheckingPermissions
            _ = memoryPanel.automationGranted
            _ = finder.state
            _ = finder.isBusy
            _ = updates.canCheck
            _ = updates.automaticChecks
            _ = updates.state
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refresh()
                self.observeState()
            }
        }
    }

    private func showCategory() {
        for item in contentStack.arrangedSubviews {
            contentStack.removeArrangedSubview(item)
            item.removeFromSuperview()
        }
        switch selectedCategory {
        case .general: showGeneral()
        case .mouseReset: showMouseReset()
        case .permissions: showPermissions()
        case .about: showAbout()
        }
    }

    private func showMouseReset() {
        addDescription(localized("mouse.settings.help"))
        do {
            let tools = try mouseResetPreferences.load()
            let editable = !lifecycle.terminationRequested && !lifecycle.isActive(.mouseReset)
            let waitSeconds = try mouseResetPreferences.loadServiceWaitSeconds()
            let wait = NSStepper()
            wait.minValue = Double(MouseResetPreferences.serviceWaitRange.lowerBound)
            wait.maxValue = Double(MouseResetPreferences.serviceWaitRange.upperBound)
            wait.increment = 1
            wait.valueWraps = false
            wait.integerValue = waitSeconds
            wait.target = self
            wait.action = #selector(changeMouseResetWait(_:))
            wait.identifier = NSUserInterfaceItemIdentifier("mouse-reset.service-wait")
            wait.setAccessibilityLabel(localized("mouse.settings.wait"))
            wait.isEnabled = editable
            mouseResetWaitLabel.stringValue = localizedFormat("mouse.settings.wait.seconds", String(waitSeconds))
            let waitControl = NSStackView(views: [mouseResetWaitLabel, wait])
            waitControl.orientation = .horizontal
            waitControl.alignment = .centerY
            waitControl.spacing = 8
            addSection(
                localized("mouse.settings.timing"),
                rows: [
                    settingRow(localized("mouse.settings.wait"), control: waitControl),
                    description(localized("mouse.settings.wait.help")),
                ])
            let add = NSButton(
                title: localized("mouse.settings.add"), target: self, action: #selector(addMouseResetApplications))
            add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
            add.imagePosition = .imageLeading
            add.bezelStyle = .rounded
            add.bezelColor = .controlAccentColor
            add.isEnabled = editable
            add.identifier = NSUserInterfaceItemIdentifier("mouse-reset.add")
            let rows: [NSView] =
                tools.isEmpty
                ? [description(localized("mouse.settings.empty"))]
                : tools.map { mouseResetRow($0, editable: editable) }
            addSection(localized("mouse.settings.applications"), rows: rows, accessory: add)
        } catch {
            addDescription(error.localizedDescription)
        }
    }

    @objc private func changeMouseResetWait(_ sender: NSStepper) {
        guard !lifecycle.terminationRequested, !lifecycle.isActive(.mouseReset) else { return }
        do {
            try mouseResetPreferences.saveServiceWaitSeconds(sender.integerValue)
            mouseResetWaitLabel.stringValue = localizedFormat(
                "mouse.settings.wait.seconds", String(sender.integerValue))
        } catch { present(error) }
    }

    private func mouseResetRow(_ tool: MouseResetTool, editable: Bool) -> NSView {
        let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: tool.identifier)
        let image = NSImageView()
        if let applicationURL {
            image.image = NSWorkspace.shared.icon(forFile: applicationURL.path)
        } else {
            image.image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        }
        image.imageScaling = .scaleProportionallyUpOrDown
        image.setAccessibilityElement(false)
        image.widthAnchor.constraint(equalToConstant: 24).isActive = true
        image.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let name = NSTextField(labelWithString: tool.name)
        name.lineBreakMode = .byTruncatingMiddle
        name.toolTip = applicationURL?.path ?? tool.identifier
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let remove = NSButton()
        remove.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        remove.imagePosition = .imageOnly
        remove.isBordered = false
        remove.contentTintColor = .systemRed
        remove.target = self
        remove.action = #selector(removeMouseResetApplication(_:))
        remove.identifier = NSUserInterfaceItemIdentifier(tool.identifier)
        remove.toolTip = localizedFormat("mouse.settings.remove", tool.name)
        remove.setAccessibilityLabel(remove.toolTip)
        remove.isEnabled = editable
        remove.widthAnchor.constraint(equalToConstant: 28).isActive = true
        remove.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let row = NSStackView(views: [image, name, spacer, remove])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    @objc private func addMouseResetApplications() {
        guard !lifecycle.terminationRequested, !lifecycle.isActive(.mouseReset), let window = view.window else {
            return
        }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = true
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.prompt = localized("mouse.settings.add")
        picker.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK,
                !self.lifecycle.terminationRequested, !self.lifecycle.isActive(.mouseReset)
            else { return }
            do {
                let selected: [MouseResetTool]
                do { selected = try picker.urls.map { try MouseResetTool(applicationURL: $0) } } catch {
                    throw CocoaError(
                        .fileReadCorruptFile,
                        userInfo: [NSLocalizedDescriptionKey: localized("mouse.settings.invalid")])
                }
                var tools = try self.mouseResetPreferences.load()
                for tool in selected where !tools.contains(where: { $0.identifier == tool.identifier }) {
                    tools.append(tool)
                }
                try self.mouseResetPreferences.save(tools)
                self.refresh()
            } catch { self.present(error) }
        }
    }

    @objc private func removeMouseResetApplication(_ sender: NSButton) {
        guard !lifecycle.terminationRequested, !lifecycle.isActive(.mouseReset), let identifier = sender.identifier
        else {
            return
        }
        do {
            let tools = try mouseResetPreferences.load().filter { $0.identifier != identifier.rawValue }
            try mouseResetPreferences.save(tools)
            refresh()
        } catch { present(error) }
    }

    private func showGeneral() {
        let languages = NSPopUpButton()
        languages.identifier = NSUserInterfaceItemIdentifier("application-settings.language")
        languages.target = self
        languages.action = #selector(changeLanguage(_:))
        for language in ApplicationLanguage.allCases {
            languages.addItem(withTitle: language == .system ? localized("language.system") : language.nativeName)
            languages.lastItem?.representedObject = language.rawValue
            if language == languagePreferences.selection { languages.select(languages.lastItem) }
        }
        languages.setAccessibilityLabel(localized("language.label"))
        addSection(localized("settings.language"), rows: [settingRow(localized("language.label"), control: languages)])
        addDescription(localized("language.restart.help"))
        addSection(
            localized("settings.startup"),
            rows: [
                settingRow(
                    localized("login.launch"),
                    control: toggle(
                        localized("login.launch"), enabled: loginStatus == .enabled || loginStatus == .requiresApproval,
                        action: #selector(changeLaunchAtLogin(_:))))
            ])
        if loginStatus == .requiresApproval {
            contentStack.addArrangedSubview(button(localized("login.approve"), action: #selector(approveLogin)))
        }
        addSection(
            localized("settings.updates"),
            rows: [
                settingRow(
                    localized("update.automatic"),
                    control: toggle(
                        localized("update.automatic"), enabled: updates.automaticChecks,
                        action: #selector(changeAutomaticUpdates(_:)), available: updates.isAvailable))
            ])
        if let status = updates.status { addDescription(status) }
    }

    private func showPermissions() {
        let accessibilityStatus: PermissionGuidance.Status
        let automationStatus: PermissionGuidance.Status
        switch memoryPanel.permissionStatus {
        case .unchecked:
            accessibilityStatus = .checking
            automationStatus = .checking
        case .granted:
            accessibilityStatus = .granted
            automationStatus = .granted
        case .required(.accessibility):
            accessibilityStatus = .notGranted
            automationStatus = .unknown
        case .required(.automation):
            accessibilityStatus = .granted
            automationStatus = .notGranted
        case .failed:
            accessibilityStatus = .unknown
            automationStatus = .unknown
        }
        let automationState =
            memoryPanel.automationGranted.map {
                $0 ? PermissionGuidance.Status.granted : .notGranted
            } ?? automationStatus
        addSection(
            localized("settings.permissions"),
            rows: [
                settingRow(
                    permissionGuidance.accessibilityTitle,
                    control: permissionControl(status: accessibilityStatus, action: #selector(openAccessibility(_:)))),
                settingRow(
                    localized("permissions.automation.title"),
                    control: permissionControl(status: automationState, action: #selector(openAutomation))),
                settingRow(localized("settings.finder.actions"), control: finderPermissionControl()),
            ])
        if let error = memoryPanel.error ?? memoryPanel.permissionError { addDescription(error) }
        switch finder.state {
        case .missing: addDescription(localized("finder.install.help"))
        case .invalidConfiguration(let message):
            addDescription(localized("finder.configuration.invalid") + "\n" + message)
        case .failed(let message): addDescription(message)
        case .checking, .enabled, .disabled, .unregistered: break
        }
    }

    private func permissionControl(status: PermissionGuidance.Status, action: Selector) -> NSView {
        let control = button("", action: action)
        permissionGuidance.configure(control, status: status)
        if case .granted = status { return grantedStatus(control.title) }
        control.isEnabled =
            !lifecycle.terminationRequested && !memoryPanel.isOpening && !memoryPanel.isCheckingPermissions
        if case .checking = status { control.isEnabled = false }
        return control
    }

    private func finderPermissionControl() -> NSView {
        let control: NSButton
        switch finder.state {
        case .enabled: return grantedStatus(localized("finder.enabled"))
        case .checking:
            control = button("", action: #selector(enableFinder))
            permissionGuidance.configure(control, status: .checking)
            control.isEnabled = false
            return control
        case .missing: control = button(localized("finder.show.app"), action: #selector(showApplication))
        case .unregistered, .disabled:
            control = button(localized("finder.enable"), action: #selector(enableFinder))
        case .invalidConfiguration:
            control = button(localized("finder.configuration.restore"), action: #selector(restoreFinder))
        case .failed: control = button(localized("finder.retry"), action: #selector(checkFinder))
        }
        control.isEnabled = !finder.isBusy && !lifecycle.terminationRequested
        return control
    }

    private func grantedStatus(_ title: String) -> NSView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
        image.contentTintColor = .systemGreen
        image.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: title)
        label.textColor = .systemGreen
        let status = NSStackView(views: [image, label])
        status.orientation = .horizontal
        status.alignment = .centerY
        status.spacing = 5
        return status
    }

    func refreshPermissionStatus() {
        guard selectedCategory == .permissions, !lifecycle.terminationRequested else { return }
        Task {
            await memoryPanel.refreshPermissions()
            guard !lifecycle.terminationRequested else { return }
            await finder.refresh()
        }
    }

    private func showAbout() {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else { preconditionFailure("The application bundle must contain its version and build") }
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Buckle")
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 112), icon.heightAnchor.constraint(equalToConstant: 112),
        ])
        let name = NSTextField(labelWithString: "Buckle")
        name.font = .systemFont(ofSize: 30, weight: .bold)
        name.alignment = .center
        let versionBadge = VersionBadgeView(text: "\(version) (\(build))")
        let check = button(localized("update.check"), action: #selector(checkUpdates))
        check.isEnabled = updates.canCheck
        var views: [NSView] = [icon, name, versionBadge, check]
        if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
            let label = description(copyright)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
            label.alignment = .center
            views.append(label)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.setCustomSpacing(16, after: versionBadge)
        stack.setCustomSpacing(20, after: check)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(stack)
        contentStack.addArrangedSubview(container)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor),
            container.heightAnchor.constraint(equalTo: view.heightAnchor, constant: -37),
            container.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
        ])
    }

    private func addSection(_ title: String, rows: [NSView], accessory: NSView? = nil) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let header = NSView()
        label.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(label)
        if let accessory {
            accessory.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(accessory)
            NSLayoutConstraint.activate([
                accessory.trailingAnchor.constraint(equalTo: header.trailingAnchor),
                accessory.centerYAnchor.constraint(equalTo: header.centerYAnchor),
                label.trailingAnchor.constraint(lessThanOrEqualTo: accessory.leadingAnchor, constant: -8),
            ])
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            header.heightAnchor.constraint(equalToConstant: 24),
        ])
        contentStack.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
        contentStack.setCustomSpacing(6, after: header)
        let card = ApplicationSettingsCardView(rows: rows)
        contentStack.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    private func settingRow(_ title: String, control: NSView) -> NSView {
        let label = description(title)
        label.alignment = .left
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, spacer, control])
        row.orientation = .horizontal
        row.distribution = .fill
        row.alignment = .centerY
        row.spacing = 12
        row.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        return row
    }

    private func toggle(_ title: String, enabled: Bool, action: Selector, available: Bool = true) -> NSSwitch {
        let control = NSSwitch()
        control.controlSize = .small
        control.state = enabled ? .on : .off
        control.target = self
        control.action = action
        control.isEnabled = available
        control.setAccessibilityLabel(title)
        return control
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func description(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.isSelectable = true
        return label
    }

    private func addDescription(_ text: String) {
        let label = description(text)
        label.textColor = .secondaryLabelColor
        contentStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: contentStack.widthAnchor).isActive = true
    }

    @objc private func changeLaunchAtLogin(_ sender: NSSwitch) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            refresh()
            present(error)
        }
    }

    @objc private func changeLanguage(_ sender: NSPopUpButton) {
        guard let identifier = sender.selectedItem?.representedObject as? String,
            let language = ApplicationLanguage(rawValue: identifier)
        else { preconditionFailure("Language menu items must identify a supported language") }
        languagePreferences.select(language)
    }

    @objc private func approveLogin() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func changeAutomaticUpdates(_ sender: NSSwitch) { updates.setAutomaticChecks(sender.state == .on) }
    @objc private func checkUpdates() { updates.checkForUpdates() }
    @objc private func openAccessibility(_ sender: NSButton) {
        guard !lifecycle.terminationRequested else { return }
        permissionGuidance.showAccessibility(from: sender)
    }
    @objc private func openAutomation() {
        permissionGuidance.close()
        Task {
            do {
                try await memoryPanel.requestAutomationPermission()
                guard !lifecycle.terminationRequested else { return }
                if memoryPanel.automationGranted == false { permissionGuidance.showAutomation() }
            } catch CocoaError.userCancelled {
                return
            } catch {
                guard !lifecycle.terminationRequested else { return }
                present(error)
            }
        }
    }
    @objc private func showApplication() {
        guard !lifecycle.terminationRequested else { return }
        finder.showApplication()
    }
    @objc private func enableFinder() {
        Task {
            guard !lifecycle.terminationRequested else { return }
            await finder.enable()
            guard !lifecycle.terminationRequested else { return }
            if case .disabled = finder.state { finder.openSettings() }
        }
    }
    @objc private func checkFinder() {
        Task {
            guard !lifecycle.terminationRequested else { return }
            await finder.refresh()
        }
    }
    @objc private func restoreFinder() {
        guard !lifecycle.terminationRequested, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = localized("finder.configuration.restore")
        alert.informativeText = localized("finder.configuration.restore.help")
        alert.addButton(withTitle: localized("finder.configuration.restore"))
        alert.addButton(withTitle: localized("cancel"))
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                Task {
                    guard let self, !self.lifecycle.terminationRequested else { return }
                    await self.finder.restoreConfiguration()
                }
            }
        }
    }

    private func present(_ error: Error) {
        guard let window = view.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class ApplicationSettingsCardView: NSView {
    override var wantsUpdateLayer: Bool { true }

    init(rows: [NSView]) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.masksToBounds = true
        var views: [NSView] = []
        for (index, row) in rows.enumerated() {
            views.append(row)
            if index < rows.count - 1 {
                let separator = NSBox()
                separator.boxType = .separator
                views.append(separator)
            }
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        for row in rows { row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }
}

@MainActor
final class VersionBadgeView: NSView {
    override var wantsUpdateLayer: Bool { true }
    private let label: NSTextField

    init(text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        setAccessibilityLabel(text)
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: label.intrinsicContentSize.width + 18, height: 22) }

    override func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
        }
    }
}
