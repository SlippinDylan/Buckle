import Foundation

enum OnboardingStep: CaseIterable {
    case welcome, permissions, finder, preferences, complete
}

@MainActor
final class OnboardingState {
    private let defaults: UserDefaults
    private var automaticPresentationAllowed = false
    private var receivedExternalAction = false
    private static let dismissedKey = "onboarding.dismissed"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var shouldPresentAutomatically: Bool {
        automaticPresentationAllowed && !defaults.bool(forKey: Self.dismissedKey)
    }

    func prepareLaunch(isDefaultLaunch: Bool, isLoginItem: Bool) {
        automaticPresentationAllowed = isDefaultLaunch && !isLoginItem && !receivedExternalAction
    }

    func suppressAutomaticPresentation() {
        receivedExternalAction = true
        automaticPresentationAllowed = false
    }

    func dismiss() {
        defaults.set(true, forKey: Self.dismissedKey)
        automaticPresentationAllowed = false
    }
}
