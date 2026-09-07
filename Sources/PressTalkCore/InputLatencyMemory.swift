import Foundation

/// Remembers how long each microphone takes to start, so the app can tell
/// someone what a device costs them instead of guessing.
///
/// Measured on studio1 on 2026-09-07: a USB Shure starts in 0.33 s, AirPods Pro
/// in 1.17-1.37 s. That difference is five or six syllables of German, and the
/// owner had been describing it as words being cut off long before anything in
/// the app could name it.
///
/// Per device and per machine, because the number is a property of the pairing
/// rather than of Bluetooth in general: a hardcoded "1.2 s" would be a
/// confident guess about somebody else's hardware, and this project has shipped
/// enough of those today.
public struct InputLatencyMemory: Equatable {
    /// Recent starts per device UID, newest last.
    private var samples: [String: [Double]]

    /// Enough to be stable, few enough to follow a device whose behaviour
    /// changes -- a headset that pairs slowly when its battery is low.
    public static let sampleLimit = 7

    /// Above this a start has cost the speaker words worth warning about. A
    /// wired microphone lands far below it; Bluetooth reliably above.
    public static let slowStartSeconds = 0.6

    public init(samples: [String: [Double]] = [:]) { self.samples = samples }

    public mutating func record(seconds: Double, forDeviceUID uid: String) {
        guard seconds.isFinite, seconds >= 0, seconds < 30, !uid.isEmpty else { return }
        var list = samples[uid] ?? []
        list.append(seconds)
        if list.count > Self.sampleLimit { list.removeFirst(list.count - Self.sampleLimit) }
        samples[uid] = list
    }

    /// Median, not mean. One 3-second outlier while something else grabbed the
    /// device should not become the number shown to the user forever.
    public func typicalStartSeconds(forDeviceUID uid: String) -> Double? {
        guard let list = samples[uid], !list.isEmpty else { return nil }
        let sorted = list.sorted()
        return sorted[sorted.count / 2]
    }

    /// Nil when the device has never been used: unknown is not slow, and
    /// labelling an unmeasured device as slow would be the same guess this type
    /// exists to avoid.
    public func isSlowToStart(deviceUID uid: String) -> Bool? {
        guard let typical = typicalStartSeconds(forDeviceUID: uid) else { return nil }
        return typical >= Self.slowStartSeconds
    }

    /// What to show beside a device in the picker. Nil when there is nothing
    /// honest to say yet.
    public func annotation(forDeviceUID uid: String) -> String? {
        guard let typical = typicalStartSeconds(forDeviceUID: uid) else { return nil }
        guard typical >= Self.slowStartSeconds else { return nil }
        return String(format: "takes about %.1f s to start", typical)
    }

    // MARK: persistence

    public var storageValue: [String: [Double]] { samples }

    public init(storageValue: Any?) {
        guard let raw = storageValue as? [String: [Double]] else { self.samples = [:]; return }
        self.samples = raw
    }
}
