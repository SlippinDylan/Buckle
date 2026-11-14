import AppKit
import ApplicationServices
import Observation

@MainActor
protocol SystemMemoryPanelOperations {
    func debugValue() -> CFPropertyList?
    func setDebugValue(_ value: CFPropertyList?) throws
    func permissions(requestPermission: Bool) async throws -> MemoryPanelPermissions
    func trigger() async throws
}

struct MemoryPanelPermissions {
    let accessibilityGranted: Bool
    let automationGranted: Bool

    var issue: MemoryPanelPermissionIssue? {
        if !accessibilityGranted { return .accessibility }
        return automationGranted ? nil : .automation
    }
}

enum MemoryPanelPermissionStatus {
    case unchecked, granted
    case required(MemoryPanelPermissionIssue)
    case failed(String)
}

enum MemoryPanelPermissionIssue {
    case accessibility, automation

    var message: String {
        switch self {
        case .accessibility: localized("memory.access.required")
        case .automation: localized("memory.automation.required")
        }
    }

}

// The journal must reach disk before loginwindow preferences change, and survive failed restoration.
struct MemoryPanelRecoveryStore {
    let directory: URL
    private var file: URL { directory.appendingPathComponent("pending.plist") }

    struct Snapshot {
        let original: CFPropertyList?
    }

    func save(original: CFPropertyList?) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var contents: [String: Any] = [:]
        if let original { contents["original"] = original }
        let data = try PropertyListSerialization.data(fromPropertyList: contents, format: .binary, options: 0)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func load() throws -> Snapshot? {
        let data: Data
        do { data = try Data(contentsOf: file) } catch CocoaError.fileReadNoSuchFile { return nil }
        guard
            let contents = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                as? [String: Any], Set(contents.keys).isSubset(of: ["original"])
        else { throw CocoaError(.propertyListReadCorrupt) }
        return Snapshot(original: contents["original"] as CFPropertyList?)
    }

    func remove() throws {
        try FileManager.default.removeItem(at: file)
    }
}

@MainActor @Observable
final class SystemMemoryPanel {
    var isOpening: Bool { lifecycle.isActive(.memoryPanel) }
    var isCheckingPermissions: Bool { lifecycle.isActive(.memoryPermissions) }
    var canOpen: Bool {
        // Background checks can be awaited; a foreground authorization must finish before another user action.
        !lifecycle.terminationRequested && !isOpening && (!isCheckingPermissions || permissionCheck != nil)
    }
    private(set) var permissionStatus: MemoryPanelPermissionStatus = .unchecked
    private(set) var automationGranted: Bool?
    var permissionIssue: MemoryPanelPermissionIssue? {
        if case .required(let issue) = permissionStatus { return issue }
        return nil
    }
    var permissionError: String? {
        if case .failed(let message) = permissionStatus { return message }
        return nil
    }
    var error: String?
    @ObservationIgnored private let operations: any SystemMemoryPanelOperations
    @ObservationIgnored private let recovery: MemoryPanelRecoveryStore
    @ObservationIgnored private let lifecycle: ApplicationLifecycle
    @ObservationIgnored private var permissionCheck: Task<Void, Never>?

    init(
        operations: any SystemMemoryPanelOperations = NativeMemoryPanelOperations(),
        lifecycle: ApplicationLifecycle = ApplicationLifecycle(),
        recovery: MemoryPanelRecoveryStore = MemoryPanelRecoveryStore(
            directory: URL.applicationSupportDirectory.appending(path: "Buckle/MemoryPanel"))
    ) {
        self.operations = operations
        self.lifecycle = lifecycle
        self.recovery = recovery
    }

    func recover() throws {
        if let snapshot = try recovery.load() {
            try operations.setDebugValue(snapshot.original)
            try recovery.remove()
        }
    }

    func showRecoveryRecord() {
        NSWorkspace.shared.activateFileViewerSelecting([recovery.directory])
    }

