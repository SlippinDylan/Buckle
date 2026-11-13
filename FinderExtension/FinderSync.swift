import AppKit
import FinderSync
import OSLog

@MainActor
final class BuckleFinderSync: FIFinderSync {
    private let logger = Logger(subsystem: FinderIntegration.identifier, category: "Finder")

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
        if let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: .skipHiddenVolumes)
        {
            FIFinderSyncController.default().directoryURLs.formUnion(volumes)
        } else {
            logger.error("Could not enumerate mounted volumes.")
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeMounted(_:)), name: NSWorkspace.didMountNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(volumeUnmounted(_:)), name: NSWorkspace.didUnmountNotification, object: nil)
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
        let menu = NSMenu()
        menu.autoenablesItems = false
        var language: String?
        do {
            // Snapshot the context with each item; the action must not follow later selection changes.
            let configuration = try FinderConfigurationStore.standard().load()
            language = configuration.language
            if case .items = context, configuration.airDropEnabled,
                let service = NSSharingService(named: .sendViaAirDrop)
            {
                try add(.airDrop, files: context.files, title: service.title, image: service.image, to: menu)
            }
            if configuration.terminalEnabled, let directory = try context.directory() {
                try add(
                    .terminal, files: [directory], title: localized("finder.terminal.title", language: language),
                    image: NSImage(systemSymbolName: "terminal", accessibilityDescription: nil), to: menu)
            }
            if configuration.copyPathEnabled {
                let item = NSMenuItem(
                    title: localized("finder.copyPath.title", language: language), action: #selector(copyPath(_:)),
                    keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil)
                item.representedObject = context.files
                menu.addItem(item)
            }
            if configuration.moveEnabled, let directory = try context.directory() {
                let item = NSMenuItem(
                    title: localized("finder.move.title", language: language), action: #selector(performAction(_:)),
                    keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: "folder.badge.arrow.forward", accessibilityDescription: nil)
                item.isEnabled = NSPasteboard.general.canReadObject(
                    forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
                item.representedObject = try FinderActionRequest(
                    action: .move, files: [directory], clipboardChangeCount: NSPasteboard.general.changeCount
                ).url()
                menu.addItem(item)
            }
        } catch {
            logger.error("Could not create Finder menu: \(error.localizedDescription, privacy: .private)")
            let item = NSMenuItem(
                title: localized("finder.menu.unavailable", language: language), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    private nonisolated func add(_ action: FinderAction, files: [URL], title: String, image: NSImage?, to menu: NSMenu)
        throws
    {
        let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
        item.target = self
        item.image = image
        item.representedObject = try FinderActionRequest(action: action, files: files).url()
        menu.addItem(item)
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? URL else { return }
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

    @objc private func copyPath(_ sender: NSMenuItem) {
        guard let files = sender.representedObject as? [URL] else { return }
        do {
            guard try FinderConfigurationStore.standard().load().copyPathEnabled else { return }
            try FinderPathCopy.write(files, to: .general)
        } catch {
            logger.error("Could not copy paths: \(error.localizedDescription, privacy: .private)")
            NSSound.beep()
        }
    }

    @objc private func volumeMounted(_ notification: Notification) {
        guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        FIFinderSyncController.default().directoryURLs.insert(url)
    }

    @objc private func volumeUnmounted(_ notification: Notification) {
        guard let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
        FIFinderSyncController.default().directoryURLs.remove(url)
    }
}

enum FinderPathCopy {
    static func write(_ files: [URL], to pasteboard: NSPasteboard) throws {
        guard !files.isEmpty, files.allSatisfy({ $0.isFileURL }) else {
            throw FinderActionRequest.RequestError.invalidFiles
        }
        pasteboard.clearContents()
        guard pasteboard.setString(files.map(\.path).joined(separator: "\n"), forType: .string) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
