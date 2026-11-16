import AppKit
import BucklePermissionSupport
import OSLog
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
    private let finderExtension = FinderExtensionController()
    private let lifecycle = ApplicationLifecycle()
    private lazy var mouseReset = MouseResetController(lifecycle: lifecycle)
    private lazy var menuBarRestart = MenuBarRestartController(lifecycle: lifecycle)
    private lazy var finderActions = FinderActionService(lifecycle: lifecycle)
    private let permissionGuidance = PermissionGuidance()
    private lazy var settings = ApplicationSettingsWindowController(
        memoryPanel: systemMemoryPanel, finder: finderExtension,
        updates: updates, lifecycle: lifecycle, permissionGuidance: permissionGuidance)
    private lazy var statusMenu = StatusMenuController(
        memoryPanel: systemMemoryPanel, mouseReset: mouseReset,
        menuBarRestart: menuBarRestart, finder: finderExtension, lifecycle: lifecycle,
        openMemory: { [weak self] in Task { await self?.showSystemMemoryPanel() } },
        openSettings: { [weak self] category in self?.showSettings(category: category) },
        resetMouse: { [weak self] in self?.showMouseReset() })
    private var mouseResetWindow: NSWindow?
    private lazy var systemMemoryPanel = SystemMemoryPanel(lifecycle: lifecycle)
    private let updates = ApplicationUpdateController()
    private var ownsApplicationState = false
    private let onboardingState = OnboardingState()
    private var onboardingWindow: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let signposter = OSSignposter(subsystem: "studio.slippindylan.Buckle", category: "Lifecycle")
        let interval = signposter.beginInterval("Launch Setup")
        defer { signposter.endInterval("Launch Setup", interval) }
        if let identifier = Bundle.main.bundleIdentifier,
            NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: {
                $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
            })
        {
            NSApp.terminate(nil)
            return
        }
        ownsApplicationState = true
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAsLoginItem =
            launchEvent?.eventID == kAEOpenApplication
            && launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        onboardingState.prepareLaunch(
            isDefaultLaunch: notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == true,
            isLoginItem: launchedAsLoginItem)
        settings.onChange = { [weak self] in self?.onboardingWindow?.refresh() }
        updates.start()
        lifecycle.onReadyToTerminate = { [weak self] in
            self?.prepareToTerminate()
        }
        NSApp.setActivationPolicy(.accessory)
        do { try systemMemoryPanel.recover() } catch { systemMemoryPanel.error = error.localizedDescription }
        statusMenu.start()
        mouseReset.onStateChange = { [weak self] in
            guard let self else { return }
            self.statusMenu.updateStatusImage()
            if !self.mouseReset.isPresented { self.mouseResetWindow?.close() }
        }
        Task { @MainActor in
            do {
                try await mouseReset.recoverInterruptedReset {
                    NSApp.activate()
                    let alert = NSAlert()
                    alert.messageText = localized("mouse.recovery.title")
                    alert.informativeText = localized("mouse.recovery.help")
                    alert.addButton(withTitle: localized("mouse.recovery.later"))
                    alert.addButton(withTitle: localized("mouse.recovery.restore"))
                    return alert.runModal() == .alertSecondButtonReturn
                }
            } catch {
                guard lifecycle.shouldPresentUserActionError(error) else { return }
                NSApp.activate()
                NSAlert(error: error).runModal()
            }
            if onboardingState.shouldPresentAutomatically, !lifecycle.terminationRequested { showOnboarding() }
        }
        Task { await finderExtension.refresh() }
        Task { await systemMemoryPanel.refreshPermissions() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        onboardingState.suppressAutomaticPresentation()
        onboardingWindow?.suspend()
        Task { @MainActor in
            guard !lifecycle.terminationRequested else { return }
            do {
                for url in urls {
                    if url.path == "/new-text-file" {
                        try await finderActions.handle(FinderNewTextFileRequest(url: url))
                    } else {
                        try await finderActions.handle(FinderActionRequest(url: url))
                    }
                }
            } catch {
                guard lifecycle.shouldPresentUserActionError(error) else { return }
                NSApp.activate()
                let alert = FinderActionAlert.make(error)
                if alert.runModal() == .alertFirstButtonReturn,
                    let requirement = error as? PermissionRequirement,
                    !lifecycle.terminationRequested
                {
                    settings.requestPermission(requirement, from: alert.buttons[0])
                }
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard ownsApplicationState else { return }
        Task { await finderExtension.refresh() }
        Task { await systemMemoryPanel.refreshPermissions() }
        settings.refresh()
        if onboardingWindow?.window?.isVisible == true, onboardingWindow?.step == .permissions {
            settings.refreshOnboardingPermissions()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) { permissionGuidance.close() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ownsApplicationState else { return .terminateNow }
        onboardingWindow?.suspendForTermination()
        permissionGuidance.close()
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
            if !allowed { onboardingWindow?.resumeAfterCancelledTermination() }
        }
    }

    private func showOnboarding() {
        guard !lifecycle.terminationRequested, !lifecycle.isActive(.finderAction), !lifecycle.isActive(.mouseReset)
        else { return }
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(
                lifecycle: lifecycle,
                rows: { [settings] in settings.onboardingRows(for: $0) },
                didChangeStep: { [weak self] step in
                    guard let self, step == .permissions, !self.lifecycle.terminationRequested else { return }
                    self.settings.refreshOnboardingPermissions()
                },
                didDismiss: { [weak self] in
                    self?.onboardingState.dismiss()
                    self?.permissionGuidance.close()
                },
                didComplete: { [weak self] in
                    guard let self, !self.lifecycle.terminationRequested else { return }
                    self.statusMenu.statusItem?.button?.performClick(nil)
                })
        }
        settings.refresh()
        onboardingWindow?.present()
    }

    private func showSettings(category: ApplicationSettingsViewController.Category? = nil) {
        Task { await finderExtension.refresh() }
        settings.present(category: category)
    }

    private func showMouseReset() {
        guard mouseReset.canPresent else { return }
        if mouseResetWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = localized("mouse.reset")
            window.contentViewController = NSHostingController(rootView: MouseResetView(controller: mouseReset))
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.center()
            mouseResetWindow = window
        }
        NSApp.activate()
        mouseResetWindow?.makeKeyAndOrderFront(nil)
        if !mouseReset.isPresented { Task { await mouseReset.run() } }
    }

    private func showSystemMemoryPanel() async {
        guard systemMemoryPanel.canOpen else { return }
        do {
            let opened = try await systemMemoryPanel.show(requestPermission: true)
            if !opened && !lifecycle.terminationRequested { showSettings(category: .permissions) }
        } catch {
            systemMemoryPanel.error = error.localizedDescription
            if !lifecycle.terminationRequested {
                NSApp.activate(ignoringOtherApps: true)
                NSAlert(error: error).runModal()
            }
        }
    }
}
