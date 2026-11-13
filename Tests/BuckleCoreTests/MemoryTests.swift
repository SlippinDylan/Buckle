import Dispatch
import Foundation
import Testing

@testable import BuckleCore

@Test func reminderRequiresSustainedUsageAndRespectsCooldown() {
    var reminder = MemoryReminder()
    let now = ContinuousClock.now
    #expect(reminder.shouldRemind(usedFraction: 0.95, pressureEvent: false, now: now) == false)
    #expect(
        reminder.shouldRemind(usedFraction: 0.95, pressureEvent: false, now: now.advanced(by: .seconds(30))) == true)
    reminder.recordReminder(at: now.advanced(by: .seconds(30)))
    #expect(
        reminder.shouldRemind(usedFraction: 0.99, pressureEvent: true, now: now.advanced(by: .seconds(60))) == false)
    #expect(reminder.shouldRemind(usedFraction: 0.8, pressureEvent: true, now: now.advanced(by: .seconds(930))) == true)
}

@Test func normalUsageResetsHighSamples() {
    var reminder = MemoryReminder()
    let now = ContinuousClock.now
    let results = [
        reminder.shouldRemind(usedFraction: 0.95, pressureEvent: false, now: now),
        reminder.shouldRemind(usedFraction: 0.6, pressureEvent: false, now: now),
        reminder.shouldRemind(usedFraction: 0.95, pressureEvent: false, now: now),
    ]
    #expect(results == [false, false, false])
}

@Test func rapidRefreshesDoNotCountAsSustainedMemoryUsage() {
    var reminder = MemoryReminder()
    let now = ContinuousClock.now
    #expect(reminder.shouldRemind(usedFraction: 0.95, pressureEvent: false, now: now) == false)
    for milliseconds in [100, 200, 500, 1000, 29_999] {
        #expect(
            reminder.shouldRemind(
                usedFraction: 0.95, pressureEvent: false,
                now: now.advanced(by: .milliseconds(milliseconds))) == false)
    }
    #expect(
        reminder.shouldRemind(usedFraction: 0.95, pressureEvent: false, now: now.advanced(by: .seconds(30))) == true)
}

@Test func undeliveredRemindersDoNotConsumeCooldown() {
    var reminder = MemoryReminder()
    let now = ContinuousClock.now
    #expect(reminder.shouldRemind(usedFraction: 0.5, pressureEvent: true, now: now) == true)
    #expect(reminder.shouldRemind(usedFraction: 0.5, pressureEvent: true, now: now.advanced(by: .seconds(1))) == true)
}

@Test func browserLanguagesMatchAppAndSeparateProfiles() {
    #expect(BrowserLanguage.allCases.map(\.rawValue) == ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es"])
    let arguments = BrowserLanguage.simplifiedChinese.arguments(
        profile: URL(fileURLWithPath: "/tmp/profile with spaces"))
    #expect(arguments.contains("--lang=zh-CN"))
    #expect(arguments.contains("--user-data-dir=/tmp/profile with spaces"))
    #expect(arguments.contains("(zh-Hans)"))
}

@Test func mergedPressureEventsRetainHighSignalsAndAreConsumedOnce() {
    for events: DispatchSource.MemoryPressureEvent in [[.normal, .critical], [.normal, .warning], [.critical]] {
        var signal = MemoryPressureSignal()
        signal.receive(events)
        signal.receive(.normal)
        let first = signal.take()
        let second = signal.take()
        #expect(first && !second)
        var reminder = MemoryReminder()
        let decision = reminder.shouldRemind(usedFraction: 0.8, pressureEvent: first)
        #expect(decision)
    }
    var normal = MemoryPressureSignal()
    normal.receive(.normal)
    let decision = normal.take()
    #expect(!decision)
}
