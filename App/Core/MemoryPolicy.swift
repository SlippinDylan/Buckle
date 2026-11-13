import Dispatch
import Foundation

public struct MemoryReminder: Sendable {
    private var highSince: ContinuousClock.Instant?
    private var lastReminder: ContinuousClock.Instant?

    public init() {}

    public mutating func shouldRemind(
        usedFraction: Double, pressureEvent: Bool, now: ContinuousClock.Instant = .now
    ) -> Bool {
        if usedFraction >= 0.9 {
            if highSince == nil { highSince = now }
        } else {
            highSince = nil
        }
        let sustained = highSince.map { $0.duration(to: now) >= .seconds(30) } ?? false
        guard pressureEvent || sustained else { return false }
        return lastReminder.map { $0.duration(to: now) >= .seconds(900) } ?? true
    }

    public mutating func recordReminder(at now: ContinuousClock.Instant = .now) {
        lastReminder = now
    }
}

// Dispatch coalesces pressure flags; they describe events received, not an ordered current level.
public struct MemoryPressureSignal: Sendable {
    private var pending = false

    public init() {}

    public mutating func receive(_ events: DispatchSource.MemoryPressureEvent) {
        pending = pending || !events.intersection([.warning, .critical]).isEmpty
    }

    public mutating func take() -> Bool {
        defer { pending = false }
        return pending
    }
}
