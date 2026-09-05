import XCTest
@testable import PressTalkCore

final class FirstRunSetupPolicyTests: XCTestCase {
    private let policy = FirstRunSetupPolicy()

    private func conditions(
        microphone: Bool = false,
        inputMonitoring: Bool = false,
        accessibility: Bool = false,
        speechModel: Bool = false,
        firstDictation: Bool = false,
        needsInputMonitoring: Bool = true
    ) -> FirstRunSetupPolicy.Conditions {
        FirstRunSetupPolicy.Conditions(
            microphoneCaptureVerified: microphone,
            inputMonitoringGranted: inputMonitoring,
            accessibilityGranted: accessibility,
            speechModelReady: speechModel,
            firstDictationDelivered: firstDictation,
            triggerRequiresInputMonitoring: needsInputMonitoring
        )
    }

    // Nothing else works without audio, so it is asked for first.
    func testMicrophoneComesFirst() {
        XCTAssertEqual(policy.currentStep(for: conditions()), .microphone)
    }

    func testOneStepAtATime() {
        var conditions = self.conditions()
        var seen: [FirstRunSetupPolicy.Step] = []
        var guardrail = 0
        while let step = policy.currentStep(for: conditions), guardrail < 10 {
            guardrail += 1
            seen.append(step)
            switch step {
            case .microphone:
                conditions = self.conditions(microphone: true)
            case .inputMonitoring:
                conditions = self.conditions(microphone: true, inputMonitoring: true)
            case .accessibility:
                conditions = self.conditions(microphone: true, inputMonitoring: true, accessibility: true)
            case .speechModel:
                conditions = self.conditions(
                    microphone: true, inputMonitoring: true, accessibility: true, speechModel: true)
            case .firstDictation:
                conditions = self.conditions(
                    microphone: true, inputMonitoring: true, accessibility: true,
                    speechModel: true, firstDictation: true)
            }
        }
        XCTAssertEqual(seen, [.microphone, .inputMonitoring, .accessibility, .speechModel, .firstDictation])
        XCTAssertNil(policy.currentStep(for: conditions))
    }

    // A trigger that does not use an event tap must not make someone grant
    // Input Monitoring for nothing.
    func testTriggersThatDoNotNeedInputMonitoringDoNotAskForIt() {
        let steps = policy.steps(for: conditions(needsInputMonitoring: false))
        XCTAssertFalse(steps.contains(.inputMonitoring))
        XCTAssertEqual(policy.currentStep(for: conditions(microphone: true, needsInputMonitoring: false)), .accessibility)
    }

    // Permissions looking right is not the same as text arriving.
    func testSetupIsNotCompleteUntilTextHasBeenDelivered() {
        let everythingButDictation = conditions(
            microphone: true, inputMonitoring: true, accessibility: true, speechModel: true, firstDictation: false)
        XCTAssertFalse(policy.isComplete(everythingButDictation))
        XCTAssertEqual(policy.currentStep(for: everythingButDictation), .firstDictation)
    }

    // PressTalk copies to the clipboard when it cannot paste. That is worse, not
    // broken, so a managed Mac that will never grant Accessibility still finishes.
    func testAccessibilityIsOptional() {
        let noAccessibility = conditions(
            microphone: true, inputMonitoring: true, accessibility: false,
            speechModel: true, firstDictation: true)
        XCTAssertTrue(policy.isComplete(noAccessibility))
        XCTAssertTrue(FirstRunSetupPolicy.Step.accessibility.isOptional)
    }

    func testMicrophoneIsNotOptional() {
        XCTAssertFalse(
            policy.isComplete(conditions(
                microphone: false, inputMonitoring: true, accessibility: true,
                speechModel: true, firstDictation: true)))
        XCTAssertFalse(FirstRunSetupPolicy.Step.microphone.isOptional)
    }

    func testInputMonitoringBlocksOnlyWhenTheTriggerNeedsIt() {
        let base = conditions(
            microphone: true, inputMonitoring: false, accessibility: true,
            speechModel: true, firstDictation: true, needsInputMonitoring: true)
        XCTAssertFalse(policy.isComplete(base))

        let noTapTrigger = conditions(
            microphone: true, inputMonitoring: false, accessibility: true,
            speechModel: true, firstDictation: true, needsInputMonitoring: false)
        XCTAssertTrue(policy.isComplete(noTapTrigger))
    }

    // Progress counts against the steps this configuration needs, so a trigger
    // that skips one does not sit at 80% forever.
    func testProgressIsRelativeToRequiredSteps() {
        XCTAssertEqual(policy.progress(conditions()), 0, accuracy: 0.001)
        XCTAssertEqual(
            policy.progress(conditions(
                microphone: true, inputMonitoring: true, accessibility: true,
                speechModel: true, firstDictation: true)),
            1, accuracy: 0.001)

        let done = conditions(
            microphone: true, accessibility: true, speechModel: true,
            firstDictation: true, needsInputMonitoring: false)
        XCTAssertEqual(policy.progress(done), 1, accuracy: 0.001)
    }

    // Every step has to be explainable to a person, or it becomes a dialog they
    // dismiss.
    func testEveryStepExplainsItself() {
        for step in FirstRunSetupPolicy.Step.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) has no title")
            XCTAssertGreaterThan(step.explanation.count, 30, "\(step) explanation is too thin")
        }
    }

    // The microphone step must key off captured frames, never the authorization
    // status, which stays .authorized through stale grants and dead devices.
    func testMicrophoneStepTracksVerifiedCaptureNotPermission() {
        XCTAssertEqual(policy.state(of: .microphone, given: conditions(microphone: false)), .pending)
        XCTAssertEqual(policy.state(of: .microphone, given: conditions(microphone: true)), .satisfied)
    }
}
