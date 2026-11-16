import AppKit
import Observation
import os

private final class DockClickMailbox: Sendable {
    struct State: Sendable {
        var click = DockClickState()
        var generation = 0
        var lastSample: DockTileSnapshot?
    }
    let state = OSAllocatedUnfairLock(initialState: State())
}

@MainActor @Observable
final class DockMiddleClickController {
    enum Status: Equatable {
        case disabled, accessibilityRequired, inputMonitoringRequired, unavailable, running, suspended, quitRejected
        var title: String {
            switch self {
            case .disabled: localized("dock.status.disabled")
            case .accessibilityRequired: localized("dock.status.accessibility")
            case .inputMonitoringRequired: localized("dock.status.input.monitoring")
            case .unavailable: localized("dock.status.unavailable")
            case .running: localized("dock.status.running")
            case .suspended: localized("dock.status.suspended")
            case .quitRejected: localized("dock.status.quit.rejected")
            }
        }
    }

    private(set) var isEnabled: Bool
    private(set) var quitAction: DockQuitAction
    private(set) var status: Status = .disabled
    private var isListening: Bool { status == .running || status == .quitRejected }
    var isDrained: Bool { mailbox.state.withLock { $0.click.isDrained } }
    @ObservationIgnored var onDrained: (() -> Void)?
    @ObservationIgnored private let lifecycle: ApplicationLifecycle
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let accessibilityGranted: () -> Bool
    @ObservationIgnored private let inputMonitoringGranted: () -> Bool
    @ObservationIgnored private let createTap: (CGEventMask, CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort?
    @ObservationIgnored private let mailbox = DockClickMailbox()
    @ObservationIgnored private let worker = DispatchQueue(label: "studio.slippindylan.Buckle.dock-snapshots")
    @ObservationIgnored private var timer: DispatchSourceTimer?
    @ObservationIgnored private var healthTimer: Timer?
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var suspended = false
    @ObservationIgnored private var dockPID: pid_t?
    @ObservationIgnored private var isConfirming = false
    @ObservationIgnored private let confirmation: any DockQuitConfirming
    private static let preferenceKey = "dock.middleClick.enabled"
    private static let actionPreferenceKey = "dock.middleClick.action"

    init(
        lifecycle: ApplicationLifecycle, defaults: UserDefaults = .standard,
        accessibilityGranted: @escaping () -> Bool = { AXIsProcessTrusted() },
        inputMonitoringGranted: @escaping () -> Bool = { CGPreflightListenEventAccess() },
        confirmation: any DockQuitConfirming = DockForceQuitConfirmation(),
        createTap: @escaping (CGEventMask, CGEventTapCallBack, UnsafeMutableRawPointer) -> CFMachPort? = {
            CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: $0, callback: $1, userInfo: $2)
        }
    ) {
        self.lifecycle = lifecycle
        self.defaults = defaults
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.createTap = createTap
        self.confirmation = confirmation
        isEnabled = defaults.bool(forKey: Self.preferenceKey)
        quitAction =
            defaults.string(forKey: Self.actionPreferenceKey).flatMap(DockQuitAction.init(rawValue:)) ?? .normal
    }

