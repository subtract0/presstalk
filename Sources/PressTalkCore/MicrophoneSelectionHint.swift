import Foundation

/// The sentence shown the moment someone picks a microphone in Settings.
///
/// WHY THIS IS ITS OWN TYPE
/// The first version of this lived in the Settings window and indexed the
/// device list with the popup's selected row. The popup begins with two policy
/// rows -- "System default" and "Prefer wired or built-in" -- so every device
/// index was short by two: choosing the USB microphone could produce the
/// AirPods' warning, and choosing AirPods with a short list produced no warning
/// at all. The saved selection was right; only its explanation lied, which is
/// the kind of defect that survives a demo.
///
/// It is a free function over the SELECTED DEVICE rather than a row number, so
/// the mapping cannot drift again when a row is added, and it lives here so it
/// can be tested without an NSPopUpButton.
public enum MicrophoneSelectionHint {
    public struct Device: Equatable {
        public let name: String
        public let isBluetooth: Bool
        /// What this device has actually cost on this Mac, phrased as a verb
        /// clause ("takes about 1.2 s to start"), or nil when it has never been
        /// measured here. Never a guess: an unmeasured device says only that it
        /// is wireless.
        public let startNote: String?

        public init(name: String, isBluetooth: Bool, startNote: String?) {
            self.name = name
            self.isBluetooth = isBluetooth
            self.startNote = startNote
        }
    }

    /// `selected` is nil for the policy rows, which describe themselves.
    public static func text(forSelected selected: Device?, default defaultText: String) -> String {
        guard let device = selected, device.isBluetooth else { return defaultText }
        let name = device.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = name.isEmpty ? "That microphone" : name
        if let note = device.startNote?.trimmingCharacters(in: .whitespacesAndNewlines),
           !note.isEmpty {
            return "\(subject) is wireless: it \(note) after you press the key, and speech "
                 + "before then is not recorded. Wait for the indicator to fill before you speak."
        }
        return "\(subject) is wireless. Wait for the recording indicator before speaking. "
             + "Startup time has not been measured for this capture path."
    }
}