    func refreshPermissions() async {
        guard !isOpening, permissionCheck == nil, lifecycle.begin(.memoryPermissions) else { return }
        let check = Task { @MainActor in
            defer {
                permissionCheck = nil
                lifecycle.end(.memoryPermissions)
            }
            do {
                let permissions = try await operations.permissions(requestPermission: false)
                recordPermissions(permissions)
            } catch {
                permissionStatus = .failed(error.localizedDescription)
                automationGranted = nil
            }
        }
        permissionCheck = check
        await check.value
    }

    func requestAutomationPermission() async throws {
        if let permissionCheck { await permissionCheck.value }
        guard !isOpening, lifecycle.begin(.memoryPermissions) else { throw CocoaError(.userCancelled) }
        defer { lifecycle.end(.memoryPermissions) }
        do {
            let permissions = try await operations.permissions(requestPermission: true)
            guard !lifecycle.terminationRequested else { throw CocoaError(.userCancelled) }
            recordPermissions(permissions)
        } catch {
            guard !lifecycle.terminationRequested else { throw CocoaError(.userCancelled) }
            permissionStatus = .failed(error.localizedDescription)
            automationGranted = nil
            throw error
        }
    }

    private func recordPermissions(_ permissions: MemoryPanelPermissions) {
        permissionStatus = permissions.issue.map { .required($0) } ?? .granted
        automationGranted = permissions.automationGranted
    }

    func show(requestPermission: Bool) async throws -> Bool {
        guard canOpen, lifecycle.begin(.memoryPanel) else { return false }
        defer { lifecycle.end(.memoryPanel) }
        // Reserve the user's request before waiting; additional clicks coalesce into this opening.
        if let permissionCheck { await permissionCheck.value }
        guard !lifecycle.terminationRequested else { return false }
        error = nil
        try recover()
        permissionStatus = .unchecked
        let permissions: MemoryPanelPermissions
        do {
            permissions = try await operations.permissions(requestPermission: requestPermission)
        } catch {
            guard !lifecycle.terminationRequested else { return false }
            throw error
        }
        // Authorization can outlive a quit request; no new work may start after it returns.
        guard !lifecycle.terminationRequested else { return false }
        recordPermissions(permissions)
        guard permissions.issue == nil else { return false }
        try recovery.save(original: operations.debugValue())
        var triggerError: Error?
        do {
            try operations.setDebugValue(kCFBooleanTrue)
            try await operations.trigger()
        } catch {
            triggerError = error
        }
        do {
            try recover()
        } catch {
            let context = [triggerError, error].compactMap { $0?.localizedDescription }.joined(separator: "\n")
            throw NSError(
                domain: "Buckle.MemoryPanel", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: localized("memory.restore.failed") + "\n" + context,
                    NSUnderlyingErrorKey: error,
                ])
        }
        if let triggerError { throw triggerError }
        return true
    }
}

@MainActor
private final class NativeMemoryPanelOperations: SystemMemoryPanelOperations {
    private let key = "DebugShowLowMemoryPanel" as CFString
    private let domain = "com.apple.loginwindow" as CFString
    private let runner = MemoryPanelTrigger()

    func debugValue() -> CFPropertyList? {
        CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    }

    func setDebugValue(_ value: CFPropertyList?) throws {
        // This private loginwindow flag was verified locally; preserve its exact previous value.
        CFPreferencesSetValue(key, value, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw NSError(
                domain: "Buckle.MemoryPanel", code: 1,
                userInfo: [NSLocalizedDescriptionKey: localized("memory.preference.failed")])
        }
    }

    func permissions(requestPermission: Bool) async throws -> MemoryPanelPermissions {
        // Accessibility guidance is owned by PermissionFlow, not an additional system trust prompt.
        let accessibility = AXIsProcessTrusted()
        try await ensureSystemEventsRunning()
        let automation = try await runner.automationPermissionIssue(requestPermission: requestPermission) == nil
        return MemoryPanelPermissions(accessibilityGranted: accessibility, automationGranted: automation)
    }

