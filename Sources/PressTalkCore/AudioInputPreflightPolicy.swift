import Foundation

/// Decides whether the audio input is safe to hand to WhisperKit.
///
/// WHY THIS EXISTS
/// `AVAudioNode.installTapOnBus` raises an OBJECTIVE-C exception when the format
/// it is given disagrees with the input node. Swift `do/catch` cannot catch an
/// NSException, so it becomes SIGABRT and kills the app mid-dictation. Three
/// crashes -- 2026-08-29, 2026-08-30, 2026-09-03 -- were all this one signature,
/// inside `AUGraphNodeBaseV3::CreateRecordingTap`.
///
/// The trigger is upstream: WhisperKit 0.16.0 builds the tap format by MIXING
/// two different formats (AudioProcessor.swift:984-987), taking the sample rate
/// from `inputFormat(forBus:)` (hardware) and the channel count and common
/// format from `outputFormat(forBus:)` (node output). Those agree while the
/// audio device is stable and diverge exactly when it changes.
///
/// This type holds only the DECISION, with no AVFoundation dependency, so it can
/// be tested. Reading the live device stays at the call site. That split matters:
/// this guard sits directly in the dictation path, and a false positive here
/// would block dictation entirely -- a worse failure than the crash it prevents.
public struct AudioInputPreflightPolicy {
    /// Sample rates are Doubles; treat a sub-Hz difference as agreement.
    public let sampleRateToleranceHz: Double

    public init(sampleRateToleranceHz: Double = 1.0) {
        self.sampleRateToleranceHz = sampleRateToleranceHz
    }

    /// Returns nil when capture is safe, or a human-readable reason to refuse.
    public func failureReason(hardwareSampleRate: Double,
                              nodeSampleRate: Double,
                              nodeChannelCount: UInt32,
                              canBuildTapFormat: Bool) -> String? {
        if !hardwareSampleRate.isFinite || hardwareSampleRate <= 0 {
            return "no usable input device (hardware sample rate is \(Self.fmt(hardwareSampleRate)))"
        }
        if !nodeSampleRate.isFinite || nodeSampleRate <= 0 {
            return "input node reports no sample rate (\(Self.fmt(nodeSampleRate)))"
        }
        if nodeChannelCount == 0 {
            return "input device reports 0 channels"
        }
        if abs(hardwareSampleRate - nodeSampleRate) > sampleRateToleranceHz {
            return "input format mismatch (hardware \(Self.fmt(hardwareSampleRate)) Hz vs node "
                 + "\(Self.fmt(nodeSampleRate)) Hz) -- the audio device likely changed"
        }
        if !canBuildTapFormat {
            return "cannot build a tap format for \(Self.fmt(hardwareSampleRate)) Hz / \(nodeChannelCount) channel(s)"
        }
        return nil
    }

    private static func fmt(_ v: Double) -> String {
        v.isFinite ? String(format: "%.0f", v) : "\(v)"
    }
}
