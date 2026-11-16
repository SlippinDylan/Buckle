import CoreGraphics
import Foundation

@main
struct DockMiddleClickCheck {
    @MainActor static func main() {
        let suite = "Buckle.DockMiddleClickCheck.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Cannot create isolated test preferences")
        }
        defer { defaults.removePersistentDomain(forName: suite) }
        let lifecycle = ApplicationLifecycle()
        var accessibility = false
        var inputMonitoring = false
        var installations = 0
        let controller = DockMiddleClickController(
            lifecycle: lifecycle, defaults: defaults,
            accessibilityGranted: { accessibility }, inputMonitoringGranted: { inputMonitoring },
            createTap: { mask, _, _ in
                let expected = [CGEventType.otherMouseDown, .otherMouseUp, .otherMouseDragged]
                    .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
                assert(mask == expected)
                installations += 1
                return nil
            })
        assert(!controller.isEnabled && controller.status == .disabled)
        assert(controller.quitAction == .normal)
        controller.setQuitAction(.force)
        let reopened = DockMiddleClickController(lifecycle: lifecycle, defaults: defaults)
        assert(reopened.quitAction == .force && !reopened.isEnabled && installations == 0)
        controller.setQuitAction(.normal)
        controller.setEnabled(true)
        assert(controller.isEnabled && controller.status == .accessibilityRequired)
        accessibility = true
        controller.refresh()
        assert(controller.status == .inputMonitoringRequired && installations == 1)
        inputMonitoring = true
        controller.refresh()
        assert(controller.status == .unavailable && installations == 2)
        controller.suspend()
        controller.refresh()
        assert(controller.status == .suspended && controller.isDrained && installations == 2)
        assert(lifecycle.requestTermination())
        controller.resume()
        assert(controller.status == .suspended && installations == 2)
        lifecycle.cancelTermination()
        controller.resume()
        assert(controller.status == .unavailable && installations == 3)
        controller.setEnabled(false)
        assert(controller.status == .disabled && !defaults.bool(forKey: "dock.middleClick.enabled"))
        verifyQuitConfirmation(defaults: defaults)
        print("Dock middle click checks passed")
    }

    @MainActor private static func verifyQuitConfirmation(defaults: UserDefaults) {
        let lifecycle = ApplicationLifecycle()
        let confirmation = FakeDockConfirmation()
        let controller = DockMiddleClickController(
            lifecycle: lifecycle, defaults: defaults, accessibilityGranted: { false }, confirmation: confirmation)
        var normalCalls = 0
        var forceCalls = 0
        var valid = true
        func request(_ action: DockQuitAction = .force) {
            controller.requestQuit(
                action, name: "Test App", isValid: { valid },
                normal: {
                    normalCalls += 1
                    return false
                },
                force: {
                    forceCalls += 1
                    return false
                })
        }
        controller.setQuitAction(.normal)
        request(.normal)
        assert(normalCalls == 1 && forceCalls == 0 && confirmation.presentations == 0)
        controller.setQuitAction(.force)
        request()
        request()
        assert(confirmation.presentations == 1, "Only one confirmation may be active")
        controller.refresh()
        confirmation.resolve(false)
        assert(forceCalls == 0)
        request()
        confirmation.resolve(true)
        assert(forceCalls == 1 && normalCalls == 1, "No fallback or retry on a rejected force request")
        request()
        valid = false
        confirmation.resolve(true)
        assert(forceCalls == 1, "Revalidate after confirmation")
        valid = true
        request()
        controller.setQuitAction(.normal)
        confirmation.resolve(true)
        assert(forceCalls == 1, "Changing the action invalidates a pending force request")
        controller.setQuitAction(.force)
        request()
        controller.suspend()
        assert(confirmation.completion == nil && forceCalls == 1)
        controller.resume()
        request()
        assert(lifecycle.requestTermination())
        confirmation.resolve(true)
        assert(forceCalls == 1, "A pending application quit closes admission")
        lifecycle.cancelTermination()
        controller.setQuitAction(.normal)
    }
}

@MainActor
private final class FakeDockConfirmation: DockQuitConfirming {
    var presentations = 0
    var completion: ((Bool) -> Void)?
    func present(name: String, completion: @escaping (Bool) -> Void) {
        precondition(self.completion == nil && name == "Test App")
        presentations += 1
        self.completion = completion
    }
    func cancel() { resolve(false) }
    func resolve(_ confirmed: Bool) {
        let completion = completion
        self.completion = nil
        completion?(confirmed)
    }
}
