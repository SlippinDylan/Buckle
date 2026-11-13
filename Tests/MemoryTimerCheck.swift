import CoreFoundation
import Foundation

@main
enum MemoryTimerCheck {
    @MainActor static func main() {
        let monitor = MemoryMonitor(samplingInterval: 0.02)
        let tracking = RunLoop.Mode("BuckleMemoryTimerTracking")
        // AppKit adds menu tracking to common modes; reproduce that contract without creating UI.
        CFRunLoopAddCommonMode(CFRunLoopGetMain(), CFRunLoopMode(rawValue: tracking.rawValue as CFString))
        monitor.start()
        let initialDeadline = Date().addingTimeInterval(2)
        while monitor.lastUpdated == nil && Date() < initialDeadline {
            _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        guard let initial = monitor.lastUpdated else { preconditionFailure("Initial memory sample did not finish") }
        let deadline = Date().addingTimeInterval(2)
        while monitor.lastUpdated == initial && Date() < deadline {
            _ = RunLoop.main.run(mode: tracking, before: Date().addingTimeInterval(0.02))
        }
        precondition(monitor.lastUpdated != initial, "Sampling stopped during menu tracking")
        print("The real memory monitor continues sampling in a tracking run-loop mode without opening UI.")
    }
}
