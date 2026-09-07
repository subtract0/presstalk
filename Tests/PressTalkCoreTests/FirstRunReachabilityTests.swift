import XCTest
@testable import PressTalkCore

/// The customer path, expressed as a test.
///
/// A person downloads the zip from presstalk.app, drags the app to
/// Applications and double-clicks it. Finder passes no shell environment, so
/// every customer-visible default that lives only in an environment variable
/// is absent for exactly the people it exists for.
///
/// This is the third instance of that defect found in one day. The checkout URL
/// was env-only, so the buy button was hidden in every Finder-launched build.
/// Guided setup was env-only, so nobody who installed the advertised way saw
/// any onboarding at all. Both were invisible from inside the repository
/// because every developer launch carries a shell environment.
final class FirstRunReachabilityTests: XCTestCase {

    /// Mirrors JarvisTapConfig's rule so the intent is asserted somewhere a
    /// unit test can see it. The config type itself reads a live environment.
    private func setupWindowShows(env: [String: String]) -> Bool {
        !(env["PRESSTALK_AUTO_SHOW_SETUP_WINDOW"] == "0" ||
          env["JARVISTAP_AUTO_SHOW_SETUP_WINDOW"] == "0")
    }

    private func permissionPanesOpen(env: [String: String]) -> Bool {
        !(env["PRESSTALK_OPEN_PERMISSION_PANES"] == "0" ||
          env["JARVISTAP_OPEN_PERMISSION_PANES"] == "0")
    }

    /// Guided setup needs BOTH flags: shouldPresentSetupWindow ANDs them, and
    /// every "Open System Settings" button is guarded by the second. Fixing
    /// only the first produced a window whose buttons did nothing, which reads
    /// as a broken app rather than an unconfigured one.
    private func onboardingWorks(env: [String: String]) -> Bool {
        setupWindowShows(env: env) && permissionPanesOpen(env: env)
    }

    /// The one that matters: a double-click from Finder.
    func testAFinderLaunchWithNoEnvironmentGetsWorkingOnboarding() {
        XCTAssertTrue(setupWindowShows(env: [:]))
        XCTAssertTrue(permissionPanesOpen(env: [:]))
        XCTAssertTrue(onboardingWorks(env: [:]))
    }

    /// The exact half-fix that shipped into the 0.1.12 build: setup appears,
    /// its buttons are dead.
    func testFixingOnlyTheWindowIsNotAFix() {
        let halfFixed = ["PRESSTALK_OPEN_PERMISSION_PANES": "0"]
        XCTAssertTrue(setupWindowShows(env: halfFixed))
        XCTAssertFalse(onboardingWorks(env: halfFixed))
    }

    /// The launchd job, the bootstrap installer and the probes all set this,
    /// and all of them must stay silent.
    func testAManagedLaunchStaysSilent() {
        XCTAssertFalse(setupWindowShows(env: ["PRESSTALK_AUTO_SHOW_SETUP_WINDOW": "0"]))
        XCTAssertFalse(setupWindowShows(env: ["JARVISTAP_AUTO_SHOW_SETUP_WINDOW": "0"]))
    }

    /// The Homebrew cask still passes 1. It must keep working, not become a
    /// value the new rule ignores.
    func testTheCaskSettingStillShowsSetup() {
        XCTAssertTrue(setupWindowShows(env: ["PRESSTALK_AUTO_SHOW_SETUP_WINDOW": "1"]))
    }

    /// Anything unrecognised shows setup. A typo in a launch agent should cost
    /// a developer a stray window, never cost a customer their onboarding.
    func testAnUnrecognisedValueFailsTowardsShowingIt() {
        for value in ["", "false", "no", "true", "yes"] {
            XCTAssertTrue(setupWindowShows(env: ["PRESSTALK_AUTO_SHOW_SETUP_WINDOW": value]),
                          "value \(value) should not silence onboarding")
        }
    }
}

/// The resource bundle that killed the app on every Mac but the build machine.
final class ResourceBundleReachabilityTests: XCTestCase {

    /// The vocabulary list must load. If it does not, the resolver is looking
    /// in the wrong place -- which is the state that shipped in every build up
    /// to 0.1.12, where the first dictation called fatalError instead.
    func testTheVocabularyListIsReachable() {
        let words = GermanVocabularyPolicy.loadUserVocabulary()
        XCTAssertFalse(words.isEmpty,
                       "resource bundle not found; on a customer's Mac this was a crash")
    }

    /// The property that matters: a missing bundle degrades, never aborts.
    /// Reading Bundle.module runs a generated closure that calls fatalError,
    /// so the shipping path must not touch it at all.
    func testAMissingBundleReturnsEmptyRatherThanCrashing() {
        let nowhere = Bundle(url: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"))
        XCTAssertNil(nowhere)
        // The bundle-taking overload is what the resolver funnels into, and it
        // must tolerate a bundle with no such resource.
        let bundleWithoutVocabulary = Bundle(for: type(of: self))
        XCTAssertNil(bundleWithoutVocabulary.url(forResource: "de_user_vocabulary", withExtension: "txt"))
        XCTAssertTrue(GermanVocabularyPolicy.loadUserVocabulary(bundle: bundleWithoutVocabulary).isEmpty)
    }
}

/// The dead end a customer could not escape.
final class PermissionOrderTests: XCTestCase {
    private let policy = FirstRunSetupPolicy()

    private func conditions(
        mic: Bool = false, input: Bool = false, accessibility: Bool = false,
        model: Bool = false, delivered: Bool = false, needsTap: Bool = true
    ) -> FirstRunSetupPolicy.Conditions {
        .init(microphoneCaptureVerified: mic, inputMonitoringGranted: input,
              accessibilityGranted: accessibility, speechModelReady: model,
              firstDictationDelivered: delivered,
              triggerRequiresInputMonitoring: needsTap)
    }

    /// The Fn trigger needs a writable event tap, macOS grants that on
    /// Accessibility, so asking for Input Monitoring first produced a step that
    /// could not be satisfied by anything the user was able to do next.
    func testAccessibilityIsAskedForBeforeInputMonitoring() {
        let steps = policy.steps(for: conditions())
        let acc = steps.firstIndex(of: .accessibility)
        let input = steps.firstIndex(of: .inputMonitoring)
        XCTAssertNotNil(acc); XCTAssertNotNil(input)
        XCTAssertLessThan(acc!, input!,
            "Input Monitoring cannot be satisfied before Accessibility is granted")
    }

    /// Following the guide in order must always reach a step the user can act
    /// on. The failure was not a wrong step, it was no step at all.
    func testTheGuideAdvancesWhenEachStepIsSatisfiedInOrder() {
        var mic = false, acc = false, input = false, model = false
        var seen: [FirstRunSetupPolicy.Step] = []
        for _ in 0..<10 {
            guard let step = policy.currentStep(for: conditions(
                mic: mic, input: input, accessibility: acc, model: model)) else { break }
            seen.append(step)
            switch step {
            case .microphone: mic = true
            case .accessibility: acc = true
            // The real dependency: this only becomes true once Accessibility is.
            case .inputMonitoring:
                XCTAssertTrue(acc, "reached Input Monitoring before Accessibility — the dead end")
                input = true
            case .speechModel: model = true
            case .firstDictation: return
            }
        }
        XCTFail("guide did not reach first dictation; visited \(seen)")
    }

    /// A trigger that needs no event tap must not be made to grant it.
    func testATriggerWithoutATapSkipsInputMonitoring() {
        XCTAssertFalse(policy.steps(for: conditions(needsTap: false))
                        .contains(.inputMonitoring))
    }
}
