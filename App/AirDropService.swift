import AppKit

@MainActor
protocol AirDropSending {
    func sendFiles(_ urls: [URL]) async throws
}

@MainActor
final class AirDropService: NSObject, AirDropSending, NSSharingServiceDelegate {
    private var pending: (service: NSSharingService, completion: CheckedContinuation<Void, Error>)?
    private let makeService: () -> NSSharingService?
    private let perform: (NSSharingService, [URL]) -> Void

    init(
        makeService: @escaping () -> NSSharingService? = { NSSharingService(named: .sendViaAirDrop) },
        perform: @escaping (NSSharingService, [URL]) -> Void = { service, urls in
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
        }
    ) {
        self.makeService = makeService
        self.perform = perform
        super.init()
    }

    func sendFiles(_ urls: [URL]) async throws {
        try Task.checkCancellation()
        guard pending == nil, let service = makeService(), service.canPerform(withItems: urls) else {
            throw NSError(
                domain: "Buckle.AirDrop", code: 1,
                userInfo: [NSLocalizedDescriptionKey: localized("airdrop.unavailable")])
        }
        service.delegate = self
        try await withCheckedThrowingContinuation { completion in
            pending = (service, completion)
            perform(service, urls)
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        finish(sharingService, error: nil)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        finish(sharingService, error: error)
    }

    private func finish(_ service: NSSharingService, error: Error?) {
        guard let pending, pending.service === service else { return }
        self.pending = nil
        service.delegate = nil
        if let error, (error as? CocoaError)?.code != .userCancelled {
            pending.completion.resume(throwing: error)
        } else {
            pending.completion.resume()
        }
    }
}
