import Testing

@testable import BuckleCore

@Test @MainActor func terminationWaitsForEveryOperationAndRejectsNewWork() {
    let lifecycle = ApplicationLifecycle()
    var replies = 0
    lifecycle.onReadyToTerminate = { replies += 1 }
    #expect(lifecycle.begin(.mouseReset))
    #expect(lifecycle.begin(.memoryPanel))
    #expect(!lifecycle.begin(.mouseReset))
    #expect(!lifecycle.requestTermination())
    #expect(!lifecycle.requestTermination())
    lifecycle.end(.mouseReset)
    #expect(replies == 0)
    #expect(!lifecycle.begin(.mouseReset))
    lifecycle.end(.memoryPanel)
    #expect(replies == 1)
    #expect(!lifecycle.begin(.memoryPanel))
}

@Test @MainActor func cancellingTerminationRestoresNormalOperation() {
    let lifecycle = ApplicationLifecycle()
    #expect(lifecycle.requestTermination())
    #expect(!lifecycle.begin(.mouseReset))
    lifecycle.cancelTermination()
    #expect(lifecycle.begin(.mouseReset))
    lifecycle.end(.mouseReset)
}

private enum RecoveryFailure: Error { case expected }

@Test @MainActor func recoveryRetriesWithoutAdmittingNewOperationsOrQuitRequests() async {
    let lifecycle = ApplicationLifecycle()
    #expect(lifecycle.requestTermination())
    #expect(!lifecycle.requestTermination())
    var attempts = 0
    var confirmations = 0
    let allowed = await lifecycle.resolveTermination(
        recover: { () async throws(RecoveryFailure) in
            attempts += 1
            #expect(!lifecycle.begin(.mouseReset))
            #expect(!lifecycle.requestTermination())
            if attempts == 1 { throw .expected }
        },
        confirmRecoveryFailure: { _ in
            confirmations += 1
            return .retry
        })
    #expect(allowed && attempts == 2 && confirmations == 1)
    #expect(lifecycle.terminationRequested)
}

@Test @MainActor func recoveryFailureNeedsAnExplicitQuitDecision() async {
    for choice in [ApplicationLifecycle.RecoveryDecision.cancel, .quit] {
        let lifecycle = ApplicationLifecycle()
        #expect(lifecycle.requestTermination())
        var prompted = false
        let allowed = await lifecycle.resolveTermination(
            recover: { () async throws(RecoveryFailure) in throw .expected },
            confirmRecoveryFailure: { _ in
                prompted = true
                return choice
            })
        #expect(prompted && allowed == (choice == .quit))
        #expect(lifecycle.terminationRequested == allowed)
        if !allowed {
            #expect(lifecycle.begin(.memoryPanel))
            lifecycle.end(.memoryPanel)
            #expect(lifecycle.requestTermination())
        }
    }
}

@Test @MainActor func asynchronousRecoveryCoalescesRepeatedTerminationRequests() async {
    let lifecycle = ApplicationLifecycle()
    #expect(lifecycle.requestTermination())
    var continuation: CheckedContinuation<Void, Never>?
    let resolving = Task {
        await lifecycle.resolveTermination(
            recover: { () async throws(RecoveryFailure) in
                await withCheckedContinuation { continuation = $0 }
            },
            confirmRecoveryFailure: { _ in .cancel })
    }
    while continuation == nil { await Task.yield() }
    #expect(!lifecycle.requestTermination())
    #expect(!lifecycle.begin(.memoryPermissions))
    continuation?.resume()
    let allowed = await resolving.value
    #expect(allowed)
}