    private func ensureSystemEventsRunning() async throws {
        // Apple's permission API requires a running target; System Events is a background system app.
        if NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemevents").isEmpty {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            _ = try await NSWorkspace.shared.openApplication(
                at: URL(fileURLWithPath: "/System/Library/CoreServices/System Events.app"), configuration: configuration
            )
        }
    }

    func trigger() async throws {
        let messages = try MemoryPanelWindowVerification.warningMessages(
            resources: URL(fileURLWithPath: "/System/Library/CoreServices/loginwindow.app/Contents/Resources"))
        // Do not toggle a panel that is already open. The warning distinguishes it from ForceQuitPanel.
        if try await runner.isPanelVisible(
            warningMessages: messages, deadline: .now.advanced(by: .seconds(1)))
        {
            return
        }
        // Allow loginwindow to observe the synchronized preference before it handles the shortcut.
        try await Task.sleep(for: .seconds(1))
        try await runner.trigger()
        try await MemoryPanelWindowVerification.wait { deadline in
            try await self.runner.isPanelVisible(warningMessages: messages, deadline: deadline)
        }
    }
}

@MainActor
enum MemoryPanelWindowVerification {
    static func warningMessages(resources: URL) throws -> Set<String> {
        // This is part of the private loginwindow integration. Read its own translations so app
        // language overrides cannot make us confuse LowMemoryPanel with the ordinary Force Quit panel.
        let key = "100009.title"
        var messages = Set<String>()
        let table = resources.appendingPathComponent("LowMemoryPanel.loctable")
        do {
            let data = try Data(contentsOf: table)
            guard let languages = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { throw CocoaError(.propertyListReadCorrupt) }
            for value in languages.values {
                if let translation = value as? [String: Any], let text = translation[key] as? String, !text.isEmpty {
                    messages.insert(text)
                }
            }
        } catch CocoaError.fileReadNoSuchFile {
            // Older loginwindow bundles use separate strings files instead of a shared loctable.
            for directory in try FileManager.default.contentsOfDirectory(at: resources, includingPropertiesForKeys: nil)
            where directory.pathExtension == "lproj" {
                let data: Data
                do {
                    data = try Data(contentsOf: directory.appendingPathComponent("LowMemoryPanel.strings"))
                } catch CocoaError.fileReadNoSuchFile { continue }
                guard
                    let translations = try PropertyListSerialization.propertyList(from: data, format: nil)
                        as? [String: String]
                else { throw CocoaError(.propertyListReadCorrupt) }
                if let text = translations[key], !text.isEmpty { messages.insert(text) }
            }
        }
        guard !messages.isEmpty else {
            throw NSError(
                domain: "Buckle.MemoryPanel", code: 3,
                userInfo: [NSLocalizedDescriptionKey: localized("memory.unsupported")])
        }
        return messages
    }

    static func wait(
        timeout: Duration = .seconds(10),
        isVisible: (ContinuousClock.Instant) async throws -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            try checkDeadline(deadline)
            let visible = try await isVisible(deadline)
            try Task.checkCancellation()
            try checkDeadline(deadline)
            if visible { return }
            try await Task.sleep(until: min(.now.advanced(by: .milliseconds(100)), deadline), clock: .continuous)
        }
    }

    private static func checkDeadline(_ deadline: ContinuousClock.Instant) throws {
        guard ContinuousClock.now < deadline else {
            throw NSError(
                domain: "Buckle.MemoryPanel", code: 4,
                userInfo: [NSLocalizedDescriptionKey: localized("memory.not.visible")])
        }
    }
}

