import AppKit

@MainActor
final class AirDropService: NSObject, NSSharingServiceDelegate {
    private var activeServices: [NSSharingService] = []
    private let presentError: (Error) -> Void

    init(presentError: @escaping (Error) -> Void = { NSAlert(error: $0).runModal() }) {
        self.presentError = presentError
        super.init()
    }

    func sendFiles(_ urls: [URL]) throws {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            throw NSError(
                domain: "Buckle.AirDrop", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: localized("airdrop.unavailable")
                ])
        }
        service.delegate = self
        activeServices.append(service)
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        activeServices.removeAll { $0 === sharingService }
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        activeServices.removeAll { $0 === sharingService }
        guard (error as? CocoaError)?.code != .userCancelled else { return }
        presentError(error)
    }
}
