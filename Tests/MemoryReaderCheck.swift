import Foundation

@main
enum MemoryReaderCheck {
    static func main() async throws {
        let reader = MemoryReader()
        for _ in 0..<2 {
            let sample = try await reader.read()
            precondition(sample > 0 && sample <= ProcessInfo.processInfo.physicalMemory)
        }
        print("Mach memory sampling verified without launching the app.")
    }
}
