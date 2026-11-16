import CoreGraphics
import Foundation

enum DockQuitAction: String, CaseIterable {
    case normal, force

    func request(
        confirmForce: () -> Bool, isValid: () -> Bool,
        normal: () -> Bool, force: () -> Bool
    ) -> Bool? {
        if self == .force, !confirmForce() { return nil }
        guard isValid() else { return nil }
        return self == .normal ? normal() : force()
    }
}

struct DockApplicationIdentity: Equatable, Sendable {
    let processIdentifier: Int32
    let launchDate: Date
    let bundleURL: URL
}

struct DockTileSnapshot: Sendable {
    let application: DockApplicationIdentity
    let frame: CGRect
    let sampledAt: TimeInterval

    func contains(_ point: CGPoint, at time: TimeInterval) -> Bool {
        time >= sampledAt && time - sampledAt <= 0.15 && frame.contains(point)
    }
}

// Captured pairs stay captured even when disabling cancels their action.
struct DockClickState: Sendable {
    enum Event { case down, drag, up }
    struct Result {
        let consume: Bool
        var application: DockApplicationIdentity?
    }
    private struct Capture: Sendable {
        let application: DockApplicationIdentity
        let origin: CGPoint
        var cancelled = false
        var releasedAt: TimeInterval?
    }
    var accepting = false
    var snapshot: DockTileSnapshot? {
        didSet {
            if oldValue?.frame != snapshot?.frame || oldValue?.application != snapshot?.application {
                capture?.cancelled = true
            }
        }
    }
    private var capture: Capture?
    var isDrained: Bool { capture == nil }

    mutating func cancel() {
        accepting = false
        snapshot = nil
        capture?.cancelled = true
    }

    mutating func invalidate() {
        cancel()
        capture = nil
    }

    // Source state can precede the queued up callback. Keep filtering during a release grace period.
    mutating func reconcileCancelledRelease(buttonIsDown: Bool, time: TimeInterval) -> Bool {
        guard var current = capture, current.cancelled else { return false }
        if buttonIsDown {
            current.releasedAt = nil
            capture = current
            return false
        }
        guard let releasedAt = current.releasedAt else {
            current.releasedAt = time
            capture = current
            return false
        }
        guard time - releasedAt >= 0.5 else { return false }
        capture = nil
        return true
    }

    mutating func handle(_ event: Event, point: CGPoint, time: TimeInterval) -> Result {
        switch event {
        case .down:
            // A duplicate down cannot overwrite the identity of an already captured pair.
            if capture != nil { return Result(consume: true) }
            guard accepting, let snapshot, snapshot.contains(point, at: time) else {
                return Result(consume: false)
            }
            capture = Capture(application: snapshot.application, origin: point)
            return Result(consume: true)
        case .drag, .up:
            guard var current = capture else { return Result(consume: false) }
            let matches =
                snapshot.map {
                    $0.application == current.application && $0.contains(point, at: time)
                } ?? false
            if !accepting || !matches || hypot(point.x - current.origin.x, point.y - current.origin.y) > 6 {
                current.cancelled = true
            }
            if event == .drag {
                capture = current
                return Result(consume: true)
            }
            capture = nil
            return Result(consume: true, application: current.cancelled ? nil : current.application)
        }
    }
}
