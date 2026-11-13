import AppKit

@MainActor
final class FinderActionService {
    private static let moveRunner = FinderMoveRunner()
    private let lifecycle: ApplicationLifecycle
    private let airDrop: any AirDropSending
    private let openTerminal: (URL) async throws -> Void
    private let configuration: () throws -> FinderConfiguration
    private let pasteboard: NSPasteboard
    private let confirmMove: @MainActor (FinderMovePlan) -> Bool
    private let move: @MainActor (FinderMovePlan) async throws -> Void

    init(
        lifecycle: ApplicationLifecycle,
        airDrop: any AirDropSending = AirDropService(),
        openTerminal: @escaping (URL) async throws -> Void = FinderActionService.launchTerminal,
        configuration: @escaping () throws -> FinderConfiguration = { try FinderConfigurationStore.standard().load() },
        pasteboard: NSPasteboard = .general,
        confirmMove: @escaping @MainActor (FinderMovePlan) -> Bool = FinderMoveConfirmation.confirm,
        move: @escaping @MainActor (FinderMovePlan) async throws -> Void = FinderActionService.performMove
    ) {
        self.lifecycle = lifecycle
        self.airDrop = airDrop
        self.openTerminal = openTerminal
        self.configuration = configuration
        self.pasteboard = pasteboard
        self.confirmMove = confirmMove
        self.move = move
    }

    func handle(_ request: FinderActionRequest) async throws {
        guard try configuration().isEnabled(request.action) else {
            throw CocoaError(
                .featureUnsupported, userInfo: [NSLocalizedDescriptionKey: localized("finder.action.disabled")])
        }
        guard !lifecycle.terminationRequested else { throw CocoaError(.userCancelled) }
        guard lifecycle.begin(.finderAction) else {
            throw NSError(
                domain: "Buckle.FinderAction", code: 1,
                userInfo: [NSLocalizedDescriptionKey: localized("finder.action.busy")])
        }
        defer { lifecycle.end(.finderAction) }
        switch request.action {
        case .airDrop:
            try await airDrop.sendFiles(request.files)
        case .terminal:
            guard let directory = try FinderMenuContext.items(request.files).directory() else {
                throw CocoaError(
                    .fileReadUnsupportedScheme,
                    userInfo: [NSLocalizedDescriptionKey: localized("finder.directory.required")])
            }
            try await openTerminal(directory)
        case .copyPath:
            throw FinderActionRequest.RequestError.invalidRoute
        case .move:
            guard request.clipboardChangeCount == pasteboard.changeCount,
                let objects = pasteboard.readObjects(
                    forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
                let sources = objects as? [URL], !sources.isEmpty
            else {
                throw CocoaError(
                    .fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: localized("finder.move.clipboard.changed")])
            }
            let plan = try FinderMovePlan(sources: sources, destination: request.files[0])
            guard confirmMove(plan) else { return }
            guard !lifecycle.terminationRequested else { throw CocoaError(.userCancelled) }
            guard request.clipboardChangeCount == pasteboard.changeCount else {
                throw CocoaError(
                    .fileReadUnknown, userInfo: [NSLocalizedDescriptionKey: localized("finder.move.clipboard.changed")])
            }
            try await move(plan)
        }
    }

    private static func launchTerminal(_ directory: URL) async throws {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw CocoaError(
                .fileNoSuchFile, userInfo: [NSLocalizedDescriptionKey: localized("finder.terminal.missing")])
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        _ = try await NSWorkspace.shared.open([directory], withApplicationAt: terminal, configuration: configuration)
    }

    private static func performMove(_ plan: FinderMovePlan) async throws {
        try await moveRunner.move(plan)
    }
}
