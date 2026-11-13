import AppKit
import FinderSync
import Observation

@MainActor @Observable
final class FinderExtensionController {
    enum State {
        case checking, missing, unregistered, disabled, enabled
        case invalidConfiguration(String)
        case failed(String)
    }

    private(set) var state: State = .checking
    private(set) var configuration: FinderConfiguration?
    private(set) var isBusy = false
    @ObservationIgnored private let configurationStore: () throws -> FinderConfigurationStore
    @ObservationIgnored private let language = Bundle.main.preferredLocalizations.first

    init(configurationStore: @escaping () throws -> FinderConfigurationStore = FinderConfigurationStore.standard) {
        self.configurationStore = configurationStore
    }

    private var extensionURL: URL {
        Bundle.main.bundleURL.appending(path: "Contents/PlugIns/\(FinderIntegration.bundleName)")
    }

    func refresh() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        configuration = nil
        do {
            do {
                let store = try configurationStore()
                var loaded = try store.load()
                // Use this process's resolved language; language changes take effect after restarting Buckle.
                if loaded.language != language {
                    loaded.language = language
                    try store.save(loaded)
                }
                configuration = loaded
            } catch let error as DecodingError {
                state = .invalidConfiguration(error.localizedDescription)
                return
            }
            state = try await readState()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func restoreConfiguration() async {
        guard !isBusy else { return }
        do {
            try configurationStore().restoreDefaults()
            await refresh()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool, for action: FinderAction) throws {
        var updated = try configurationStore().load()
        updated.setEnabled(enabled, for: action)
        try configurationStore().save(updated)
        configuration = updated
    }

    func enable() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await CommandRunner.run("/usr/bin/pluginkit", arguments: ["-a", extensionURL.path])
            _ = try await CommandRunner.run(
                "/usr/bin/pluginkit", arguments: ["-e", "use", "-i", FinderIntegration.identifier])
            state = try await readState()
        } catch { state = .failed(error.localizedDescription) }
    }

    func openSettings() {
        FIFinderSyncController.showExtensionManagementInterface()
    }

    func showApplication() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private func readState() async throws -> State {
        guard FileManager.default.fileExists(atPath: extensionURL.path) else { return .missing }
        let output = try await CommandRunner.run(
            "/usr/bin/pluginkit",
            arguments: [
                "-m", "-A", "-D", "-v", "-p", "com.apple.FinderSync", "-i", FinderIntegration.identifier,
            ])
        let paths = try FinderRegistration.paths(in: output)
        guard paths.contains(extensionURL.standardizedFileURL.resolvingSymlinksInPath()) else { return .unregistered }
        return FIFinderSyncController.isExtensionEnabled ? .enabled : .disabled
    }
}
