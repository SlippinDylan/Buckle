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
    @ObservationIgnored private let runner = FinderPluginKit()
    @ObservationIgnored private let configurationStore: () throws -> FinderConfigurationStore

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
                configuration = try configurationStore().load()
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
            _ = try await runner.run(["-a", extensionURL.path])
            _ = try await runner.run(["-e", "use", "-i", FinderIntegration.identifier])
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
        let output = try await runner.run([
            "-m", "-A", "-D", "-v", "-p", "com.apple.FinderSync", "-i", FinderIntegration.identifier,
        ])
        let paths = try FinderRegistration.paths(in: output)
        guard paths.contains(extensionURL.standardizedFileURL.resolvingSymlinksInPath()) else { return .unregistered }
        return FIFinderSyncController.isExtensionEnabled ? .enabled : .disabled
    }
}

private actor FinderPluginKit {
    func run(_ arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "Buckle.FinderExtension", code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: localized("finder.operation.failed") + "\n" + text
                ])
        }
        return text
    }
}
