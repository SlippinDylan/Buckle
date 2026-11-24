import AppKit
import CryptoKit
import FinderSync
import OSLog
import os.lock

@MainActor
final class BuckleFinderSync: FIFinderSync {
    private let logger = Logger(subsystem: FinderIntegration.identifier, category: "Finder")

    private let openRequest: @MainActor @Sendable (URL, Logger) -> Void
    private let copyFiles: @MainActor @Sendable ([URL], Logger) -> Void

    private enum MenuAction: Sendable {
        case open(URL)
        case copy([URL])
        case newTextFile(FinderNewTextFileTarget, SymmetricKey)
    }

    private struct MenuActions {
        var nextTag = 1
        var snapshots: [Int: MenuAction] = [:]
    }

    private nonisolated let menuActions = OSAllocatedUnfairLock(initialState: MenuActions())

    override convenience init() {
        self.init(observeDirectories: { FIFinderSyncController.default().directoryURLs = $0 })
    }

    nonisolated init(
        observeDirectories: (Set<URL>) -> Void,
        openRequest: @escaping @MainActor @Sendable (URL, Logger) -> Void = BuckleFinderSync.openHost,
        copyFiles: @escaping @MainActor @Sendable ([URL], Logger) -> Void = BuckleFinderSync.copyPaths
    ) {
        self.openRequest = openRequest
        self.copyFiles = copyFiles
        super.init()
        // Only observe the startup volume so Finder does not replace sidebar icons for other mounted volumes.
        observeDirectories([URL(fileURLWithPath: "/")])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        let context: FinderMenuContext
        switch menuKind {
        case .contextualMenuForItems:
            guard let files = controller.selectedItemURLs(), !files.isEmpty else { return nil }
            context = .items(files)
        case .contextualMenuForContainer:
            guard let directory = controller.targetedURL() else { return nil }
            context = .container(directory)
        default: return nil
        }
        do {
            return makeMenu(for: context, store: try FinderConfigurationStore.standard())
        } catch {
            logger.error("Could not locate Finder configuration: \(error.localizedDescription, privacy: .private)")
            let menu = NSMenu()
            menu.autoenablesItems = false
            addUnavailableItem(to: menu, language: nil)
            publish([:])
            return menu
        }
    }

