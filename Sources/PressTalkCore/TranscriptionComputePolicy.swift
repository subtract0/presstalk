/// The processor family the user permits for local speech recognition.
///
/// CPU support is always permitted. Core ML chooses which supported operations
/// run on the selected accelerator; the preference is not a utilization meter.
public enum TranscriptionComputeDevice: String, CaseIterable, Equatable, Sendable {
    case neuralEngine = "ane"
    case gpu = "gpu"

    public static let `default`: Self = .neuralEngine
    public static let preferenceKey = "PressTalk.TranscriptionComputeDevice"

    /// A missing or invalid saved preference retains the released ANE default.
    /// Legacy shell variables are deliberately not part of this decision.
    public init(storageValue: String?) {
        self = storageValue.flatMap(Self.init(rawValue:)) ?? .default
    }

    public var storageValue: String { rawValue }

    public var displayName: String {
        switch self {
        case .neuralEngine: return "Apple Neural Engine"
        case .gpu: return "GPU"
        }
    }

    public var detail: String {
        switch self {
        case .neuralEngine:
            return "Uses the Neural Engine with CPU support. Transcription stays on this Mac."
        case .gpu:
            return "Uses the GPU with CPU support. Transcription stays on this Mac."
        }
    }

    /// Stable diagnostics value describing allowed processors, not measured use.
    public var computeUnitsDescription: String {
        switch self {
        case .neuralEngine: return "cpuAndNeuralEngine"
        case .gpu: return "cpuAndGPU"
        }
    }
}

/// Keeps preference changes from replacing a recognizer while it is in use.
///
/// The app owns its model and task lifetime. It should persist the user's
/// requested device immediately, keep `loadedDevice` separate, and reconsider
/// this decision after capture, processing, or model loading finishes.
public enum TranscriptionComputePolicy {
    public enum ReloadDecision: Equatable, Sendable {
        case unchanged
        case waitUntilIdle
        case reload(TranscriptionComputeDevice)
    }

    public static func reloadDecision(
        requestedDevice: TranscriptionComputeDevice,
        loadedDevice: TranscriptionComputeDevice?,
        isRecording: Bool,
        isProcessing: Bool,
        isLoading: Bool
    ) -> ReloadDecision {
        // A load already in flight may carry a superseded preference. Even
        // selecting the currently loaded device must wait for that task's
        // completion; starting another load would permit out-of-order commits.
        guard !isLoading else { return .waitUntilIdle }
        guard requestedDevice != loadedDevice else { return .unchanged }
        guard !isRecording && !isProcessing else { return .waitUntilIdle }
        return .reload(requestedDevice)
    }

    /// A completed load must not replace the active recognizer after the user
    /// has selected another device. Discard it and reconsider the latest choice.
    /// Call this while holding the same state lock used for the model assignment.
    public static func acceptsCompletedLoad(
        device: TranscriptionComputeDevice,
        requestedDevice: TranscriptionComputeDevice
    ) -> Bool {
        device == requestedDevice
    }
}
