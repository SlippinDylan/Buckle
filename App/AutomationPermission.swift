import ApplicationServices
import Foundation
import Observation

enum AutomationTarget: String, CaseIterable, Sendable {
    case finder = "com.apple.finder"
    case systemEvents = "com.apple.systemevents"

    var title: String {
        switch self {
        case .finder: localized("permissions.finderAutomation.title")
        case .systemEvents: localized("permissions.systemEvents.title")
        }
    }

    func permissionGranted(requestPermission: Bool) throws -> Bool {
        var target = AEAddressDesc()
        let result = rawValue.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, rawValue.utf8.count, &target)
        }
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        defer { AEDisposeDesc(&target) }
        return try Self.isGranted(
            AEDeterminePermissionToAutomateTarget(
                &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), requestPermission))
    }

    static func isGranted(_ status: OSStatus) throws -> Bool {
        switch status {
        case noErr: return true
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return false
        default: throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

enum PermissionRequirement: LocalizedError {
    case accessibility
    case automation(AutomationTarget)

    var errorDescription: String? {
        switch self {
        case .accessibility: localized("finder.move.accessibility.required")
        case .automation(let target): localizedFormat("permissions.automation.required", target.title)
        }
    }
}

// The permission API can block and must not run on the UI thread.
actor AutomationPermissionProbe {
    static let shared = AutomationPermissionProbe()
    func granted(_ target: AutomationTarget, requestPermission: Bool) async throws -> Bool {
        try target.permissionGranted(requestPermission: requestPermission)
    }
}

@MainActor @Observable
final class FinderAutomationPermission {
    enum State: Equatable {
        case unchecked, checking, granted, required
        case failed(String)
    }

    private(set) var state: State = .unchecked
    @ObservationIgnored private var checkTask: (requestsPermission: Bool, task: Task<Void, Error>)?
    private let query: @MainActor (Bool) async throws -> Bool

    init(
        query: @escaping @MainActor (Bool) async throws -> Bool = {
            try await AutomationPermissionProbe.shared.granted(.finder, requestPermission: $0)
        }
    ) {
        self.query = query
    }

    // Silent checks expose errors through state; explicit requests also throw to their caller.
    func refresh() async { try? await check(requestPermission: false) }

    func request() async throws {
        try await check(requestPermission: true)
    }

    private func check(requestPermission: Bool) async throws {
        if let checkTask {
            if requestPermission && !checkTask.requestsPermission {
                // Explicit authorization follows a silent query, even when that query failed.
                _ = await checkTask.task.result
                try Task.checkCancellation()
                try await check(requestPermission: true)
                return
            }
            try await checkTask.task.value
            return
        }
        try Task.checkCancellation()
        state = .checking
        let task = Task {
            defer { checkTask = nil }
            do {
                state = try await query(requestPermission) ? .granted : .required
            } catch {
                state = .failed(error.localizedDescription)
                throw error
            }
        }
        checkTask = (requestPermission, task)
        try await task.value
    }
}
