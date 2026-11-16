import AppKit

extension FinderAction {
    func menuImage(in bundle: Bundle = .main) -> NSImage? {
        let name: String
        switch self {
        case .airDrop: return NSSharingService(named: .sendViaAirDrop)?.image
        case .terminal: name = "finder-open-in-terminal"
        case .copyPath: name = "finder-copy-path"
        case .move: name = "finder-move-items-here"
        case .newTextFile: name = "finder-new-text-file"
        }
        // Keep menu sizing local; named images can be shared by the resource cache.
        guard let image = bundle.image(forResource: name)?.copy() as? NSImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = false
        return image
    }
}
