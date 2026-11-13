import Darwin
import Foundation
import Observation

actor MemoryReader {
    func read() throws -> UInt64 {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(pageResult))
        }
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw NSError(domain: NSMachErrorDomain, code: Int(result))
        }
        let pages =
            UInt64(statistics.active_count) + UInt64(statistics.wire_count) + UInt64(statistics.compressor_page_count)
        return min(pages * UInt64(pageSize), ProcessInfo.processInfo.physicalMemory)
    }
}

@MainActor @Observable
final class MemoryMonitor {
    var used: UInt64 = 0
    let total = ProcessInfo.processInfo.physicalMemory
    var isLoading = false
    var error: String?
    var lastUpdated: Date?
    var remindersEnabled = UserDefaults.standard.object(forKey: "memoryReminders") as? Bool ?? true {
        didSet { UserDefaults.standard.set(remindersEnabled, forKey: "memoryReminders") }
    }
    @ObservationIgnored var onReminder: (() async -> Bool)?
    @ObservationIgnored private let reader = MemoryReader()
    @ObservationIgnored private var reminder = MemoryReminder()
    @ObservationIgnored private var pressureSignal = MemoryPressureSignal()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var pressure: DispatchSourceMemoryPressure?
    @ObservationIgnored private let samplingInterval: TimeInterval

    init(samplingInterval: TimeInterval = 30) {
        self.samplingInterval = samplingInterval
    }

    func start() {
        let pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        pressure.setEventHandler { [weak self, weak pressure] in
            MainActor.assumeIsolated {
                guard let self, let pressure else { return }
                self.pressureSignal.receive(pressure.data)
                Task { await self.refresh() }
            }
        }
        self.pressure = pressure
        pressure.resume()
        let timer = Timer(timeInterval: samplingInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        Task { await refresh() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            used = try await reader.read()
            lastUpdated = Date()
            error = nil
            let shouldRemind = reminder.shouldRemind(
                usedFraction: Double(used) / Double(total), pressureEvent: pressureSignal.take())
            if remindersEnabled && shouldRemind {
                if await onReminder?() == true { reminder.recordReminder() }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

}
