import AppKit

@main
enum FinderMenuIconCheck {
    static func main() {
        guard CommandLine.arguments.count == 2,
            let bundle = Bundle(url: URL(filePath: CommandLine.arguments[1]))
        else { preconditionFailure("Missing compiled icon bundle") }
        let icons: [(FinderAction, String)] = [
            (.terminal, "finder-open-in-terminal"), (.copyPath, "finder-copy-path"),
            (.move, "finder-move-items-here"), (.newTextFile, "finder-new-text-file"),
        ]
        for (action, name) in icons {
            guard let original = bundle.image(forResource: name) else {
                preconditionFailure("Xcode did not compile the named icon: \(name)")
            }
            let originalSize = original.size
            guard let menuImage = action.menuImage(in: bundle) else {
                preconditionFailure("The menu cannot load its icon: \(name)")
            }
            precondition(menuImage.isValid && !menuImage.isTemplate)
            precondition(menuImage.size == NSSize(width: 16, height: 16))
            precondition(menuImage !== original && original.size == originalSize)
        }
        print("Four Icon Composer resources compile and load as color menu images without PNG exports.")
    }
}