private actor MemoryPanelTrigger {
    func isPanelVisible(warningMessages: Set<String>, deadline: ContinuousClock.Instant) async throws -> Bool {
        let scanDeadline = min(deadline, .now.advanced(by: .seconds(1)))
        let pids = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.loginwindow").map(
                \.processIdentifier)
        }
        for pid in pids {
            try Task.checkCancellation()
            guard ContinuousClock.now < scanDeadline else { return false }
            let application = AXUIElementCreateApplication(pid)
            guard
                let windows = try attribute(kAXWindowsAttribute, of: application, deadline: scanDeadline)
                    as? [AXUIElement]
            else { continue }
            // Breadth-first traversal reaches the warning before potentially large application tables.
            var elements = windows
            var index = 0
            while index < elements.count, ContinuousClock.now < scanDeadline {
                let element = elements[index]
                index += 1
                if let role = try attribute(kAXRoleAttribute, of: element, deadline: scanDeadline) as? String,
                    role == kAXStaticTextRole,
                    let text = try attribute(kAXValueAttribute, of: element, deadline: scanDeadline) as? String,
                    warningMessages.contains(text)
                {
                    return true
                }
                if let children = try attribute(kAXChildrenAttribute, of: element, deadline: scanDeadline)
                    as? [AXUIElement]
                {
                    elements.append(contentsOf: children)
                }
            }
        }
        return false
    }

    private func attribute(_ name: String, of element: AXUIElement, deadline: ContinuousClock.Instant) throws
        -> CFTypeRef?
    {
        try Task.checkCancellation()
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { return nil }
        let components = remaining.components
        let seconds = Float(components.seconds) + Float(components.attoseconds) / 1e18
        // AX timeouts belong to individual objects, not the application or its descendants.
        let timeoutResult = AXUIElementSetMessagingTimeout(element, min(0.25, seconds))
        guard timeoutResult == .success else { throw accessibilityError(timeoutResult) }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { return nil }
        switch result {
        case .success: return value
        // Unsupported values are normal; stale or temporarily unresponsive windows are retried by the poll.
        case .attributeUnsupported, .noValue, .invalidUIElement, .cannotComplete: return nil
        default: throw accessibilityError(result)
        }
    }

    private func accessibilityError(_ result: AXError) -> NSError {
        NSError(
            domain: "Buckle.MemoryPanel.Accessibility", code: Int(result.rawValue),
            userInfo: [
                NSLocalizedDescriptionKey: result == .apiDisabled
                    ? localized("memory.access.required")
                    : localized("memory.not.visible") + " (AXError \(result.rawValue))"
            ])
    }

    func automationPermissionIssue(requestPermission: Bool) throws -> MemoryPanelPermissionIssue? {
        var target = AEAddressDesc()
        let identifier = "com.apple.systemevents"
        let result = identifier.withCString {
            AECreateDesc(DescType(typeApplicationBundleID), $0, identifier.utf8.count, &target)
        }
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        defer { AEDisposeDesc(&target) }
        let permission = AEDeterminePermissionToAutomateTarget(
            &target, AEEventClass(typeWildCard), AEEventID(typeWildCard), requestPermission)
        switch permission {
        case noErr: return nil
        case OSStatus(errAEEventNotPermitted), OSStatus(errAEEventWouldRequireUserConsent): return .automation
        default: throw NSError(domain: NSOSStatusErrorDomain, code: Int(permission))
        }
    }

    func trigger() throws {
        let reply = try MemoryPanelShortcut.event().sendEvent(options: MemoryPanelShortcut.sendOptions, timeout: 10)
        if let code = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber))?.int32Value, code != 0 {
            let message =
                reply.paramDescriptor(forKeyword: AEKeyword(keyErrorString))?.stringValue
                ?? NSError(domain: NSOSStatusErrorDomain, code: Int(code)).localizedDescription
            throw NSError(
                domain: "Buckle.MemoryPanel", code: Int(code), userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

// These event and modifier codes come from System Events' scripting dictionary, not private loginwindow APIs.
enum MemoryPanelShortcut {
    static let sendOptions: NSAppleEventDescriptor.SendOptions = [
        .waitForReply, .neverInteract,
        NSAppleEventDescriptor.SendOptions(rawValue: UInt(kAEDoNotPromptForUserConsent)),
    ]

    static func event() -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(
            eventClass: 0x7072_6373, eventID: 0x6b63_6f64,  // prcs / kcod: key code
            targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.systemevents"),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(int32: 53), forKeyword: AEKeyword(keyDirectObject))
        let modifiers = NSAppleEventDescriptor.list()
        modifiers.insert(NSAppleEventDescriptor(enumCode: 0x4b63_6d64), at: 1)  // Kcmd: command down
        modifiers.insert(NSAppleEventDescriptor(enumCode: 0x4b6f_7074), at: 2)  // Kopt: option down
        event.setParam(modifiers, forKeyword: 0x6661_616c)  // faal: using
        return event
    }
}
