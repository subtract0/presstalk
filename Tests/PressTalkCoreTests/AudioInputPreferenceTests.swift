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

    // MARK: the default must not touch anything

    func testTheDefaultIsSystemDefault() {
        XCTAssertEqual(AudioInputPreference.default, .systemDefault)
        XCTAssertEqual(AudioInputPreference(storageValue: nil), .systemDefault)
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

    /// An unrecognised stored value must not resurrect the old override.
    func testACorruptPreferenceFallsBackToSystemDefault() {
        XCTAssertEqual(AudioInputPreference(storageValue: "avoid_bluetooth_v1"),
                       .systemDefault)
        XCTAssertEqual(AudioInputPreference(storageValue: "device:"), .systemDefault)
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

    /// Unplugging the chosen microphone must not break dictation, and must not
    /// silently forget the preference either.
    func testAnUnpluggedChoiceFallsBackWithoutLosingThePreference() {
        let preference = AudioInputPreference.specificDevice(uid: "shure")
        let choice = AudioInputSelector.choose(
            preference: preference,
            devices: [device("builtin", isDefault: true)])
        XCTAssertNil(choice.deviceUID)
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
