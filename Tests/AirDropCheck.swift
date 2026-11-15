import AppKit

@main
enum AirDropCheck {
    @MainActor static func main() throws {
        let service = makeService()
        let callbackService = makeService()
        var starts = 0
        var errors: [NSError] = []
        let controller = AirDropService(
            makeService: { service }, perform: { _, _ in starts += 1 },
            reportError: { errors.append($0 as NSError) })
        let urls = [URL(fileURLWithPath: "/tmp/example")]
        try controller.present(urls)
        precondition(starts == 1, "Presentation must return without an end callback")
        guard let firstDelegate = service.delegate else { preconditionFailure("Session delegate was not retained") }
        do {
            try controller.present(urls)
            preconditionFailure("A second sharing window was opened")
        } catch { precondition((error as NSError).code == 2) }
        precondition(starts == 1)

        // Real AirDrop callbacks can carry another wrapper, even when the original service is retained.
        firstDelegate.sharingService?(callbackService, didShareItems: [])
        precondition(service.delegate == nil)
        try controller.present(urls)
        guard let secondDelegate = service.delegate else { preconditionFailure("Second session was not retained") }
        precondition(firstDelegate !== secondDelegate)
        firstDelegate.sharingService?(
            callbackService, didFailToShareItems: [], error: CocoaError(.fileReadNoPermission))
        precondition(service.delegate === secondDelegate, "A late callback detached a newer session")
        precondition(errors.isEmpty)
        secondDelegate.sharingService?(callbackService, didFailToShareItems: [], error: CocoaError(.userCancelled))
        precondition(errors.isEmpty && service.delegate == nil)

        for error in [CocoaError(.fileReadNoPermission) as Error, NSError(domain: "Test", code: NSUserCancelledError)] {
            try controller.present(urls)
            guard let delegate = service.delegate else { preconditionFailure("Missing error delegate") }
            delegate.sharingService?(callbackService, didFailToShareItems: [], error: error)
            precondition(errors.last?.domain == (error as NSError).domain)
            precondition(errors.last?.code == (error as NSError).code)
            let count = errors.count
            delegate.sharingService?(callbackService, didFailToShareItems: [], error: error)
            precondition(errors.count == count, "Duplicate callback reported an error twice")
        }
        let synchronous = AirDropService(
            makeService: { service },
            perform: { service, _ in service.delegate?.sharingService?(callbackService, didShareItems: []) },
            reportError: { _ in preconditionFailure("Synchronous completion failed") })
        try synchronous.present(urls)
        try synchronous.present(urls)
        let unavailable = AirDropService(
            makeService: { nil }, perform: { _, _ in preconditionFailure("Unavailable service performed") })
        do {
            try unavailable.present(urls)
            preconditionFailure("Missing service must report failure")
        } catch { precondition((error as NSError).code == 1) }
        print(
            "AirDrop returns after presentation, blocks duplicate sessions, accepts wrapper callbacks, isolates late callbacks, and reports errors once."
        )
    }

    @MainActor private static func makeService() -> NSSharingService {
        NSSharingService(
            title: "Test", image: NSImage(size: NSSize(width: 1, height: 1)), alternateImage: nil, handler: {})
    }
}
