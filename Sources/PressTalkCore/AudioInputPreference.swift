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

    public static let `default` = AudioInputPreference.systemDefault

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
            self = uid.isEmpty ? .systemDefault : .specificDevice(uid: uid)
        default:
            // Unknown or absent falls back to the system default rather than to
            // the old override, so a corrupt preference cannot resurrect the
            // behaviour this type exists to retire.
            self = .systemDefault
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
                // The device is unplugged. Falling back to the system default
                // is better than failing: the user gets a working microphone
                // and their preference is still there when they replug it.
                return Choice(deviceUID: nil, reason: "preferred_device_absent",
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
            guard current.isBluetooth else {
                return Choice(deviceUID: nil, reason: "default_is_already_wired",
                              requiresPromotion: false)
            }
            guard let wired = devices.first(where: { !$0.isBluetooth && !$0.isVirtual })
            else {
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

        public init(uid: String, name: String, isDefault: Bool,
                    isBluetooth: Bool, isVirtual: Bool) {
            self.uid = uid
            self.name = name
            self.isDefault = isDefault
            self.isBluetooth = isBluetooth
            self.isVirtual = isVirtual
        }
    }
}
