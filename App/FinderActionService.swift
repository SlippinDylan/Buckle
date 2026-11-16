import AppKit
import CryptoKit

@MainActor
final class FinderActionService {
    private static let moveRunner = FinderMoveRunner()
    private let lifecycle: ApplicationLifecycle
    private let airDrop: any AirDropPresenting
    private let openTerminal: (URL) async throws -> Void
    private let configuration: () throws -> FinderConfiguration
    private let moveKey: () throws -> SymmetricKey
    private let pasteboard: NSPasteboard
    private let createTextFile: @Sendable (FinderNewTextFileRequest, String) async throws -> URL
    private let revealFile: (URL) -> Void
    private let move: @MainActor (FinderMovePlan) async throws -> Void

    init(
        lifecycle: ApplicationLifecycle,
        airDrop: (any AirDropPresenting)? = nil,
        openTerminal: @escaping (URL) async throws -> Void = FinderActionService.launchTerminal,
        configuration: @escaping () throws -> FinderConfiguration = { try FinderConfigurationStore.standard().load() },
        pasteboard: NSPasteboard = .general,
        moveKey: @escaping () throws -> SymmetricKey = { try FinderConfigurationStore.standard().loadMoveKey() },
        move: @escaping @MainActor (FinderMovePlan) async throws -> Void = FinderActionService.performMove,
        createTextFile: @escaping @Sendable (FinderNewTextFileRequest, String) async throws -> URL = FinderActionService
            .createTextFile,
        revealFile: @escaping (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    ) {
        self.lifecycle = lifecycle
        self.airDrop =
            airDrop
            ?? AirDropService(reportError: { error in
                guard lifecycle.shouldPresentUserActionError(error) else { return }
                NSApp.activate()
                NSAlert(error: error).runModal()
            })
        self.openTerminal = openTerminal
        self.configuration = configuration
        self.pasteboard = pasteboard
        self.moveKey = moveKey
        self.move = move
        self.createTextFile = createTextFile
        self.revealFile = revealFile
    }

    func handle(_ request: FinderActionRequest) async throws {
        guard try configuration().isEnabled(request.action) else {
            throw CocoaError(
                .featureUnsupported,
                userInfo: request.action == .move
                    ? [
                        NSLocalizedDescriptionKey: localized("finder.move.disabled.title"),
                        NSLocalizedRecoverySuggestionErrorKey: localized("finder.move.disabled.help"),
                    ]
                    : [NSLocalizedDescriptionKey: localized("finder.action.disabled")])
        }
        guard !lifecycle.terminationRequested else { throw CocoaError(.userCancelled) }
        if request.action == .move {
            guard try request.authenticates(using: moveKey()) else {
                throw FinderActionRequest.RequestError.invalidRoute
            }
        }
        guard lifecycle.begin(.finderAction) else {
            throw NSError(
                domain: "Buckle.FinderAction", code: 1,
                userInfo: [NSLocalizedDescriptionKey: localized("finder.action.busy")])
        }
        defer { lifecycle.end(.finderAction) }
        switch request.action {
        case .airDrop:
            try await airDrop.present(request.files)
        case .terminal:
            guard let directory = try FinderMenuContext.items(request.files).directory() else {
                throw CocoaError(
                    .fileReadUnsupportedScheme,
                    userInfo: [NSLocalizedDescriptionKey: localized("finder.directory.required")])
            }
            try await openTerminal(directory)
        case .copyPath, .newTextFile:
            throw FinderActionRequest.RequestError.invalidRoute
        case .move:
            let clipboardChangeCount = pasteboard.changeCount
            guard request.clipboardChangeCount == clipboardChangeCount,
                let objects = pasteboard.readObjects(
                    forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]),
                let sources = objects as? [URL], !sources.isEmpty
            else {
                throw FinderMoveError.clipboardChanged
            }
            let plan = try FinderMovePlan(
                sources: sources, destination: request.files[0], clipboardChangeCount: clipboardChangeCount)
            try await move(plan)
        }
    }

    func handle(_ request: FinderNewTextFileRequest) async throws {
        guard try configuration().newTextFileEnabled else {
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
        let url = try await createTextFile(request, localized("finder.newTextFile.name"))
        revealFile(url)
    }

    nonisolated private static func createTextFile(_ request: FinderNewTextFileRequest, baseName: String) async throws
        -> URL
    {
        try await NewTextFileService.shared.create(
            request, baseName: baseName, store: FinderConfigurationStore.standard())
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
