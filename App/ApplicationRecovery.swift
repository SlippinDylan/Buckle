import Foundation

@MainActor
struct ApplicationRecovery {
    let memoryPanel: SystemMemoryPanel
    let mouseReset: MouseResetController

    enum Failure: LocalizedError {
        case memory(Error)
        case mouse(Error)
        case both(memory: Error, mouse: Error)

        var includesMemory: Bool {
            switch self {
            case .memory, .both: true
            case .mouse: false
            }
        }

        var errorDescription: String? {
            switch self {
            case .memory(let error):
                localized("memory.restore.failed") + "\n" + error.localizedDescription
            case .mouse(let error):
                localized("mouse.restore.failed") + "\n" + error.localizedDescription
            case .both(let memory, let mouse):
                localized("memory.restore.failed") + "\n" + memory.localizedDescription + "\n\n"
                    + localized("mouse.restore.failed") + "\n" + mouse.localizedDescription
            }
        }
    }

    func restore() async throws(Failure) {
        var memoryError: Error?
        do { try memoryPanel.recover() } catch { memoryError = error }
        // A damaged memory journal must not prevent restoration of mouse utilities.
        do { try await mouseReset.recover() } catch {
            if let memoryError { throw .both(memory: memoryError, mouse: error) }
            throw .mouse(error)
        }
        if let memoryError { throw .memory(memoryError) }
    }
}
