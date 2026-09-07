import XCTest
@testable import PressTalkCore

final class AudioInputPreferenceTests: XCTestCase {

    private func device(_ uid: String, name: String = "Mic", isDefault: Bool = false,
                        bluetooth: Bool = false, virtual: Bool = false)
    -> AudioInputSelector.Device {
        .init(uid: uid, name: name, isDefault: isDefault,
              isBluetooth: bluetooth, isVirtual: virtual)
    }

    private var airpodsDefaultPlusShure: [AudioInputSelector.Device] {
        [device("airpods", name: "AirPods Pro", isDefault: true, bluetooth: true),
         device("shure", name: "Shure MV7i"),
         device("camo", name: "Camo Microphone", virtual: true)]
    }

    // MARK: the default must not touch anything outside PressTalk

    /// Was .systemDefault. Measurement changed it: AirPods take about 1.2 s to
    /// start against a USB microphone's 0.33 s, which is five or six syllables
    /// gone before recording begins. A dictation app should not inherit that
    /// silently.
    func testTheDefaultPrefersWired() {
        XCTAssertEqual(AudioInputPreference.default, .preferWired)
        XCTAssertEqual(AudioInputPreference(storageValue: nil), .preferWired)
    }

    /// The distinction that makes preferWired acceptable as a default: it binds
    /// PressTalk's own engine and never asks for the system default to move.
    /// The old override changed the default for every application on the Mac.
    func testTheDefaultNeverRequiresChangingTheSystemDefault() {
        let choice = AudioInputSelector.choose(
            preference: .default, devices: airpodsDefaultPlusShure)
        XCTAssertEqual(choice.deviceUID, "shure")
        // requiresPromotion still reports that this differs from the system
        // default, and the app deliberately ignores it: it binds the engine.
        XCTAssertTrue(choice.requiresPromotion)
    }

    /// Anyone who wants their headset used says so, and is obeyed.
    func testSystemDefaultRemainsSelectable() {
        XCTAssertEqual(AudioInputPreference(storageValue: "system_default"), .systemDefault)
        XCTAssertNil(AudioInputSelector.choose(
            preference: .systemDefault, devices: airpodsDefaultPlusShure).deviceUID)
    }

    /// The whole point of the change: with AirPods as the system default and a
    /// USB microphone attached, PressTalk now uses the AirPods, because that is
    /// what the user chose in System Settings.
    func testSystemDefaultUsesTheAirPodsAndPromotesNothing() {
        let choice = AudioInputSelector.choose(
            preference: .systemDefault, devices: airpodsDefaultPlusShure)
        XCTAssertNil(choice.deviceUID)
        XCTAssertFalse(choice.requiresPromotion)
    }

    /// An unrecognised value lands on the shipped default, which is safe
    /// because it changes nothing outside PressTalk.
    func testACorruptPreferenceFallsBackToTheShippedDefault() {
        XCTAssertEqual(AudioInputPreference(storageValue: "avoid_bluetooth_v1"), .default)
        XCTAssertEqual(AudioInputPreference(storageValue: "device:"), .default)
    }

    // MARK: opt-in wired preference

    func testPreferWiredSkipsABluetoothDefault() {
        let choice = AudioInputSelector.choose(
            preference: .preferWired, devices: airpodsDefaultPlusShure)
        XCTAssertEqual(choice.deviceUID, "shure")
        XCTAssertEqual(choice.reason, "avoided_bluetooth")
        XCTAssertTrue(choice.requiresPromotion)
    }

    func testPreferWiredSkipsVirtualDevicesToo() {
        // Camo is virtual and must not be chosen as the wired alternative.
        let choice = AudioInputSelector.choose(
            preference: .preferWired,
            devices: [device("airpods", isDefault: true, bluetooth: true),
                      device("camo", virtual: true),
                      device("builtin", name: "MacBook Pro Microphone")])
        XCTAssertEqual(choice.deviceUID, "builtin")
    }

    func testPreferWiredChangesNothingWhenTheDefaultIsAlreadyWired() {
        let choice = AudioInputSelector.choose(
            preference: .preferWired,
            devices: [device("shure", isDefault: true), device("airpods", bluetooth: true)])
        XCTAssertNil(choice.deviceUID)
        XCTAssertFalse(choice.requiresPromotion)
    }

    /// A Mac Studio with only AirPods connected has no wired alternative.
    /// Recording over Bluetooth beats refusing to record.
    func testBluetoothIsUsedWhenItIsTheOnlyInput() {
        let choice = AudioInputSelector.choose(
            preference: .preferWired,
            devices: [device("airpods", isDefault: true, bluetooth: true)])
        XCTAssertNil(choice.deviceUID)
        XCTAssertEqual(choice.reason, "no_wired_alternative")
        XCTAssertFalse(choice.requiresPromotion)
    }

