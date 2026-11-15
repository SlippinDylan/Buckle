import AppKit
import Darwin
import OSLog

@MainActor
protocol AirDropPresenting {
    func present(_ urls: [URL]) async throws
}

@MainActor
final class AirDropService: AirDropPresenting {
    private var session: AirDropSession?
    private let makeService: () -> NSSharingService?
    private let perform: (NSSharingService, [URL]) -> Void
    private let reportError: (Error) -> Void
    private let logger = Logger(subsystem: "studio.slippindylan.Buckle", category: "AirDrop")

    init(
        makeService: @escaping () -> NSSharingService? = { NSSharingService(named: .sendViaAirDrop) },
        perform: @escaping (NSSharingService, [URL]) -> Void = { service, urls in
            NSApp.activate(ignoringOtherApps: true)
            service.perform(withItems: urls)
        },
        reportError: @escaping (Error) -> Void = { error in
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    ) {
        self.makeService = makeService
        self.perform = perform
        self.reportError = reportError
    }

    func present(_ urls: [URL]) async throws {
        guard session == nil else {
            throw NSError(
                domain: "Buckle.AirDrop", code: 2,
                userInfo: [NSLocalizedDescriptionKey: localized("airdrop.busy")])
        }
        guard let service = makeService() else {
            throw NSError(
                domain: "Buckle.AirDrop", code: 1,
                userInfo: [NSLocalizedDescriptionKey: localized("airdrop.unavailable")])
        }
        // FinderActionService serializes requests while file access is being prepared.
        try await Task.detached { try Self.requestFileAccess(urls) }.value
        try Task.checkCancellation()
        guard service.canPerform(withItems: urls) else {
            throw NSError(
                domain: "Buckle.AirDrop", code: 1,
                userInfo: [NSLocalizedDescriptionKey: localized("airdrop.unavailable")])
        }
        let session = AirDropSession(service: service) { [weak self] session, error in
            guard let self, self.session === session else { return }
            self.session = nil
            if let error, (error as? CocoaError)?.code != .userCancelled { self.reportError(error) }
        }
        self.session = session
        service.delegate = session
        logger.info("AirDrop perform begin; items=\(urls.count)")
        perform(service, urls)
        // Returning completes the shortcut request, not the file transfer.
        logger.info("AirDrop perform returned")
    }
    private nonisolated static func requestFileAccess(_ urls: [URL]) throws {
        // Capability checks only preflight protected folders; open the user-selected items first
        // so macOS can request file access instead of reporting AirDrop as unavailable.
        for url in urls {
            try url.withUnsafeFileSystemRepresentation { path in
                guard let path else { throw CocoaError(.fileReadInvalidFileName) }
                // O_NONBLOCK also prevents a selected FIFO from blocking the UI.
                let descriptor = Darwin.open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
                guard descriptor >= 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSURLErrorKey: url])
                }
                guard Darwin.close(descriptor) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSURLErrorKey: url])
                }
            }
        }
    }

}

@MainActor
private final class AirDropSession: NSObject, NSSharingServiceDelegate {
    private let service: NSSharingService
    private var completion: ((AirDropSession, Error?) -> Void)?
    private let logger = Logger(subsystem: "studio.slippindylan.Buckle", category: "AirDrop")

    init(service: NSSharingService, completion: @escaping (AirDropSession, Error?) -> Void) {
        self.service = service
        self.completion = completion
    }

    func sharingService(_ sharingService: NSSharingService, willShareItems items: [Any]) {
        logger.info("AirDrop willShare; items=\(items.count)")
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        logger.info("AirDrop didShare callback")
        finish(error: nil)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        let failure = error as NSError
        logger.error("AirDrop didFail; domain=\(failure.domain, privacy: .public) code=\(failure.code)")
        finish(error: error)
    }

    private func finish(error: Error?) {
        guard let completion else { return }
        self.completion = nil
        // AppKit can pass a different service wrapper; this delegate identifies the request.
        service.delegate = nil
        completion(self, error)
    }
}
