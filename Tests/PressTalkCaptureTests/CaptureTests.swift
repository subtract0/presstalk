import XCTest
import PressTalkHAL
@testable import PressTalkCapture

final class CaptureTests: XCTestCase {
    func testTransientUnitBindingChangeInvalidatesPreviouslyRetainedAudio() throws {
        let c = try XCTUnwrap(pt_test_create(48000, 8))
        defer { XCTAssertTrue(pt_destroy(c)) }
        let samples: [Float] = [0.1, 0.2]
        samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 2, 0) }
        // Output format notifications are irrelevant to this input-only unit.
        pt_test_property_change(c, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0)
        XCTAssertEqual(pt_stats(c).failure, 0)
        // Away and back between readbacks cannot erase the event.
        pt_test_property_change(c, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0)
        pt_test_property_change(c, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0)
        XCTAssertEqual(pt_stats(c).failure, UInt32(PT_CONFIGURATION))
        var output = [Float](repeating: 0, count: 8)
        XCTAssertEqual(output.withUnsafeMutableBufferPointer { pt_read(c, $0.baseAddress, 8) }, 0)
    }

    func testReleaseBeforeSetupPreventsOpeningAndLateDelivery() throws {
        let capture = HALCapture()
        XCTAssertNil(capture.stop(session: 10))
        var delivered = false
        XCTAssertThrowsError(try capture.start(session: 10, deviceID: 0, deviceUID: "unavailable",
            onSamples: { _ in delivered = true }, onFailure: { _ in })) { error in
            XCTAssertTrue(String(describing: error).contains("cancelled"))
        }
        XCTAssertFalse(delivered)
        XCTAssertNil(capture.stop(session: 9))
    }

    func testQueuePreservesFirstAndLastSamplesAndSilence() throws {
        let c = try XCTUnwrap(pt_test_create(48000, 512))
        defer { XCTAssertTrue(pt_destroy(c)) }
        let input: [Float] = [0.125, 0, 0, -0.75]
        input.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, 100) }
        var output = [Float](repeating: 9, count: 512)
        let n = output.withUnsafeMutableBufferPointer { pt_read(c, $0.baseAddress, 512) }
        XCTAssertEqual(n, 4)
        XCTAssertEqual(Array(output.prefix(4)), input)
        XCTAssertEqual(pt_stats(c).failure, 0)
        XCTAssertEqual(pt_stats(c).retainedFrames, 4)
        XCTAssertEqual(pt_stats(c).consumedFrames, 4)
        let silence = [Float](repeating: 0, count: 4)
        silence.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, 104) }
        XCTAssertEqual(pt_stats(c).failure, 0)
        XCTAssertGreaterThan(pt_stats(c).firstPCMAt, 0)
    }

    func testInjectedFaultsCannotYieldUsablePCM() throws {
        for fault in ["gap", "duplicate", "nonfinite", "capacity", "configuration", "timestamp"] {
            let c = try XCTUnwrap(pt_test_create(48000, 8))
            defer { XCTAssertTrue(pt_destroy(c)) }
            var samples: [Float] = [0.1, 0.2, 0.3, 0.4]
            samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, 0) }
            switch fault {
            case "gap": samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, 8) }
            case "duplicate": samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, 0) }
            case "nonfinite":
                samples[2] = .nan
                samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, 4) }
            case "capacity": samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 9, 4) }
            case "configuration": pt_invalidate(c)
            default: samples.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 4, .nan) }
            }
            XCTAssertNotEqual(pt_stats(c).failure, 0, fault)
            var output = [Float](repeating: 0, count: 8)
            XCTAssertEqual(output.withUnsafeMutableBufferPointer { pt_read(c, $0.baseAddress, 8) }, 0, fault)
        }
    }

    func testOverflowIsStickyAndNewSessionIsClean() throws {
        let c = try XCTUnwrap(pt_test_create(24000, 8))
        defer { XCTAssertTrue(pt_destroy(c)) }
        let input: [Float] = [0.3]
        for i in 0..<65 { input.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 1, Double(i)) } }
        XCTAssertEqual(pt_stats(c).failure, UInt32(PT_OVERFLOW))
        XCTAssertEqual(pt_stats(c).droppedFrames, 1)
        let next = try XCTUnwrap(pt_test_create(24000, 8))
        defer { XCTAssertTrue(pt_destroy(next)) }
        XCTAssertEqual(pt_stats(next).failure, 0)
        XCTAssertEqual(pt_stats(next).retainedFrames, 0)
    }

    func testConsumerCapacityCannotReadPastBuffer() throws {
        let c = try XCTUnwrap(pt_test_create(48000, 8))
        defer { XCTAssertTrue(pt_destroy(c)) }
        let input = [Float](repeating: 0.2, count: 8)
        input.withUnsafeBufferPointer { pt_test_push(c, $0.baseAddress, 8, 0) }
        var output: [Float] = [123]
        XCTAssertEqual(output.withUnsafeMutableBufferPointer { pt_read(c, $0.baseAddress, 1) }, 0)
        XCTAssertEqual(output[0], 123)
        XCTAssertEqual(pt_stats(c).failure, UInt32(PT_CAPACITY))
    }

    func testConversionPreservesDurationPitchAndChunkBoundaries() throws {
        for rate in [16000.0, 24000, 44100, 48000, 96000] {
            let count = Int(rate * 0.32)
            let input = (0..<count).map { Float(0.5 * sin(2 * .pi * 1000 * Double($0) / rate)) }
            func run(chunk: Int) throws -> [Float] {
                let converter = try PCMConverter(sampleRate: rate)
                var output: [Float] = []
                for offset in stride(from: 0, to: count, by: chunk) {
                    output += try converter.append(Array(input[offset..<min(offset + chunk, count)]))
                }
                output += try converter.finish()
                XCTAssertEqual(output.count, 5120, accuracy: 2)
                XCTAssertTrue(output.allSatisfy(\.isFinite))
                return output
            }
            let whole = try run(chunk: count)
            for chunk in [17, 257, 512, 4096] {
                let split = try run(chunk: chunk)
                XCTAssertEqual(split.count, whole.count)
                XCTAssertLessThan(zip(whole, split).map { abs($0 - $1) }.max() ?? 1, 0.00001)
            }
            // The first/last 20 ms must still contain the 1 kHz signal, at the original gain.
            for start in [160, whole.count - 480] {
                let window = Array(whole[start..<start + 320])
                let rms = sqrt(window.reduce(0) { $0 + Double($1 * $1) } / 320)
                XCTAssertEqual(rms, 0.35355, accuracy: 0.025)
                let crossings = zip(window, window.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
                XCTAssertEqual(crossings, 20, accuracy: 1)
            }
        }
    }

    func testConversionRejectsInvalidDataAndDrainsOnlyOnce() throws {
        XCTAssertThrowsError(try PCMConverter(sampleRate: .nan))
        let converter = try PCMConverter(sampleRate: 48000)
        XCTAssertThrowsError(try converter.append([.infinity]))
        _ = try converter.append([Float](repeating: 0, count: 4800))
        _ = try converter.finish()
        XCTAssertEqual(try converter.finish(), [])
        XCTAssertThrowsError(try converter.append([1]))
    }
}
