import Foundation
import Testing

@testable import BuckleCore

@Test @MainActor func onboardingDismissalPersistsWithoutChangingExistingPreferences() throws {
    let name = "Buckle.OnboardingTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set(true, forKey: "SUEnableAutomaticChecks")
    let state = OnboardingState(defaults: defaults)
    state.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(state.shouldPresentAutomatically)
    state.dismiss()
    #expect(!state.shouldPresentAutomatically)
    let nextLaunch = OnboardingState(defaults: defaults)
    nextLaunch.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(!nextLaunch.shouldPresentAutomatically)
    #expect(defaults.bool(forKey: "SUEnableAutomaticChecks"))
}

@Test @MainActor func onboardingDefersBackgroundAndExternalLaunchesWithoutDismissing() throws {
    let name = "Buckle.OnboardingTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let login = OnboardingState(defaults: defaults)
    login.prepareLaunch(isDefaultLaunch: true, isLoginItem: true)
    #expect(!login.shouldPresentAutomatically)
    let external = OnboardingState(defaults: defaults)
    external.suppressAutomaticPresentation()
    external.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(!external.shouldPresentAutomatically)
    let indirect = OnboardingState(defaults: defaults)
    indirect.prepareLaunch(isDefaultLaunch: false, isLoginItem: false)
    #expect(!indirect.shouldPresentAutomatically)
    let manual = OnboardingState(defaults: defaults)
    manual.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(manual.shouldPresentAutomatically)
    manual.suppressAutomaticPresentation()
    #expect(!manual.shouldPresentAutomatically)
}

@Test @MainActor func onboardingReinstallationRequiresRemovingTheDismissalRecord() throws {
    let name = "Buckle.OnboardingTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    defaults.set("de", forKey: "application.language")

    let firstInstall = OnboardingState(defaults: defaults)
    firstInstall.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(firstInstall.shouldPresentAutomatically)
    firstInstall.dismiss()

    // Replacing the app, including after removal, retains its preferences.
    let replacement = OnboardingState(defaults: defaults)
    replacement.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(!replacement.shouldPresentAutomatically)

    // The documented uninstall step removes only the guide's dismissal record.
    defaults.removeObject(forKey: "onboarding.dismissed")
    let reinstalled = OnboardingState(defaults: defaults)
    reinstalled.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(reinstalled.shouldPresentAutomatically)
    #expect(defaults.string(forKey: "application.language") == "de")
    reinstalled.dismiss()

    let nextLaunch = OnboardingState(defaults: defaults)
    nextLaunch.prepareLaunch(isDefaultLaunch: true, isLoginItem: false)
    #expect(!nextLaunch.shouldPresentAutomatically)
}