    private func beginObserving() {
        guard observers.isEmpty else { return }
        let notifications: [(NotificationCenter, Notification.Name)] = [
            (.default, NSApplication.didChangeScreenParametersNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.willSleepNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didLaunchApplicationNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didTerminateApplicationNotification),
        ]
        for (center, name) in notifications {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.invalidateCandidates()
                        if name == NSWorkspace.willSleepNotification {
                            self?.status = .unavailable
                            self?.stopAccepting()
                        } else {
                            self?.refresh()
                        }
                    }
                })
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.preferenceKey)
        // A cancelled application quit can resume the service via an explicit settings action.
        if !lifecycle.terminationRequested { suspended = false }
        refresh()
    }

    func suspend() {
        suspended = true
        confirmation.cancel()
        refresh()
    }

    func setQuitAction(_ action: DockQuitAction) {
        guard !lifecycle.terminationRequested else { return }
        quitAction = action
        defaults.set(action.rawValue, forKey: Self.actionPreferenceKey)
        invalidateCandidates()
        refresh()
    }

    func resume() {
        guard !lifecycle.terminationRequested else { return }
        suspended = false
        refresh()
    }

    func refresh() {
        beginObserving()
        let desired: Status
        if suspended || lifecycle.terminationRequested {
            desired = .suspended
        } else if !isEnabled {
            desired = .disabled
        } else if !accessibilityGranted() {
            desired = .accessibilityRequired
        } else {
            desired = .running
        }
        // A disabled filter cannot deliver a captured release, including while draining on quit.
        if let tap, !accessibilityGranted() || !CGEvent.tapIsEnabled(tap: tap) {
            failTap()
            if desired != .running { status = desired }
            return
        }
        guard desired == .running else {
            status = desired
            stopAccepting()
            return
        }
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier
        if dockPID != pid {
            dockPID = pid
            invalidateCandidates()
        }
        if tap == nil, !startTap() {
            status = inputMonitoringGranted() ? .unavailable : .inputMonitoringRequired
            return
        }
        if status != .quitRejected { status = .running }
        reconcileCancelledRelease()
        let accepting = !isConfirming
        mailbox.state.withLock { $0.click.accepting = accepting }
        startSampling()
    }

    private func startTap() -> Bool {
        let mask = [CGEventType.otherMouseDown, .otherMouseUp, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard
            let created = createTap(
                mask,
                { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    // This source is installed only on the main run loop. No AX IPC runs here.
                    let point = event.location
                    let button = event.getIntegerValueField(.mouseEventButtonNumber)
                    let consume = MainActor.assumeIsolated {
                        let owner = Unmanaged<DockMiddleClickController>.fromOpaque(context).takeUnretainedValue()
                        return owner.receive(type, point: point, button: button)
                    }
                    return consume ? nil : Unmanaged.passUnretained(event)
                }, Unmanaged.passUnretained(self).toOpaque())
        else { return false }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        tap = created
        source = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        healthTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        return true
    }

    private func receive(_ type: CGEventType, point: CGPoint, button: Int64) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            mailbox.state.withLock {
                $0.click.invalidate()
                $0.generation += 1
                $0.lastSample = nil
            }
            DispatchQueue.main.async { [weak self] in self?.failTap() }
            return false
        }
        guard button == 2 else {
            return false
        }
        let kind: DockClickState.Event
        switch type {
        case .otherMouseDown: kind = .down
        case .otherMouseDragged: kind = .drag
        case .otherMouseUp: kind = .up
        default: return false
        }
        let (result, generation) = mailbox.state.withLock { state in
            (state.click.handle(kind, point: point, time: ProcessInfo.processInfo.systemUptime), state.generation)
        }
        if let identity = result.application {
            DispatchQueue.main.async { [weak self] in
                self?.validateAndQuit(identity, point: point, generation: generation)
            }
        }
        if kind == .up, result.consume {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if !isListening { removeTapIfDrained() }
                if isDrained { onDrained?() }
            }
        }
        return result.consume
    }

    private func validateAndQuit(_ identity: DockApplicationIdentity, point: CGPoint, generation: Int) {
        guard isListening, !isConfirming, !lifecycle.terminationRequested else { return }
        let action = quitAction
        let mailbox = mailbox
        worker.async { [weak self] in
            guard let verified = Self.snapshot(at: point), verified.application == identity else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, isListening, !isConfirming, quitAction == action,
                    !lifecycle.terminationRequested,
                    accessibilityGranted(), let tap, CGEvent.tapIsEnabled(tap: tap),
                    verified.contains(point, at: ProcessInfo.processInfo.systemUptime),
                    mailbox.state.withLock({ state in
                        state.generation == generation && state.click.accepting
                            && state.click.snapshot?.application == identity
                            && state.click.snapshot?.frame == verified.frame
                    }),
                    let app = NSRunningApplication(processIdentifier: identity.processIdentifier),
                    Self.identity(of: app) == identity
                else { return }
                requestQuit(
                    action, name: app.localizedName ?? identity.bundleURL.deletingPathExtension().lastPathComponent,
                    isValid: {
                        self.isListening && !self.lifecycle.terminationRequested && self.quitAction == action
                            && self.accessibilityGranted() && CGEvent.tapIsEnabled(tap: tap)
                            && mailbox.state.withLock { $0.generation == generation }
                            && Self.identity(of: app) == identity
                    }, normal: { app.terminate() || app.isTerminated },
                    force: { app.forceTerminate() || app.isTerminated })
            }
        }
    }

    func requestQuit(
        _ action: DockQuitAction, name: String, isValid: @escaping () -> Bool,
        normal: @escaping () -> Bool, force: @escaping () -> Bool
    ) {
        guard !isConfirming, !lifecycle.terminationRequested, quitAction == action else { return }
        let finish: (Bool) -> Void = { [weak self] confirmed in
            guard let self else { return }
            isConfirming = false
            let requested = action.request(
                confirmForce: { confirmed },
                isValid: { !self.lifecycle.terminationRequested && self.quitAction == action && isValid() },
                normal: normal, force: force)
            if let requested { status = requested ? .running : .quitRejected }
            refresh()
        }
        if action == .force {
            isConfirming = true
            mailbox.state.withLock { $0.click.cancel() }
            confirmation.present(name: name, completion: finish)
        } else {
            finish(true)
        }
    }

    private func startSampling() {
        guard timer == nil else { return }
        let mailbox = mailbox
        var displayCount: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &displayCount)
        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount)
        let displays = displayIDs.prefix(Int(displayCount)).map { CGDisplayBounds($0) }
        let timer = DispatchSource.makeTimerSource(queue: worker)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler {
            let generation = mailbox.state.withLock { $0.generation }
            let point = CGEvent(source: nil)?.location
            // Avoid AX IPC for ordinary pointer movement away from every display edge.
            let nearEdge =
                point.map { point in
                    displays.contains { $0.contains(point) && !$0.insetBy(dx: 300, dy: 300).contains(point) }
                } ?? false
            let snapshot = nearEdge ? Self.snapshot(at: point) : nil
            mailbox.state.withLock { state in
                if state.generation == generation && state.click.accepting {
                    let stable =
                        snapshot.map { next in
                            state.lastSample.map {
                                $0.application == next.application && $0.frame == next.frame
                                    && next.sampledAt - $0.sampledAt <= 0.15
                            } ?? false
                        } ?? false
                    state.click.snapshot = stable ? snapshot : nil
                    state.lastSample = snapshot
                }
            }
        }
        self.timer = timer
        timer.resume()
    }

    private func invalidateCandidates() {
        timer?.cancel()
        timer = nil
        mailbox.state.withLock { state in
            let accepting = state.click.accepting
            state.click.cancel()
            state.click.accepting = accepting
            state.generation += 1
            state.lastSample = nil
        }
    }

    private func stopAccepting() {
        mailbox.state.withLock {
            $0.click.cancel()
            $0.generation += 1
            $0.lastSample = nil
        }
        timer?.cancel()
        timer = nil
        reconcileCancelledRelease()
        removeTapIfDrained()
    }

    private func reconcileCancelledRelease() {
        // Include synthesized session events, not only physical mouse hardware.
        let isDown =
            CGEventSource.buttonState(.combinedSessionState, button: .center)
            || CGEventSource.buttonState(.hidSystemState, button: .center)
        let drained = mailbox.state.withLock {
            $0.click.reconcileCancelledRelease(buttonIsDown: isDown, time: ProcessInfo.processInfo.systemUptime)
        }
        if drained { onDrained?() }
    }

    private func removeTapIfDrained() {
        guard isDrained else { return }
        healthTimer?.invalidate()
        healthTimer = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func failTap() {
        mailbox.state.withLock {
            $0.click.invalidate()
            $0.generation += 1
            $0.lastSample = nil
        }
        status = .unavailable
        timer?.cancel()
        timer = nil
        removeTapIfDrained()
        onDrained?()
    }

    nonisolated private static func identity(of app: NSRunningApplication) -> DockApplicationIdentity? {
        guard app.activationPolicy == .regular, !app.isTerminated,
            app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
            let identifier = app.bundleIdentifier, identifier != Bundle.main.bundleIdentifier,
            !["com.apple.finder", "com.apple.dock", "com.apple.WindowManager"].contains(identifier),
            let date = app.launchDate, let url = app.bundleURL
        else { return nil }
        return DockApplicationIdentity(
            processIdentifier: app.processIdentifier, launchDate: date,
            bundleURL: url.standardizedFileURL.resolvingSymlinksInPath())
    }

    nonisolated private static func snapshot(at point: CGPoint?) -> DockTileSnapshot? {
        guard AXIsProcessTrusted(), let point else { return nil }
        let sampledAt = ProcessInfo.processInfo.systemUptime
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        // Only a system-wide hit test respects windows from other apps covering the Dock.
        // Do not set its timeout: that would mutate every AX call in this process.
        let system = AXUIElementCreateSystemWide()
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
            var element = hit
        else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid == dock.processIdentifier else { return nil }
        for _ in 0..<5 {
            AXUIElementSetMessagingTimeout(element, 0.05)
            if attribute(kAXSubroleAttribute, of: element) as? String == kAXApplicationDockItemSubrole {
                guard let url = attribute(kAXURLAttribute, of: element) as? URL, url.isFileURL,
                    let position = attribute(kAXPositionAttribute, of: element),
                    CFGetTypeID(position) == AXValueGetTypeID(),
                    let size = attribute(kAXSizeAttribute, of: element), CFGetTypeID(size) == AXValueGetTypeID()
                else { return nil }
                var origin = CGPoint.zero
                var dimensions = CGSize.zero
                guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
                    AXValueGetValue(size as! AXValue, .cgSize, &dimensions)
                else { return nil }
                let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
                let candidates = NSWorkspace.shared.runningApplications.compactMap { identity(of: $0) }
                    .filter { $0.bundleURL == canonical }
                guard candidates.count == 1 else { return nil }
                let snapshot = DockTileSnapshot(
                    application: candidates[0], frame: CGRect(origin: origin, size: dimensions), sampledAt: sampledAt)
                return snapshot.contains(point, at: ProcessInfo.processInfo.systemUptime) ? snapshot : nil
            }
            guard let parent = attribute(kAXParentAttribute, of: element),
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            element = parent as! AXUIElement
        }
        return nil
    }

    nonisolated private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}

