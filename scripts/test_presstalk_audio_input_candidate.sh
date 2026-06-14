#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/presstalk-audio-input-candidate-test.XXXXXX")"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

cp "$REPO_ROOT/Sources/PressTalkCore/AudioInputDeviceCandidate.swift" "$TEST_TMPDIR/AudioInputDeviceCandidate.swift"
cat > "$TEST_TMPDIR/main.swift" <<'SWIFT'
import CoreAudio
import Darwin
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let bluetoothTransport = AudioInputDeviceCandidate(
    id: 1,
    name: "Headset Microphone",
    inputChannels: 1,
    isDefault: true,
    transportType: kAudioDeviceTransportTypeBluetooth
)
let genericBluetoothName = AudioInputDeviceCandidate(
    id: 2,
    name: "Bluetooth Conference Mic",
    inputChannels: 1,
    isDefault: false,
    transportType: nil
)
let productNameWithoutTransport = AudioInputDeviceCandidate(
    id: 3,
    name: "AirPods Pro",
    inputChannels: 1,
    isDefault: false,
    transportType: nil
)

expect(bluetoothTransport.isBluetoothLike, "Bluetooth transport must be classified as Bluetooth-like")
expect(genericBluetoothName.isBluetoothLike, "Generic Bluetooth device names must be classified as Bluetooth-like")
expect(!productNameWithoutTransport.isBluetoothLike, "Product-specific names must not drive Bluetooth classification")

let usbInput = AudioInputDeviceCandidate(
    id: 10,
    name: "USB Microphone",
    inputChannels: 2,
    isDefault: false,
    transportType: kAudioDeviceTransportTypeUSB
)
let virtualInput = AudioInputDeviceCandidate(
    id: 11,
    name: "Virtual Microphone",
    inputChannels: 2,
    isDefault: false,
    transportType: kAudioDeviceTransportTypeVirtual
)
let defaultBluetoothInput = AudioInputDeviceCandidate(
    id: 12,
    name: "Headset Microphone",
    inputChannels: 1,
    isDefault: true,
    transportType: kAudioDeviceTransportTypeBluetooth
)
let defaultUSBInput = AudioInputDeviceCandidate(
    id: 13,
    name: "USB Microphone",
    inputChannels: 2,
    isDefault: true,
    transportType: kAudioDeviceTransportTypeUSB
)

expect(usbInput.isPhysicalInput, "USB input must be treated as physical")
expect(!virtualInput.isPhysicalInput, "Virtual input must not be treated as physical")
expect(!defaultBluetoothInput.isPhysicalInput, "Bluetooth input must not be treated as physical")
expect(defaultUSBInput.selectionScore > defaultBluetoothInput.selectionScore, "Default USB input must outrank default Bluetooth input")
expect(defaultUSBInput.selectionScore > virtualInput.selectionScore, "Default USB input must outrank virtual input")
expect(defaultBluetoothInput.selectionScore < virtualInput.selectionScore, "Bluetooth input must remain lower priority than virtual input")
SWIFT

swiftc "$TEST_TMPDIR/AudioInputDeviceCandidate.swift" "$TEST_TMPDIR/main.swift" -o "$TEST_TMPDIR/audio-input-candidate-test"
"$TEST_TMPDIR/audio-input-candidate-test"

echo "PASS audio_input_candidate"
