import Foundation
import Observation

@MainActor @Observable
final class ApplicationLifecycle {
    enum Operation: Hashable {
        case memoryPanel, memoryPermissions, mouseReset, finderAction, finderPermissions, menuBarRestart
    }

    enum RecoveryDecision { case retry, cancel, quit }

    private enum Termination { case running, waiting, recovering }
    private var operations: Set<Operation> = []
    private var termination: Termination = .running
    var terminationRequested: Bool { termination != .running }
    @ObservationIgnored var onReadyToTerminate: (() -> Void)?

    func isActive(_ operation: Operation) -> Bool { operations.contains(operation) }

    // Recovery failures have their own quit decision; ordinary action errors must not interrupt it.
    func shouldPresentUserActionError(_ error: Error) -> Bool {
        !terminationRequested && (error as? CocoaError)?.code != .userCancelled
    }

    func begin(_ operation: Operation) -> Bool {
        guard !terminationRequested else { return false }
        return operations.insert(operation).inserted
    }

    func end(_ operation: Operation) {
        precondition(operations.remove(operation) != nil, "Only an active operation can finish")
        if termination == .waiting && operations.isEmpty {
            termination = .recovering
            onReadyToTerminate?()
        }
    }

    // A pending quit closes admission first, so an idle gap cannot start another operation.
    func requestTermination() -> Bool {
        guard termination == .running else { return false }
        termination = operations.isEmpty ? .recovering : .waiting
        return operations.isEmpty
    }

    func resolveTermination<Failure: Error>(
        recover: () async throws(Failure) -> Void, confirmRecoveryFailure: (Failure) -> RecoveryDecision
    ) async -> Bool {
        precondition(termination == .recovering && operations.isEmpty, "Recovery is resolved after operations finish")
        while true {
            do {
                try await recover()
                return true
            } catch {
                switch confirmRecoveryFailure(error) {
                case .retry: continue
                case .quit: return true
                case .cancel:
                    cancelTermination()
                    return false
                }
            }
        }
    }

    func cancelTermination() { termination = .running }
}
