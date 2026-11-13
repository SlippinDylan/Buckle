import AppKit

@main
enum AirDropCheck {
    @MainActor static func main() async throws {
        for error: Error? in [
            nil, CocoaError(.userCancelled), CocoaError(.fileReadNoPermission),
            NSError(domain: "Test", code: NSUserCancelledError),
        ] {
            let service = NSSharingService(
                title: "Test", image: NSImage(size: NSSize(width: 1, height: 1)), alternateImage: nil, handler: {})
            var started = false
            var finished = false
            let controller = AirDropService(makeService: { service }, perform: { _, _ in started = true })
            let sharing = Task { @MainActor in
                defer { finished = true }
                try await controller.sendFiles([URL(fileURLWithPath: "/tmp/example")])
            }
            while !started { await Task.yield() }
            precondition(!finished, "Starting AirDrop is not completion")
            if let error {
                controller.sharingService(service, didFailToShareItems: [], error: error)
            } else {
                controller.sharingService(service, didShareItems: [])
            }
            do {
                try await sharing.value
                precondition(error == nil || (error as? CocoaError)?.code == .userCancelled)
            } catch let actual {
                precondition((actual as NSError).domain == (error as NSError?)?.domain)
                precondition((actual as NSError).code == (error as NSError?)?.code)
            }
            precondition(finished)
            // Duplicate or late callbacks cannot resume a continuation twice.
            controller.sharingService(service, didShareItems: [])
        }
        let unavailable = AirDropService(
            makeService: { nil }, perform: { _, _ in preconditionFailure("Unavailable service performed") })
        do {
            try await unavailable.sendFiles([])
            preconditionFailure("Missing service must report failure")
        } catch { precondition((error as NSError).domain == "Buckle.AirDrop") }
        print(
            "AirDrop awaits completion, treats cancellation as normal, and propagates real failures without opening UI."
        )
    }
}
