import XCTest
@testable import PressTalkCore

final class TranscriptionComputePolicyTests: XCTestCase {
    func testNewAndInvalidPreferencesKeepReleasedDefault() {
        for value: String? in [nil, "", "auto", "cpu", "all", "neural-engine", "GPU"] {
            XCTAssertEqual(TranscriptionComputeDevice(storageValue: value), .neuralEngine)
        }
    }

    func testSavedExplicitChoiceRoundTrips() {
        for device in TranscriptionComputeDevice.allCases {
            XCTAssertEqual(TranscriptionComputeDevice(storageValue: device.storageValue), device)
        }
        XCTAssertEqual(TranscriptionComputeDevice(storageValue: "gpu"), .gpu)
        XCTAssertEqual(TranscriptionComputeDevice(storageValue: "ane"), .neuralEngine)
    }

    func testInitialLoadUsesRequestedDevice() {
        for device in TranscriptionComputeDevice.allCases {
            XCTAssertEqual(decision(requested: device, loaded: nil), .reload(device))
        }
    }

    func testSameLoadedDeviceDoesNotInterruptCurrentDictation() {
        XCTAssertEqual(decision(requested: .neuralEngine, loaded: .neuralEngine,
                                recording: true), .unchanged)
        XCTAssertEqual(decision(requested: .gpu, loaded: .gpu,
                                processing: true), .unchanged)
    }

    func testChangeWaitsForRecordingAndFinalTranscription() {
        XCTAssertEqual(decision(requested: .gpu, loaded: .neuralEngine,
                                recording: true), .waitUntilIdle)
        XCTAssertEqual(decision(requested: .gpu, loaded: .neuralEngine,
                                processing: true), .waitUntilIdle)
        XCTAssertEqual(decision(requested: .gpu, loaded: .neuralEngine,
                                recording: true, processing: true), .waitUntilIdle)
        XCTAssertEqual(decision(requested: .gpu, loaded: .neuralEngine), .reload(.gpu))
    }

    func testOnlyLatestChoiceIsAppliedAfterCurrentDictation() {
        // The preference changes twice during one recording. An implementation
        // that queues each selection would unload and reload unnecessarily.
        XCTAssertEqual(decision(requested: .gpu, loaded: .neuralEngine,
                                recording: true), .waitUntilIdle)
        XCTAssertEqual(decision(requested: .neuralEngine, loaded: .neuralEngine,
                                recording: true), .unchanged)
        XCTAssertEqual(decision(requested: .neuralEngine, loaded: .neuralEngine), .unchanged)
    }

    func testInFlightLoadNeverStartsASecondLoad() {
        for requested in TranscriptionComputeDevice.allCases {
            for loaded: TranscriptionComputeDevice? in [nil, .neuralEngine, .gpu] {
                XCTAssertEqual(decision(requested: requested, loaded: loaded,
                                        loading: true), .waitUntilIdle)
            }
        }
    }

    func testSupersededLoadCannotOverwriteLatestSelection() {
        XCTAssertFalse(TranscriptionComputePolicy.acceptsCompletedLoad(
            device: .neuralEngine, requestedDevice: .gpu))
        XCTAssertFalse(TranscriptionComputePolicy.acceptsCompletedLoad(
            device: .gpu, requestedDevice: .neuralEngine))
        XCTAssertTrue(TranscriptionComputePolicy.acceptsCompletedLoad(
            device: .gpu, requestedDevice: .gpu))
        XCTAssertTrue(TranscriptionComputePolicy.acceptsCompletedLoad(
            device: .neuralEngine, requestedDevice: .neuralEngine))
    }

    func testFailedLoadCanBeRetriedWithoutSwitchingDevices() {
        // A failure is represented by no loaded recognizer, not by silently
        // loading the other accelerator or selecting a different ASR model.
        XCTAssertEqual(decision(requested: .gpu, loaded: nil), .reload(.gpu))
        XCTAssertEqual(decision(requested: .neuralEngine, loaded: nil), .reload(.neuralEngine))
    }

    private func decision(
        requested: TranscriptionComputeDevice,
        loaded: TranscriptionComputeDevice?,
        recording: Bool = false,
        processing: Bool = false,
        loading: Bool = false
    ) -> TranscriptionComputePolicy.ReloadDecision {
        TranscriptionComputePolicy.reloadDecision(
            requestedDevice: requested, loadedDevice: loaded,
            isRecording: recording, isProcessing: processing, isLoading: loading)
    }
}
