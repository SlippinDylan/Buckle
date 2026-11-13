import AppKit
import Combine
import Observation
import Sparkle

@MainActor @Observable
final class ApplicationUpdateController {
    enum State {
        case disabled, unconfigured, ready
        case failed(String)
    }

    private(set) var state: State = .disabled
    private(set) var canCheck = false
    private(set) var automaticChecks = false
    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observations: Set<AnyCancellable> = []
    @ObservationIgnored private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func start() {
        guard controller == nil else { return }
        do {
            let configuration = try UpdateConfiguration(
                enabled: bundle.object(forInfoDictionaryKey: "BuckleUpdaterEnabled") as? String == "YES",
                feed: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "",
                publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
            guard case .enabled = configuration else { return }
            let controller = SPUStandardUpdaterController(
                startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            try controller.updater.start()
            self.controller = controller
            state = .ready
            // Sparkle delivers these KVO changes on the main thread and owns the persisted preference.
            controller.updater.publisher(for: \.canCheckForUpdates)
                .sink { [weak self] in self?.canCheck = $0 }
                .store(in: &observations)
            controller.updater.publisher(for: \.automaticallyChecksForUpdates)
                .sink { [weak self] in self?.automaticChecks = $0 }
                .store(in: &observations)
        } catch is UpdateConfiguration.ConfigurationError {
            state = .unconfigured
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    var status: String? {
        switch state {
        case .disabled: nil
        case .unconfigured: localized("update.unconfigured")
        case .ready: nil
        case .failed(let message): message
        }
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
    }
}
