import CoreML
import FluidAudio
import Foundation
import PressTalkCore

/// Adapts the saved preference to the pinned Parakeet loader without selecting
/// a different speech model or permitting the other accelerator as a fallback.
struct TranscriptionComputeConfiguration {
    typealias ModelLoader = (URL, MLModelConfiguration) async throws -> MLModel

    let device: TranscriptionComputeDevice

    var computeUnits: MLComputeUnits {
        switch device {
        case .neuralEngine: return .cpuAndNeuralEngine
        case .gpu: return .cpuAndGPU
        }
    }

    var label: String { device.computeUnitsDescription }

    func makeModelConfiguration() -> MLModelConfiguration {
        // Preserve FluidAudio's pinned configuration defaults, changing only
        // the allowed processors. Decoder and joint stages use this value.
        let configuration = AsrModels.defaultConfiguration()
        configuration.computeUnits = computeUnits
        return configuration
    }

    /// Pass explicitly alongside `makeModelConfiguration()` so an upstream
    /// encoder-specific default cannot silently override the user's choice.
    var encoderComputeUnits: MLComputeUnits { computeUnits }

    /// Load the same cached v3 assets directly through Core ML. The dependency's
    /// general loader deletes and downloads its cache again after *any* loading
    /// error, including a processor-specific error. A settings change must never
    /// erase a working model cache or silently select another processor.
    func loadCachedParakeetModels(
        from directory: URL,
        modelLoader: ModelLoader = { try await MLModel.load(contentsOf: $0, configuration: $1) }
    ) async throws -> AsrModels {
        try Self.validateCachedParakeetModels(at: directory)
        let vocabulary = try Self.loadVocabulary(from: directory)
        let configuration = makeModelConfiguration()

        let preprocessor = try await loadModel(
            named: ModelNames.ASR.preprocessorFile, from: directory, computeUnits: .cpuOnly,
            using: modelLoader)
        let encoder = try await loadModel(
            named: ParakeetEncoderPrecision.int8.encoderFileName,
            from: directory, computeUnits: encoderComputeUnits, using: modelLoader)
        let decoder = try await loadModel(
            named: ModelNames.ASR.decoderFile, from: directory, computeUnits: computeUnits,
            using: modelLoader)
        let joint = try await loadModel(
            named: ModelNames.ASR.jointV3File, from: directory, computeUnits: computeUnits,
            using: modelLoader)
        try Task.checkCancellation()
        return AsrModels(
            encoder: encoder, preprocessor: preprocessor, decoder: decoder, joint: joint,
            configuration: configuration, vocabulary: vocabulary, version: .v3)
    }

    /// True only for a complete cache of the pinned v3 models. This checks files,
    /// not model execution; an invalid model is reported by Core ML at load time.
    static func cachedParakeetModelsArePresent(at directory: URL) -> Bool {
        (try? validateCachedParakeetModels(at: directory)) != nil
    }

    static func validateCachedParakeetModels(at directory: URL) throws {
        let modelNames = [
            ModelNames.ASR.preprocessorFile,
            ParakeetEncoderPrecision.int8.encoderFileName,
            ModelNames.ASR.decoderFile,
            ModelNames.ASR.jointV3File,
        ]
        let files = modelNames.flatMap { name in
            ["coremldata.bin", "model.mil", "weights/weight.bin"].map { "\(name)/\($0)" }
        } + [ModelNames.ASR.vocabularyFile]
        for relativePath in files {
            let path = directory.appendingPathComponent(relativePath)
            guard let values = try? path.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true, (values.fileSize ?? 0) > 0
            else { throw CachedModelError.missingAsset(relativePath) }
        }
    }

    /// Downloads missing assets without the dependency's load-and-delete
    /// recovery path and without compiling them on an unselected accelerator.
    /// The caller decides when first-download setup is allowed; mode changes
    /// with a valid cache never need this method.
    static func downloadParakeetModelsIfMissing(to directory: URL) async throws {
        guard !cachedParakeetModelsArePresent(at: directory) else { return }
        guard directory.lastPathComponent == Repo.parakeetV3.folderName else {
            throw CachedModelError.invalidDownloadDirectory
        }
        try await DownloadUtils.downloadRepo(
            .parakeetV3, to: directory.deletingLastPathComponent(),
            variant: ParakeetEncoderPrecision.int8.rawValue)
        try validateCachedParakeetModels(at: directory)
    }

    private func loadModel(
        named name: String, from directory: URL, computeUnits: MLComputeUnits,
        using loader: ModelLoader
    ) async throws -> MLModel {
        try Task.checkCancellation()
        let configuration = makeModelConfiguration()
        configuration.computeUnits = computeUnits
        // Match the pinned dependency's actual per-model loader configuration.
        configuration.allowLowPrecisionAccumulationOnGPU = true
        let model = try await loader(directory.appendingPathComponent(name), configuration)
        try Task.checkCancellation()
        return model
    }

    private static func loadVocabulary(from directory: URL) throws -> [Int: String] {
        let data = try Data(contentsOf: directory.appendingPathComponent(ModelNames.ASR.vocabularyFile))
        let value = try JSONSerialization.jsonObject(with: data)
        if let tokens = value as? [String], !tokens.isEmpty {
            return Dictionary(uniqueKeysWithValues: tokens.enumerated().map { ($0.offset, $0.element) })
        }
        if let tokens = value as? [String: String], !tokens.isEmpty {
            var vocabulary: [Int: String] = [:]
            for (key, token) in tokens {
                guard let index = Int(key), index >= 0, vocabulary[index] == nil else {
                    throw CachedModelError.invalidVocabulary
                }
                vocabulary[index] = token
            }
            return vocabulary
        }
        throw CachedModelError.invalidVocabulary
    }

    enum CachedModelError: LocalizedError {
        case missingAsset(String)
        case invalidVocabulary
        case invalidDownloadDirectory

        var errorDescription: String? {
            switch self {
            case .missingAsset(let path): return "The local speech model is missing \(path)."
            case .invalidVocabulary: return "The local speech model vocabulary is invalid."
            case .invalidDownloadDirectory: return "The local speech model download directory is invalid."
            }
        }
    }
}
