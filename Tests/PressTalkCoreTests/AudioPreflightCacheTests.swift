import XCTest
@testable import PressTalkCore

final class AudioPreflightCacheTests: XCTestCase {
    private let shure = AudioPreflightCache.DeviceFingerprint(
        deviceUID: "shure", sampleRate: 48_000, channelCount: 2)
    private let airpods = AudioPreflightCache.DeviceFingerprint(
        deviceUID: "airpods", sampleRate: 24_000, channelCount: 1)

    func testAColdCacheAsksForTheRealCheck() {
        let cache = AudioPreflightCache()
        XCTAssertFalse(cache.isPrimed)
        XCTAssertNil(cache.cachedResult(for: shure))
    }

    /// The point of the whole thing: a repeat press on the same hardware must
    /// not pay 52 ms to be told what it already knows.
    func testASuccessIsRemembered() {
        var cache = AudioPreflightCache()
        cache.record(nil, for: shure)
        let result = cache.cachedResult(for: shure)
        XCTAssertNotNil(result)        // we know the answer
        XCTAssertNil(result!)          // and the answer is "no failure"
    }

    func testAFailureIsRemembered() {
        var cache = AudioPreflightCache()
        cache.record("sample rate mismatch", for: shure)
        XCTAssertEqual(cache.cachedResult(for: shure), "sample rate mismatch")
    }

    /// The dangerous case. A cached success for other hardware must never be
    /// returned, because the check guards an uncatchable crash.
    func testADifferentDeviceIsACacheMiss() {
        var cache = AudioPreflightCache()
        cache.record(nil, for: shure)
        XCTAssertNil(cache.cachedResult(for: airpods))
    }

    func testASampleRateChangeOnTheSameDeviceIsACacheMiss() {
        var cache = AudioPreflightCache()
        cache.record(nil, for: shure)
        XCTAssertNil(cache.cachedResult(for: .init(
            deviceUID: "shure", sampleRate: 44_100, channelCount: 2)))
    }

    func testAChannelCountChangeIsACacheMiss() {
        var cache = AudioPreflightCache()
        cache.record(nil, for: shure)
        XCTAssertNil(cache.cachedResult(for: .init(
            deviceUID: "shure", sampleRate: 48_000, channelCount: 1)))
    }

    func testInvalidateForgetsEverything() {
        var cache = AudioPreflightCache()
        cache.record(nil, for: shure)
        cache.invalidate()
        XCTAssertFalse(cache.isPrimed)
        XCTAssertNil(cache.cachedResult(for: shure))
    }

    /// Switching away and back is the common case when someone unplugs
    /// headphones mid-session, and it must re-check rather than trust history.
    func testSwitchingBackStillRequiresTheRealCheckUntilRecordedAgain() {
        var cache = AudioPreflightCache()
        cache.record(nil, for: shure)
        cache.record(nil, for: airpods)
        XCTAssertNil(cache.cachedResult(for: shure))
        cache.record(nil, for: shure)
        XCTAssertNotNil(cache.cachedResult(for: shure))
    }
}
