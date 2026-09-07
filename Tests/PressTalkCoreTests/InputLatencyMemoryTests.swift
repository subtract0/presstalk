import XCTest
@testable import PressTalkCore

final class InputLatencyMemoryTests: XCTestCase {

    /// The measured numbers from studio1, 2026-09-07.
    func testTheMeasuredDevicesAreClassifiedAsObserved() {
        var m = InputLatencyMemory()
        for s in [0.327, 0.311, 0.340] { m.record(seconds: s, forDeviceUID: "shure") }
        for s in [1.369, 0.397, 1.222, 1.165] { m.record(seconds: s, forDeviceUID: "airpods") }
        XCTAssertEqual(m.isSlowToStart(deviceUID: "shure"), false)
        XCTAssertEqual(m.isSlowToStart(deviceUID: "airpods"), true)
        XCTAssertNil(m.annotation(forDeviceUID: "shure"))
        XCTAssertEqual(m.annotation(forDeviceUID: "airpods"), "takes about 1.2 s to start")
    }

    /// A device nobody has used is unknown, not slow. Labelling it would be the
    /// guess this type exists to replace.
    func testAnUnmeasuredDeviceIsUnknownRatherThanSlow() {
        let m = InputLatencyMemory()
        XCTAssertNil(m.isSlowToStart(deviceUID: "never-used"))
        XCTAssertNil(m.annotation(forDeviceUID: "never-used"))
    }

    /// Median, so one bad start does not become the permanent label.
    func testASingleOutlierDoesNotDefineTheDevice() {
        var m = InputLatencyMemory()
        for s in [0.30, 0.31, 4.80, 0.29, 0.32] { m.record(seconds: s, forDeviceUID: "shure") }
        XCTAssertEqual(m.isSlowToStart(deviceUID: "shure"), false)
    }

    func testItFollowsADeviceThatBecomesSlow() {
        var m = InputLatencyMemory()
        for _ in 0..<InputLatencyMemory.sampleLimit { m.record(seconds: 0.30, forDeviceUID: "d") }
        XCTAssertEqual(m.isSlowToStart(deviceUID: "d"), false)
        for _ in 0..<InputLatencyMemory.sampleLimit { m.record(seconds: 1.40, forDeviceUID: "d") }
        XCTAssertEqual(m.isSlowToStart(deviceUID: "d"), true)
    }

    func testNonsenseIsIgnored() {
        var m = InputLatencyMemory()
        m.record(seconds: .nan, forDeviceUID: "d")
        m.record(seconds: .infinity, forDeviceUID: "d")
        m.record(seconds: -1, forDeviceUID: "d")
        m.record(seconds: 99, forDeviceUID: "d")
        m.record(seconds: 0.5, forDeviceUID: "")
        XCTAssertNil(m.typicalStartSeconds(forDeviceUID: "d"))
    }

    func testItRoundTripsThroughStorage() {
        var m = InputLatencyMemory()
        m.record(seconds: 1.2, forDeviceUID: "airpods")
        XCTAssertEqual(InputLatencyMemory(storageValue: m.storageValue), m)
        XCTAssertEqual(InputLatencyMemory(storageValue: nil), InputLatencyMemory())
        XCTAssertEqual(InputLatencyMemory(storageValue: "junk"), InputLatencyMemory())
    }
}