    // MARK: a specific chosen device

    func testAChosenDeviceIsUsedAndNeedsPromotionWhenItIsNotDefault() {
        let choice = AudioInputSelector.choose(
            preference: .specificDevice(uid: "shure"), devices: airpodsDefaultPlusShure)
        XCTAssertEqual(choice.deviceUID, "shure")
        XCTAssertTrue(choice.requiresPromotion)
    }

    func testAChosenDeviceThatIsAlreadyDefaultNeedsNoPromotion() {
        let choice = AudioInputSelector.choose(
            preference: .specificDevice(uid: "shure"),
            devices: [device("shure", isDefault: true)])
        XCTAssertFalse(choice.requiresPromotion)
    }

    /// An absent chosen microphone must not silently become a different input.
    func testAnUnpluggedChoicePreservesIdentityAndReportsAbsence() {
        let preference = AudioInputPreference.specificDevice(uid: "shure")
        let choice = AudioInputSelector.choose(
            preference: preference,
            devices: [device("builtin", isDefault: true)])
        XCTAssertEqual(choice.deviceUID, "shure")
        XCTAssertEqual(choice.reason, "preferred_device_absent")
        XCTAssertFalse(choice.requiresPromotion)
        // Round-trips, so replugging restores the choice.
        XCTAssertEqual(AudioInputPreference(storageValue: preference.storageValue),
                       preference)
    }

    // MARK: promotion is the exception, not the rule

    /// Promotion changes the system default for every application on the Mac,
    /// so it must only ever follow an explicit user choice.
    func testSystemDefaultNeverPromotes() {
        for devices in [airpodsDefaultPlusShure, [device("only", isDefault: true)], []] {
            XCTAssertFalse(
                AudioInputSelector.choose(preference: .systemDefault, devices: devices)
                    .requiresPromotion)
        }
    }

    func testStorageRoundTrips() {
        for preference: AudioInputPreference in [
            .systemDefault, .preferWired, .specificDevice(uid: "AppleUSBAudioEngine:Shure")
        ] {
            XCTAssertEqual(
                AudioInputPreference(storageValue: preference.storageValue), preference)
        }
    }
}

/// What this app may and may not claim about silence, from getting it wrong on
/// 2026-09-07: the owner was told his Shure was muted while Zoom was recording
/// from it successfully.
final class MutedDeviceTests: XCTestCase {

    /// The only mute claim that is checkable: macOS says input to *this
    /// process* is muted.
    func testProcessLevelMuteIsNamedAsSuch() {
        let verdict = CaptureIntegrity.evaluate(
            capturedSeconds: 1.10, heldSeconds: 1.27, rms: 0.0, peak: 0.0,
            inputMutedForThisProcess: true)
        XCTAssertEqual(verdict, .inputMutedForThisApp)
        let message = verdict.userFacingMessage ?? ""
        XCTAssertTrue(message.contains("PressTalk"),
                      "the claim must be scoped to this app, not to a device")
    }

    /// Unknown, unsupported and failing reads all arrive as false, and silence
    /// then stays silence. Naming a cause we cannot establish is worse than
    /// naming none.
    func testSilenceWithoutAProvenMuteStaysGeneric() {
        XCTAssertEqual(
            CaptureIntegrity.evaluate(capturedSeconds: 1.1, heldSeconds: 1.3,
                                      rms: 0.0, peak: 0.0,
                                      inputMutedForThisProcess: false),
            .silent)
    }

