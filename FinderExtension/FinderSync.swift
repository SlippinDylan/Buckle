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
        guard menuKind == .contextualMenuForItems,
            let files = FIFinderSyncController.default().selectedItemURLs(), !files.isEmpty
        else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        do {
            // Read on each menu opening so switches work without restarting Finder or sharing an App Group.
            guard try FinderConfigurationStore.standard().load().airDropEnabled else { return menu }
            guard let service = NSSharingService(named: .sendViaAirDrop) else { return menu }
            let item = NSMenuItem(title: service.title, action: #selector(airDrop(_:)), keyEquivalent: "")
            item.target = self
            item.image = service.image
            menu.addItem(item)
        } catch {
            logger.error("Could not read menu configuration: \(error.localizedDescription, privacy: .private)")
            let item = NSMenuItem(title: localized("finder.menu.unavailable"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    @objc private func airDrop(_ sender: NSMenuItem) {
        guard let files = FIFinderSyncController.default().selectedItemURLs(), !files.isEmpty else { return }
        do {
            let request = try FinderAirDropRequest(files: files).url()
            let host = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.open([request], withApplicationAt: host, configuration: configuration) {
                [logger] _, error in
                if let error { logger.error("Could not open Buckle: \(error.localizedDescription, privacy: .private)") }
            }
        } catch {
            logger.error("Invalid AirDrop selection: \(error.localizedDescription, privacy: .private)")
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
