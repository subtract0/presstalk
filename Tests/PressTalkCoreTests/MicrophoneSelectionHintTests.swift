import XCTest
@testable import PressTalkCore

final class MicrophoneSelectionHintTests: XCTestCase {
    private let fallback = "PressTalk uses a wired or built-in microphone when there is one."

    private func device(_ name: String, bluetooth: Bool, note: String? = nil)
    -> MicrophoneSelectionHint.Device {
        .init(name: name, isBluetooth: bluetooth, startNote: note)
    }

    func testThePolicyRowsKeepTheDefaultSentence() {
        XCTAssertEqual(
            MicrophoneSelectionHint.text(forSelected: nil, default: fallback), fallback)
    }

    func testAWiredDeviceKeepsTheDefaultSentence() {
        XCTAssertEqual(
            MicrophoneSelectionHint.text(
                forSelected: device("Shure MV7i", bluetooth: false), default: fallback),
            fallback)
    }

    /// The defect this type exists for: the warning must name the device that
    /// was actually selected, never its neighbour in the list.
    func testAWirelessDeviceIsNamedInItsOwnWarning() {
        let text = MicrophoneSelectionHint.text(
            forSelected: device("Alex’ AirPods Pro", bluetooth: true), default: fallback)
        XCTAssertTrue(text.contains("Alex’ AirPods Pro"), text)
        XCTAssertTrue(text.contains("wireless"), text)
    }

    /// A measured cost is the whole point of showing a number. An unmeasured
    /// device must not borrow one.
    func testAMeasuredStartIsQuotedAndAnUnmeasuredOneIsNot() {
        let measured = MicrophoneSelectionHint.text(
            forSelected: device("Alex’ AirPods Pro", bluetooth: true,
                                note: "takes about 1.2 s to start"),
            default: fallback)
        XCTAssertTrue(measured.contains("takes about 1.2 s to start"), measured)

        let unmeasured = MicrophoneSelectionHint.text(
            forSelected: device("Some Headset", bluetooth: true), default: fallback)
        XCTAssertFalse(unmeasured.contains("1.2"), unmeasured)
        XCTAssertFalse(unmeasured.contains(" s "), unmeasured)
    }

    func testABlankStartNoteIsTreatedAsUnmeasured() {
        let text = MicrophoneSelectionHint.text(
            forSelected: device("Some Headset", bluetooth: true, note: "   "), default: fallback)
        XCTAssertEqual(text, MicrophoneSelectionHint.text(
            forSelected: device("Some Headset", bluetooth: true), default: fallback))
    }

    func testAnUnnamedDeviceStillReadsAsASentence() {
        let text = MicrophoneSelectionHint.text(
            forSelected: device("", bluetooth: true), default: fallback)
        XCTAssertTrue(text.hasPrefix("That microphone is wireless"), text)
    }
}
