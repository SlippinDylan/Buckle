import Foundation
import Testing

@testable import BuckleCore

struct DockClickTests {
    @Test func quitActionsRequireExplicitConfirmationAndRevalidateAfterIt() {
        var normalCalls = 0
        var forceCalls = 0
        var confirmations = 0
        var valid = true
        func request(_ action: DockQuitAction, confirmed: Bool, invalidate: Bool = false) -> Bool? {
            action.request(
                confirmForce: {
                    confirmations += 1
                    if invalidate { valid = false }
                    return confirmed
                }, isValid: { valid },
                normal: {
                    normalCalls += 1
                    return true
                },
                force: {
                    forceCalls += 1
                    return false
                })
        }
        #expect(request(.normal, confirmed: false) == true)
        #expect(normalCalls == 1 && forceCalls == 0 && confirmations == 0)
        #expect(request(.force, confirmed: false) == nil)
        #expect(forceCalls == 0 && confirmations == 1)
        #expect(request(.force, confirmed: true) == false)
        #expect(normalCalls == 1 && forceCalls == 1 && confirmations == 2)
        #expect(request(.force, confirmed: true, invalidate: true) == nil)
        #expect(forceCalls == 1 && confirmations == 3)
    }

    private let identity = DockApplicationIdentity(
        processIdentifier: 42, launchDate: Date(timeIntervalSince1970: 10), bundleURL: URL(filePath: "/A.app"))
    private let point = CGPoint(x: 20, y: 20)

    private func state() -> DockClickState {
        var state = DockClickState()
        state.accepting = true
        state.snapshot = DockTileSnapshot(
            application: identity, frame: CGRect(x: 10, y: 10, width: 40, height: 40), sampledAt: 1)
        return state
    }

    @Test func pairedClickRequestsOnlyOneQuit() {
        var click = state()
        #expect(click.handle(.down, point: point, time: 1).consume)
        #expect(click.handle(.down, point: point, time: 1).consume)
        let release = click.handle(.up, point: point, time: 1.1)
        #expect(release.consume)
        #expect(release.application == identity)
        #expect(!click.handle(.up, point: point, time: 1.1).consume)
        #expect(click.isDrained)
    }

    @Test func invalidSnapshotsPassWholePairThrough() {
        for (point, time) in [(point, 1.2), (point, 0.9), (CGPoint(x: 60, y: 20), 1.0)] {
            var click = state()
            #expect(!click.handle(.down, point: point, time: time).consume)
            #expect(!click.handle(.up, point: point, time: time).consume)
        }
    }

    @Test func draggingOutAndBackCancelsButConsumesRelease() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        #expect(click.handle(.drag, point: CGPoint(x: 80, y: 20), time: 1.05).consume)
        let release = click.handle(.up, point: point, time: 1.1)
        #expect(release.consume)
        #expect(release.application == nil)
    }

    @Test func disableDrainsAndReenableCannotReviveAction() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.cancel()
        #expect(!click.isDrained)
        click.accepting = true
        let release = click.handle(.up, point: point, time: 1.1)
        #expect(release.consume)
        #expect(release.application == nil)
        #expect(click.isDrained)
    }

    @Test func restartOrMovedTileRejectsRelease() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.snapshot = DockTileSnapshot(
            application: DockApplicationIdentity(
                processIdentifier: identity.processIdentifier,
                launchDate: identity.launchDate.addingTimeInterval(1), bundleURL: identity.bundleURL),
            frame: CGRect(x: 10, y: 10, width: 40, height: 40), sampledAt: 1.05)
        let release = click.handle(.up, point: point, time: 1.1)
        #expect(release.consume)
        #expect(release.application == nil)
    }

    @Test func tileMotionCancelsEvenIfItReturnsBeforeRelease() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.snapshot = DockTileSnapshot(
            application: identity, frame: CGRect(x: 11, y: 10, width: 40, height: 40), sampledAt: 1.02)
        click.snapshot = state().snapshot
        let release = click.handle(.up, point: point, time: 1.1)
        #expect(release.consume)
        #expect(release.application == nil)
    }

    @Test func timeoutInvalidatesActionAndPair() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.invalidate()
        #expect(click.isDrained)
        #expect(click.snapshot == nil)
        #expect(!click.accepting)
        #expect(click.handle(.up, point: point, time: 1.1).application == nil)
    }

    @Test func cancelledCaptureRecoversLostReleaseWithoutWaitingForAnotherClick() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.cancel()
        let held = click.reconcileCancelledRelease(buttonIsDown: true, time: 1)
        #expect(!held)
        #expect(!click.isDrained)
        let firstRelease = click.reconcileCancelledRelease(buttonIsDown: false, time: 1.1)
        #expect(!firstRelease)
        let released = click.reconcileCancelledRelease(buttonIsDown: false, time: 1.61)
        #expect(released)
        #expect(click.isDrained)
        let repeated = click.reconcileCancelledRelease(buttonIsDown: false, time: 2)
        #expect(!repeated)
        #expect(!click.handle(.up, point: point, time: 1.1).consume)
    }

    @Test func cancelledCaptureLetsQueuedReleaseReachTheTapBeforeRecovery() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.cancel()
        let recovered = click.reconcileCancelledRelease(buttonIsDown: false, time: 1.01)
        #expect(!recovered)
        #expect(!click.isDrained)
        let release = click.handle(.up, point: point, time: 1.1)
        #expect(release.consume)
        #expect(release.application == nil)
        #expect(click.isDrained)
    }

    @Test func reconciliationDoesNotDiscardActivePair() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        let active = click.reconcileCancelledRelease(buttonIsDown: false, time: 1)
        #expect(!active)
        #expect(!click.isDrained)
        #expect(click.handle(.up, point: point, time: 1.1).application == identity)
    }

    @Test @MainActor func lostReleaseFinishesPendingTerminationOnlyAfterButtonIsReleased() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.cancel()
        let lifecycle = ApplicationLifecycle()
        var replies = 0
        lifecycle.onReadyToTerminate = { replies += 1 }
        #expect(lifecycle.begin(.dockClick))
        #expect(!lifecycle.requestTermination())
        if click.reconcileCancelledRelease(buttonIsDown: true, time: 1) { lifecycle.end(.dockClick) }
        #expect(replies == 0)
        if click.reconcileCancelledRelease(buttonIsDown: false, time: 2) { lifecycle.end(.dockClick) }
        #expect(replies == 0)
        if click.reconcileCancelledRelease(buttonIsDown: false, time: 2.51) { lifecycle.end(.dockClick) }
        #expect(replies == 1)
        #expect(!lifecycle.isActive(.dockClick))
    }

    @Test func holdingTheButtonAgainRestartsReleaseRecovery() {
        var click = state()
        _ = click.handle(.down, point: point, time: 1)
        click.cancel()
        let first = click.reconcileCancelledRelease(buttonIsDown: false, time: 2)
        let held = click.reconcileCancelledRelease(buttonIsDown: true, time: 2.4)
        let restarted = click.reconcileCancelledRelease(buttonIsDown: false, time: 2.8)
        let waiting = click.reconcileCancelledRelease(buttonIsDown: false, time: 3.1)
        #expect(!first && !held && !restarted && !waiting)
        #expect(!click.isDrained)
        let recovered = click.reconcileCancelledRelease(buttonIsDown: false, time: 3.31)
        #expect(recovered && click.isDrained)
    }
}