    func testAudibleAudioIsUsableEvenIfAMuteIsReported() {
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 3.0, heldSeconds: 3.1, rms: 0.02, peak: 0.3,
            inputMutedForThisProcess: true).isUsable)
    }

    /// The capture that was let through: 0.30 s of a 2.75 s hold, 89% of the
    /// speech gone, exempt because the truncation check started at 3 s.
    func testTheHoldThatWasExemptIsNowCaught() {
        let verdict = CaptureIntegrity.evaluate(
            capturedSeconds: 0.30, heldSeconds: 2.75, rms: 0.02, peak: 0.3)
        XCTAssertEqual(verdict, .truncated(capturedSeconds: 0.30, heldSeconds: 2.75))
    }

    /// A stray tap of the key is still not a broken microphone.
    func testStrayTapsAreStillExempt() {
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 0.1, heldSeconds: 0.4, rms: 0.02, peak: 0.3).isUsable)
        XCTAssertTrue(CaptureIntegrity.evaluate(
            capturedSeconds: 0.3, heldSeconds: 0.9, rms: 0.02, peak: 0.3).isUsable)
    }

    /// Choosing a specific microphone must not require moving the system
    /// default: doing that raced the engine and killed capture.
    func testAChosenDeviceIsIdentifiedForDirectBinding() {
        let devices = [
            AudioInputSelector.Device(uid: "zoom", name: "ZoomAudioDevice",
                                      isDefault: true, isBluetooth: false, isVirtual: true),
            AudioInputSelector.Device(uid: "builtin", name: "MacBook Microphone",
                                      isDefault: false, isBluetooth: false, isVirtual: false),
        ]
        XCTAssertEqual(
            AudioInputSelector.choose(preference: .specificDevice(uid: "builtin"),
                                      devices: devices).deviceUID,
            "builtin")
    }

    // MARK: - An iPhone is not a wired microphone

    /// Reported on the owner's own desk: AirPods connected, an iPhone 17
    /// sitting there offering itself over Continuity, and dictation going to
    /// neither the AirPods nor the built-in microphone. Continuity is not
    /// Bluetooth and not virtual, so "the first non-Bluetooth, non-virtual
    /// device" selected the phone.
    func testAContinuityPhoneIsNotTreatedAsAWiredAlternative() {
        let devices = [
            AudioInputSelector.Device(uid: "airpods", name: "Alex’ AirPods Pro",
                                      isDefault: true, isBluetooth: true, isVirtual: false),
            AudioInputSelector.Device(uid: "iphone", name: "Alex’ iPhone Microphone",
                                      isDefault: false, isBluetooth: false, isVirtual: false,
                                      isContinuity: true),
        ]
        let choice = AudioInputSelector.choose(preference: .preferWired, devices: devices)
        XCTAssertNil(choice.deviceUID, "selected the phone as a wired alternative")
        XCTAssertEqual(choice.reason, "no_wired_alternative")
    }

    /// And a real microphone is still preferred over the AirPods when one
    /// exists, with the phone in the list alongside it.
    func testARealMicrophoneStillWinsWithAPhoneInTheList() {
        let devices = [
            AudioInputSelector.Device(uid: "airpods", name: "Alex’ AirPods Pro",
                                      isDefault: true, isBluetooth: true, isVirtual: false),
            AudioInputSelector.Device(uid: "iphone", name: "Alex’ iPhone Microphone",
                                      isDefault: false, isBluetooth: false, isVirtual: false,
                                      isContinuity: true),
            AudioInputSelector.Device(uid: "shure", name: "Shure MV7i",
                                      isDefault: false, isBluetooth: false, isVirtual: false),
        ]
        XCTAssertEqual(
            AudioInputSelector.choose(preference: .preferWired, devices: devices).deviceUID,
            "shure")
    }

    /// Choosing the phone BY NAME must still work. The exclusion is about what
    /// PressTalk picks on someone's behalf, not about vetoing their choice.
    func testAPhoneChosenByNameIsStillHonoured() {
        let devices = [
            AudioInputSelector.Device(uid: "iphone", name: "Alex’ iPhone Microphone",
                                      isDefault: false, isBluetooth: false, isVirtual: false,
                                      isContinuity: true),
        ]
        XCTAssertEqual(
            AudioInputSelector.choose(preference: .specificDevice(uid: "iphone"),
                                      devices: devices).deviceUID,
            "iphone")
    }


    /// The boundary the Continuity exclusion missed: make the phone the system
    /// DEFAULT, with a built-in microphone present. It is not Bluetooth, so
    /// preferWired used to return "default_is_already_wired" and keep the
    /// phone -- the exclusion only worked when something else was default.
    func testAContinuityPhoneAsTheSystemDefaultIsStillReplaced() {
        let devices = [
            AudioInputSelector.Device(uid: "iphone", name: "Alex’ iPhone Microphone",
                                      isDefault: true, isBluetooth: false, isVirtual: false,
                                      isContinuity: true),
            AudioInputSelector.Device(uid: "builtin", name: "MacBook Microphone",
                                      isDefault: false, isBluetooth: false, isVirtual: false),
        ]
        let choice = AudioInputSelector.choose(preference: .preferWired, devices: devices)
        XCTAssertEqual(choice.deviceUID, "builtin")
    }

    /// And with nothing better available it stays on the phone rather than
    /// refusing to record.
    func testAContinuityDefaultIsKeptWhenThereIsNoAlternative() {
        let devices = [
            AudioInputSelector.Device(uid: "iphone", name: "Alex’ iPhone Microphone",
                                      isDefault: true, isBluetooth: false, isVirtual: false,
                                      isContinuity: true),
        ]
        let choice = AudioInputSelector.choose(preference: .preferWired, devices: devices)
        XCTAssertNil(choice.deviceUID)
        XCTAssertEqual(choice.reason, "no_wired_alternative")
    }

}
