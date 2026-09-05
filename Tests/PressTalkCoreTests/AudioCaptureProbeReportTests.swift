import XCTest
@testable import PressTalkCore

final class AudioCaptureProbeReportTests: XCTestCase {
    private func report(
        outcome: AudioCaptureProbeReport.Outcome,
        authorization: String = "authorized",
        frames: Int = 0
    ) -> AudioCaptureProbeReport {
        AudioCaptureProbeReport(
            outcome: outcome,
            authorizationStatus: authorization,
            sampleRate: 48000,
            channelCount: 1,
            framesCaptured: frames,
            peakAmplitude: 0,
            durationSeconds: 1.2,
            detail: ""
        )
    }

    func testFramesArrivingMeansCaptured() {
        XCTAssertEqual(
            AudioCaptureProbeReport.classify(engineStarted: true, hasInputDevice: true, framesCaptured: 1024),
            .captured
        )
    }

    // The case the permission API cannot see: everything reports healthy and no
    // audio arrives.
    func testStartedEngineWithNoFramesIsASilentDenial() {
        XCTAssertEqual(
            AudioCaptureProbeReport.classify(engineStarted: true, hasInputDevice: true, framesCaptured: 0),
            .silentDenial
        )
    }

    func testEngineFailureIsNotReportedAsSilentDenial() {
        XCTAssertEqual(
            AudioCaptureProbeReport.classify(engineStarted: false, hasInputDevice: true, framesCaptured: 0),
            .engineFailed
        )
    }

    // A missing device outranks both: telling someone to reinstall the app when
    // they simply unplugged a microphone wastes their evening.
    func testMissingDeviceOutranksEngineFailure() {
        XCTAssertEqual(
            AudioCaptureProbeReport.classify(engineStarted: false, hasInputDevice: false, framesCaptured: 0),
            .noInputDevice
        )
        XCTAssertEqual(
            AudioCaptureProbeReport.classify(engineStarted: true, hasInputDevice: false, framesCaptured: 4096),
            .noInputDevice
        )
    }

    func testOnlyCapturedCountsAsUsable() {
        XCTAssertTrue(report(outcome: .captured, frames: 4096).isUsable)
        for outcome in [AudioCaptureProbeReport.Outcome.silentDenial, .engineFailed, .noInputDevice] {
            XCTAssertFalse(report(outcome: outcome).isUsable, "\(outcome) must not read as usable")
        }
    }

    // The summary is what a buyer reads at 11pm. A silent denial must not be
    // described using the word the system API would have used.
    func testSilentDenialSummaryContradictsTheSystemStatus() {
        let summary = report(outcome: .silentDenial, authorization: "authorized").userFacingSummary
        XCTAssertTrue(summary.contains("no audio arrived"), summary)
        XCTAssertTrue(summary.contains("authorized"), summary)
        XCTAssertFalse(summary.lowercased().contains("granted"), "must not present a denial as a grant: \(summary)")
    }

    func testMissingDeviceSummaryAsksForHardwareNotAReinstall() {
        let summary = report(outcome: .noInputDevice).userFacingSummary
        XCTAssertTrue(summary.contains("No microphone"), summary)
        XCTAssertFalse(summary.lowercased().contains("reinstall"), summary)
    }

    func testReportSurvivesARoundTrip() throws {
        let original = report(outcome: .captured, frames: 26400)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AudioCaptureProbeReport.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
