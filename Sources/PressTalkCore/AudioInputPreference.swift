import Foundation

/// Which microphone PressTalk should use.
///
/// This used to be one developer's preference compiled in as universal
/// behaviour: any Bluetooth default was overridden with a physical device,
/// scored by a table that penalised Bluetooth by 140 points. The reason was
/// real -- AirPods misbehaved on a laptop sitting in front of you -- but the
/// consequence was that PressTalk quietly disagreed with a choice the user had
/// already made in System Settings.
///
/// Worse, overriding required *promoting* the chosen device to be the system
/// default, and nothing ever restored the previous one. Dictating once with
/// AirPods connected silently repointed the microphone for every other
/// application on the Mac, permanently. That is not a preference, it is damage.
///
/// So the default is now `.systemDefault`, which is what almost every other
/// app does and what a user expects. The old behaviour remains available for
/// people who want it, and choosing a specific device is available for people
/// who want that -- but both are now a decision someone made, not one made for
/// them.
public enum AudioInputPreference: Equatable {
    /// Use whatever macOS says the input device is. No override, no promotion,
    /// no side effect on other applications.
    case systemDefault

    /// Skip Bluetooth when something wired or built in is available. The old
    /// hardcoded behaviour, now opt-in.
    case preferWired

    /// Always this device, identified by its persistent UID rather than its
    /// AudioDeviceID, which macOS reassigns across reboots and replugs.
    case specificDevice(uid: String)

    /// Prefer wired, not system default.
    ///
    /// This was `.systemDefault`, on the reasoning that PressTalk should follow
    /// macOS like most applications do. Measurement changed the answer: on this
    /// hardware AirPods take about 1.2 s to start against a USB microphone's
    /// 0.33 s, and 1.2 s is five or six syllables gone before recording begins.
    /// A dictation app silently inheriting that costs the user their first
    /// words with no explanation.
    ///
    /// This is not the old override returning. That one *changed* the system
    /// default, so every other application on the Mac followed PressTalk's
    /// opinion. This binds PressTalk's own capture engine and changes nothing
    /// outside it, and `.systemDefault` remains one click away for anyone who
    /// wants their headset used.
    public static let `default` = AudioInputPreference.preferWired

    // MARK: persistence

    public var storageValue: String {
        switch self {
        case .systemDefault: return "system_default"
        case .preferWired: return "prefer_wired"
        case .specificDevice(let uid): return "device:\(uid)"
        }
    }

    public init(storageValue: String?) {
        switch storageValue {
        case "prefer_wired": self = .preferWired
        case let value? where value.hasPrefix("device:"):
            let uid = String(value.dropFirst("device:".count))
            // A device prefix with nothing after it is corruption, not a
            // choice of system default. It lands on the shipped default like
            // every other unrecognised value.
            self = uid.isEmpty ? .default : .specificDevice(uid: uid)
        case "system_default": self = .systemDefault
        default:
            // Absent means never chosen, so the shipped default applies. An
            // unrecognised value lands here too, which is safe: preferWired
            // changes nothing outside PressTalk.
            self = .default
        }
    }

    public var displayName: String {
        switch self {
        case .systemDefault: return "System default"
        case .preferWired: return "Prefer wired or built-in"
        case .specificDevice: return "A specific microphone"
        }
    }
}

/// Chooses a device from what is available, given a preference.
public enum AudioInputSelector {

    public struct Choice: Equatable {
        public let deviceUID: String?
        /// Why this device was chosen, for the trace log.
        public let reason: String
        /// Whether using it requires changing the system default input device.
        /// True only when the user asked for a device macOS is not currently
        /// using, because that change is visible to every other application.
        public let requiresPromotion: Bool

        public init(deviceUID: String?, reason: String, requiresPromotion: Bool) {
            self.deviceUID = deviceUID
            self.reason = reason
            self.requiresPromotion = requiresPromotion
        }
    }

    /// `nil` deviceUID means "use the system default and change nothing".
    public static func choose(
        preference: AudioInputPreference,
        devices: [Device]
    ) -> Choice {
        switch preference {
        case .systemDefault:
            return Choice(deviceUID: nil, reason: "system_default",
                          requiresPromotion: false)

        case .specificDevice(let uid):
            guard let match = devices.first(where: { $0.uid == uid }) else {
                // Preserve identity even when absent. The caller must report
                // unavailability; substituting another microphone is not consent.
                return Choice(deviceUID: uid, reason: "preferred_device_absent",
                              requiresPromotion: false)
            }
            return Choice(deviceUID: match.uid,
                          reason: match.isDefault ? "preferred_device_already_default"
                                                  : "preferred_device",
                          requiresPromotion: !match.isDefault)

        case .preferWired:
            guard let current = devices.first(where: { $0.isDefault }) else {
                return Choice(deviceUID: nil, reason: "no_default_device",
                              requiresPromotion: false)
            }
            // Continuity counts as a reason to look, not only Bluetooth.
            // Excluding the phone from being CHOSEN did nothing when the phone
            // was already the system default: it is not Bluetooth, so this
            // returned "default_is_already_wired" and kept it. The exclusion
            // and this test have to agree on what counts as a real microphone
            // or the exclusion only works in the cases it was tested on.
            guard current.isBluetooth || current.isContinuity else {
                return Choice(deviceUID: nil, reason: "default_is_already_wired",
                              requiresPromotion: false)
            }
            // Continuity is excluded here, not merely ranked below. An iPhone
            // is not a wired alternative in any sense a person would accept: it
            // may be in another room, and it stops being a microphone the
            // moment they pick it up. Ranking alone still selected it when it
            // was the only non-Bluetooth device in the list, which on a Mac
            // Studio with AirPods and a phone on the desk is the common case.
            guard let wired = devices.first(where: {
                !$0.isBluetooth && !$0.isVirtual && !$0.isContinuity
            }) else {
                // Bluetooth is all there is. Using it beats refusing to record.
                return Choice(deviceUID: nil, reason: "no_wired_alternative",
                              requiresPromotion: false)
            }
            return Choice(deviceUID: wired.uid, reason: "avoided_bluetooth",
                          requiresPromotion: true)
        }
    }

    public struct Device: Equatable {
        public let uid: String
        public let name: String
        public let isDefault: Bool
        public let isBluetooth: Bool
        public let isVirtual: Bool
        /// An iPhone or iPad offered over Continuity. Defaulted to false so a
        /// caller that has not thought about it cannot accidentally mark a real
        /// microphone as one.
        public let isContinuity: Bool

        public init(uid: String, name: String, isDefault: Bool,
                    isBluetooth: Bool, isVirtual: Bool, isContinuity: Bool = false) {
            self.uid = uid
            self.name = name
            self.isDefault = isDefault
            self.isBluetooth = isBluetooth
            self.isVirtual = isVirtual
            self.isContinuity = isContinuity
        }
    }
}