@MainActor
protocol DockQuitConfirming {
    func present(name: String, completion: @escaping (Bool) -> Void)
    func cancel()
}

// Own this alert's window and completion; never abort another feature's modal session.
@MainActor
final class DockForceQuitConfirmation: NSObject, DockQuitConfirming, NSWindowDelegate {
    private var alert: NSAlert?
    private var completion: ((Bool) -> Void)?

    func present(name: String, completion: @escaping (Bool) -> Void) {
        precondition(alert == nil)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = localizedFormat("dock.force.confirm.title", name)
        alert.informativeText = localized("dock.force.confirm.help")
        let force = alert.addButton(withTitle: localized("dock.quit.force.button"))
        let cancel = alert.addButton(withTitle: localized("cancel"))
        alert.layout()
        force.target = self
        force.action = #selector(confirm)
        force.keyEquivalent = ""
        cancel.target = self
        cancel.action = #selector(dismiss)
        cancel.keyEquivalent = "\u{1b}"
        alert.window.defaultButtonCell = nil
        alert.window.delegate = self
        alert.window.isReleasedWhenClosed = false
        self.alert = alert
        self.completion = completion
        NSApp.activate()
        alert.window.center()
        alert.window.makeKeyAndOrderFront(nil)
    }

    @objc private func confirm() { finish(true) }
    @objc private func dismiss() { finish(false) }
    func cancel() { finish(false) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish(false)
        return false
    }

    private func finish(_ confirmed: Bool) {
        guard let completion else { return }
        self.completion = nil
        alert?.window.delegate = nil
        alert?.window.close()
        alert = nil
        completion(confirmed)
    }
}
