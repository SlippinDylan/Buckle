import AppKit

@main
enum AirDropCheck {
    @MainActor static func main() {
        var errors: [NSError] = []
        let controller = AirDropService(presentError: { errors.append($0 as NSError) })
        let service = NSSharingService(
            title: "Test", image: NSImage(size: NSSize(width: 1, height: 1)), alternateImage: nil, handler: {})
        controller.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled))
        precondition(errors.isEmpty)
        controller.sharingService(
            service, didFailToShareItems: [], error: NSError(domain: "Test", code: NSUserCancelledError))
        controller.sharingService(service, didFailToShareItems: [], error: CocoaError(.fileReadNoPermission))
        precondition(errors.count == 2)
        precondition(errors[0].domain == "Test" && errors[1].code == CocoaError.fileReadNoPermission.rawValue)
        print("AirDrop cancellation and real failures verified without opening a sharing window.")
    }
}
