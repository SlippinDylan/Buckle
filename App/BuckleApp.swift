import AppKit
import SwiftUI

@main
enum BuckleApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = MemoryMonitor()
    private let airDrop = AirDropService()
    private let finderExtension = FinderExtensionController()
    private let lifecycle = ApplicationLifecycle()
    private lazy var mouseReset = MouseResetController(lifecycle: lifecycle)
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private lazy var systemMemoryPanel = SystemMemoryPanel(lifecycle: lifecycle)
    private lazy var updates = ApplicationUpdateController()
    private var ownsApplicationState = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            })
        {
            NSApp.terminate(nil)
            return
        }
        ownsApplicationState = true
        lifecycle.onReadyToTerminate = { [weak self] in
            self?.prepareToTerminate()
        }
        NSApp.setActivationPolicy(.accessory)
        do { try systemMemoryPanel.recover() } catch { systemMemoryPanel.error = error.localizedDescription }
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Buckle")
            button.target = self
            button.action = #selector(handleStatusClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = localized("memory.menu.help")
        }
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MemoryView(
                monitor: monitor, systemMemoryPanel: systemMemoryPanel,
                openMemory: { [weak self] in
                    Task { await self?.showSystemMemoryPanel(requestPermission: true) }
                }, mouseReset: mouseReset, finderExtension: finderExtension, updates: updates))
        mouseReset.onStateChange = { [weak self] in
            guard let self else { return }
            if let button = self.statusItem?.button {
                let label = self.mouseReset.accessibilityLabel
                button.image = NSImage(systemSymbolName: self.mouseReset.symbol, accessibilityDescription: label)
                button.setAccessibilityLabel(label)
                if self.mouseReset.isPresented && !self.mouseReset.isRunning {
                    NSAccessibility.post(
                        element: button, notification: .announcementRequested,
                        userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                }
            }
            self.popover.behavior = self.mouseReset.isPresented ? .applicationDefined : .transient
        }
        monitor.onReminder = { [weak self] in
            await self?.showSystemMemoryPanel(requestPermission: false) ?? false
        }
        monitor.start()
        Task { await finderExtension.refresh() }
        Task { await systemMemoryPanel.refreshPermissions() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        do {
            guard try FinderConfigurationStore.standard().load().airDropEnabled else {
                throw NSError(
                    domain: "Buckle.Finder", code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: localized("finder.airdrop.disabled")
                    ])
            }
            for url in urls {
                let request = try FinderAirDropRequest(url: url)
                try airDrop.sendFiles(request.files)
            }
        } catch is FinderAirDropRequest.RequestError {
            let alert = NSAlert()
            alert.messageText = localized("finder.invalid.request")
            alert.runModal()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsApplicationState else { return .terminateNow }
        // Sparkle's quit event uses this same gate; no separate update-only busy state is needed.
        if lifecycle.requestTermination() { prepareToTerminate() }
        return .terminateLater
    }

    private func prepareToTerminate() {
        Task { @MainActor in
            let recovery = ApplicationRecovery(memoryPanel: systemMemoryPanel, mouseReset: mouseReset)
            let allowed = await lifecycle.resolveTermination(recover: recovery.restore) { failure in
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = localized("quit.recovery.title")
                alert.informativeText = localized("quit.recovery.help") + "\n\n" + failure.localizedDescription
                alert.addButton(withTitle: localized("cancel"))
                alert.addButton(withTitle: localized("quit.recovery.retry"))
                alert.addButton(withTitle: localized("quit.recovery.quit"))
                if failure.includesMemory { alert.addButton(withTitle: localized("memory.recovery.show")) }
                switch alert.runModal() {
                case .alertSecondButtonReturn: return .retry
                case .alertThirdButtonReturn: return .quit
                case NSApplication.ModalResponse(
                    rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
                    systemMemoryPanel.showRecoveryRecord()
                    return .cancel
                default: return .cancel
                }
            }
            NSApp.reply(toApplicationShouldTerminate: allowed)
        }
    }

    @objc private func handleStatusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp || mouseReset.isPresented {
            togglePopover()
        } else {
            Task { await showSystemMemoryPanel(requestPermission: true) }
        }
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        Task { await finderExtension.refresh() }
        if !popover.isShown { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }

    @discardableResult
    private func showSystemMemoryPanel(requestPermission: Bool) async -> Bool {
        guard !systemMemoryPanel.isOpening else { return false }
        do {
            let opened = try await systemMemoryPanel.show(requestPermission: requestPermission)
            if !lifecycle.terminationRequested {
                if opened { popover.performClose(nil) } else if requestPermission { showPopover() }
            }
            return opened
        } catch {
            systemMemoryPanel.error = error.localizedDescription
            if requestPermission && !lifecycle.terminationRequested {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
            return false
        }
    }
}