    nonisolated func makeMenu(
        for context: FinderMenuContext, store: FinderConfigurationStore,
        loadConfiguration: @Sendable (FinderConfigurationStore) throws -> FinderConfiguration = { try $0.load() }
    ) -> NSMenu {
        // Build privately: another Finder request may finish while this one is reading configuration.
        var actions: [Int: MenuAction] = [:]
        let menu = NSMenu()
        menu.autoenablesItems = false
        var language: String?
        do {
            // Snapshot the context with each item; the action must not follow later selection changes.
            let configuration = try loadConfiguration(store)
            language = configuration.language
            if case .items = context, configuration.airDropEnabled,
                let service = NSSharingService(named: .sendViaAirDrop)
            {
                try add(
                    .airDrop, files: context.files, title: service.title, image: service.image, to: menu,
                    actions: &actions)
            }
            let directory: URL?
            if configuration.terminalEnabled || configuration.moveEnabled || configuration.newTextFileEnabled {
                do { directory = try context.directory() } catch {
                    directory = nil
                    logger.error("Could not read Finder directory: \(error.localizedDescription, privacy: .private)")
                    let item = NSMenuItem(
                        title: localized("finder.directory.unavailable", language: language), action: nil,
                        keyEquivalent: "")
                    item.isEnabled = false
                    menu.addItem(item)
                }
            } else {
                directory = nil
            }
            if configuration.terminalEnabled, let directory {
                try add(
                    .terminal, files: [directory], title: localized("finder.terminal.title", language: language),
                    image: FinderAction.terminal.menuImage(), to: menu, actions: &actions)
            }
            if configuration.copyPathEnabled {
                let item = NSMenuItem(
                    title: localized("finder.copyPath.title", language: language), action: #selector(copyPath(_:)),
                    keyEquivalent: "")
                item.target = self
                item.tag = register(.copy(context.files), in: &actions)
                item.image = FinderAction.copyPath.menuImage()
                menu.addItem(item)
            }
            if configuration.newTextFileEnabled, let directory {
                do {
                    let target = try FinderNewTextFileTarget(directory: directory)
                    let key = try store.loadNewTextFileKey()
                    let item = NSMenuItem(
                        title: localized("finder.newTextFile.title", language: language),
                        action: #selector(performAction(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = register(.newTextFile(target, key), in: &actions)
                    item.image = FinderAction.newTextFile.menuImage()
                    menu.addItem(item)
                } catch {
                    logger.error(
                        "Could not prepare text file request: \(error.localizedDescription, privacy: .private)")
                    addUnavailableItem(to: menu, language: language)
                }
            }
            if configuration.moveEnabled, let directory {
                let item = NSMenuItem(
                    title: localized("finder.move.title", language: language), action: #selector(performAction(_:)),
                    keyEquivalent: "")
                item.target = self
                item.image = FinderAction.move.menuImage()
                item.isEnabled = NSPasteboard.general.canReadObject(
                    forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                let request = try FinderActionRequest(
                    action: .move, files: [directory], clipboardChangeCount: NSPasteboard.general.changeCount
                ).signed(using: store.loadMoveKey()).url()
                item.tag = register(.open(request), in: &actions)
                menu.addItem(item)
            }
        } catch {
            logger.error("Could not create Finder menu: \(error.localizedDescription, privacy: .private)")
            addUnavailableItem(to: menu, language: language)
        }
        publish(actions)
        return menu
    }

    private nonisolated func addUnavailableItem(to menu: NSMenu, language: String?) {
        let item = NSMenuItem(
            title: localized("finder.menu.unavailable", language: language), action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private nonisolated func add(
        _ action: FinderAction, files: [URL], title: String, image: NSImage?, to menu: NSMenu,
        actions: inout [Int: MenuAction]
    ) throws {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.image = image
        item.tag = register(.open(try FinderActionRequest(action: action, files: files).url()), in: &actions)
        menu.addItem(item)
    }

    private nonisolated func register(_ action: MenuAction, in snapshots: inout [Int: MenuAction]) -> Int {
        let tag = menuActions.withLock { state in
            let tag = state.nextTag
            state.nextTag += 1
            return tag
        }
        snapshots[tag] = action
        return tag
    }

    private nonisolated func publish(_ snapshots: [Int: MenuAction]) {
        // Only a complete menu generation becomes visible to concurrent Finder callbacks.
        menuActions.withLock { $0.snapshots = snapshots }
    }

    private nonisolated func dispatchAction(_ sender: NSMenuItem) {
        // Capture under the lock before the actor hop; rebuilding a menu must not erase an accepted click.
        let tag = sender.tag
        guard let action = menuActions.withLock({ $0.snapshots[tag] }) else {
            logger.error("Rejected unknown or expired Finder menu action tag: \(tag, privacy: .public)")
            return
        }
        Task { @MainActor [openRequest, copyFiles, logger] in
            switch action {
            case .open(let request): openRequest(request, logger)
            case .copy(let files): copyFiles(files, logger)
            case .newTextFile(let target, let key):
                do {
                    openRequest(try FinderNewTextFileRequest(target: target, key: key).url(), logger)
                } catch {
                    logger.error("Could not encode text file request: \(error.localizedDescription, privacy: .private)")
                    NSAlert(error: error).runModal()
                }
            }
        }
    }

    @objc private nonisolated func performAction(_ sender: NSMenuItem) {
        dispatchAction(sender)
    }

    private static func openHost(_ request: URL, logger: Logger) {
        let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.open([request], withApplicationAt: host, configuration: configuration) {
            [logger] _, error in
            if let error {
                logger.error("Could not open Buckle: \(error.localizedDescription, privacy: .private)")
                Task { @MainActor in
                    let language: String?
                    do { language = try FinderConfigurationStore.standard().load().language } catch {
                        logger.error("Could not read Finder language: \(error.localizedDescription, privacy: .private)")
                        language = nil
                    }
                    let alert = NSAlert()
                    alert.messageText = localized("finder.host.unavailable", language: language)
                    alert.informativeText = localized("finder.host.unavailable.help", language: language)
                    alert.alertStyle = .warning
                    alert.window.level = .modalPanel
                    alert.window.orderFrontRegardless()
                    alert.runModal()
                }
            }
        }
    }

    @objc private nonisolated func copyPath(_ sender: NSMenuItem) {
        dispatchAction(sender)
    }

    private static func copyPaths(_ files: [URL], logger: Logger) {
        var language: String?
        do {
            let configuration = try FinderConfigurationStore.standard().load()
            language = configuration.language
            guard configuration.copyPathEnabled else { return }
            try FinderPathCopy.write(files, to: .general)
        } catch {
            logger.error("Could not copy paths: \(error.localizedDescription, privacy: .private)")
            let alert = NSAlert()
            alert.messageText = localized("finder.copyPath.failed", language: language)
            alert.informativeText =
                localized("finder.copyPath.failed.help", language: language)
                + "\n\n" + error.localizedDescription
            alert.alertStyle = .warning
            alert.window.level = .modalPanel
            alert.window.orderFrontRegardless()
            alert.runModal()
        }
    }
}

enum FinderPathCopy {
    static func write(_ files: [URL], to pasteboard: NSPasteboard) throws {
        guard !files.isEmpty, files.allSatisfy({ $0.isFileURL }) else {
            throw FinderActionRequest.RequestError.invalidFiles
        }
        let paths = files.map(\.path).joined(separator: "\n")
        pasteboard.clearContents()
        guard pasteboard.setString(paths, forType: .string) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
