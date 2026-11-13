import ServiceManagement
import SwiftUI

struct MemoryView: View {
    @Bindable var monitor: MemoryMonitor
    let systemMemoryPanel: SystemMemoryPanel
    let openMemory: () -> Void
    let mouseReset: MouseResetController
    let finderExtension: FinderExtensionController
    let updates: ApplicationUpdateController
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var browsers = BrowserLauncher.installed()

    var body: some View {
        if mouseReset.isPresented {
            MouseResetView(controller: mouseReset)
        } else {
            memoryContent
        }
    }

    private var memoryContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(localized("memory.title"), systemImage: "memorychip")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(monitor.isLoading)
                .help(localized("refresh"))
                .accessibilityLabel(localized("refresh"))
            }
            Button(action: openMemory) {
                Label(localized("memory.open.system"), systemImage: "macwindow")
            }
            .disabled(systemMemoryPanel.isOpening)
            if let error = monitor.error {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let issue = systemMemoryPanel.permissionIssue {
                Text(issue.message).font(.callout)
                Text(localized("memory.permissions.update.help")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(localized("finder.settings")) { issue.openSettings() }
                    Button(localized("memory.permissions.recheck")) {
                        Task { await systemMemoryPanel.refreshPermissions() }
                    }
                    .disabled(systemMemoryPanel.isOpening)
                }
                Button(localized("finder.show.app")) { finderExtension.showApplication() }
            }
            if let error = systemMemoryPanel.error ?? systemMemoryPanel.permissionError {
                Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled)
            }
            if let configuration = finderExtension.configuration {
                Toggle(
                    localized("finder.airdrop.toggle"),
                    isOn: Binding(
                        get: { configuration.airDropEnabled },
                        set: { finderExtension.setAirDropEnabled($0) }
                    ))
            }
            HStack {
                Menu {
                    Menu(localized("browser.launch")) {
                        if browsers.isEmpty { Text(localized("browser.none")) }
                        ForEach(browsers) { browser in
                            Menu(browser.name) {
                                ForEach(BrowserLanguage.allCases, id: \.self) { language in
                                    Button(language.name) {
                                        Task {
                                            do { try await BrowserLauncher.launch(browser, language: language) } catch {
                                                showError(error)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Button(localized("mouse.reset")) { Task { await mouseReset.run() } }
                    Divider()
                    Toggle(localized("memory.reminders"), isOn: $monitor.remindersEnabled)
                    Toggle(
                        localized("login.launch"),
                        isOn: Binding(
                            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                            set: { setLaunchAtLogin($0) }
                        ))
                    if loginStatus == .requiresApproval {
                        Button(localized("login.approve")) { SMAppService.openSystemSettingsLoginItems() }
                    }
                    Divider()
                    Button(localized("update.check")) { updates.checkForUpdates() }
                        .disabled(!updates.canCheck)
                    Toggle(
                        localized("update.automatic"),
                        isOn: Binding(
                            get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) })
                    )
                    .disabled(!updates.isAvailable)
                    if let status = updates.status { Text(status) }
                    Divider()
                    Button(localized("buckle.quit")) { NSApp.terminate(nil) }
                } label: {
                    Label(localized("tools"), systemImage: "slider.horizontal.3")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                if let date = monitor.lastUpdated {
                    Text(date, style: .time).font(.caption).foregroundStyle(.secondary)
                }
            }
            FinderExtensionStatusView(controller: finderExtension)
        }
        .padding(18)
        .frame(width: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await finderExtension.refresh() }
            Task { await systemMemoryPanel.refreshPermissions() }
        }
        .onAppear {
            loginStatus = SMAppService.mainApp.status
            browsers = BrowserLauncher.installed()
            Task { await monitor.refresh() }
            Task { await finderExtension.refresh() }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            loginStatus = SMAppService.mainApp.status
            showError(error)
        }
    }

    private func showError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }
}
