@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation
import WhisperKit

@main
struct PressTalkAsrBench {
    static func main() async {
        do {
            try await run()
        } catch {
            fputs("presstalk-asr-bench: \(error)\n", stderr)
            exit(1)
        }
    }

    private static func run() async throws {
        let options = try BenchOptions.parse(CommandLine.arguments.dropFirst())
        if options.help {
            print(BenchOptions.usage)
            return
        }

        if options.offline {
            DownloadUtils.enforceOffline = true
        }

        let inputURL = URL(fileURLWithPath: options.inputPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: inputURL.path) else {
            throw BenchError.inputMissing(inputURL.path)
        }

        var reports: [BenchReport] = []
        for runIndex in 1...options.runs {
            let report: BenchReport
            switch options.backend.kind {
            case .parakeetV3:
                report = try await runParakeetV3(inputURL: inputURL, options: options, runIndex: runIndex)
            case .streaming:
                report = try await runStreaming(inputURL: inputURL, options: options, runIndex: runIndex)
            case .whisperKit:
                report = try await runWhisperKit(inputURL: inputURL, options: options, runIndex: runIndex)
            }
            reports.append(report)
            print(report.prettyPrinted)

            if options.json {
                let encoded = try JSONEncoder.presstalk.encode(report)
                print(String(decoding: encoded, as: UTF8.self))
            }
        }

        if reports.count > 1 {
            let medianReport = BenchAggregate(reports: reports)
            print(medianReport.prettyPrinted)
        }
    }

    private static func runParakeetV3(
        inputURL: URL,
        options: BenchOptions,
        runIndex: Int
    ) async throws -> BenchReport {
        let loadStart = Date()
        let configuration = AsrModels.defaultConfiguration()
        let encoderComputeUnits = options.backend.encoderComputeUnits
        let models = try await AsrModels.downloadAndLoad(
            configuration: configuration,
            version: .v3,
            encoderComputeUnits: encoderComputeUnits,
            progressHandler: options.progressHandler
        )
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        let loadSeconds = Date().timeIntervalSince(loadStart)

        let transcribeStart = Date()
        var decoderState = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let language = options.language.fluidLanguage
        let result = try await manager.transcribe(inputURL, decoderState: &decoderState, language: language)
        let totalSeconds = Date().timeIntervalSince(transcribeStart)
        let audioDurationSeconds = try inputURL.audioDurationSeconds()

        let transcript = result.text
        let accuracy = options.accuracy(for: transcript)
        return BenchReport(
            backend: options.backend.rawValue,
            runIndex: runIndex,
            inputPath: inputURL.path,
            audioDurationSeconds: audioDurationSeconds,
            loadSeconds: loadSeconds,
            totalProcessingSeconds: totalSeconds,
            finalizationSeconds: totalSeconds,
            maxProcessSliceSeconds: nil,
            rtfx: audioDurationSeconds / max(totalSeconds, 0.000_001),
            partialUpdates: 0,
            transcript: transcript,
            confidence: Double(result.confidence),
            wordErrorRate: accuracy?.wordErrorRate,
            characterErrorRate: accuracy?.characterErrorRate,
            referenceText: accuracy?.reference,
            notes: options.backend.note
        )
    }

    private static func runStreaming(
        inputURL: URL,
        options: BenchOptions,
        runIndex: Int
    ) async throws -> BenchReport {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = options.backend.streamingComputeUnits
        let manager = options.backend.streamingVariant.createManager(configuration: configuration)

        let partialUpdates = LockedCounter()
        await manager.setPartialTranscriptCallback { partial in
            if !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                partialUpdates.increment()
            }
        }

        let loadStart = Date()
        try await manager.loadModels()
        let loadSeconds = Date().timeIntervalSince(loadStart)

        let audioFile = try AVAudioFile(forReading: inputURL)
        let audioDurationSeconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        let feedFrames = AVAudioFrameCount(
            max(1, Int(audioFile.processingFormat.sampleRate * options.feedSeconds))
        )

        let processStart = Date()
        var maxSliceSeconds = 0.0
        while audioFile.framePosition < audioFile.length {
            let remainingFrames = audioFile.length - audioFile.framePosition
            let frameCount = AVAudioFrameCount(min(Int64(feedFrames), remainingFrames))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: audioFile.processingFormat,
                frameCapacity: frameCount
            ) else {
                throw BenchError.bufferAllocationFailed
            }

            try audioFile.read(into: buffer, frameCount: frameCount)
            try await manager.appendAudio(buffer)

            let sliceStart = Date()
            try await manager.processBufferedAudio()
            maxSliceSeconds = max(maxSliceSeconds, Date().timeIntervalSince(sliceStart))
        }

        let finishStart = Date()
        let transcript = try await manager.finish()
        let finalizationSeconds = Date().timeIntervalSince(finishStart)
        let totalSeconds = Date().timeIntervalSince(processStart)

        let accuracy = options.accuracy(for: transcript)
        return BenchReport(
            backend: options.backend.rawValue,
            runIndex: runIndex,
            inputPath: inputURL.path,
            audioDurationSeconds: audioDurationSeconds,
            loadSeconds: loadSeconds,
            totalProcessingSeconds: totalSeconds,
            finalizationSeconds: finalizationSeconds,
            maxProcessSliceSeconds: maxSliceSeconds,
            rtfx: audioDurationSeconds / max(totalSeconds, 0.000_001),
            partialUpdates: partialUpdates.value,
            transcript: transcript,
            confidence: nil,
            wordErrorRate: accuracy?.wordErrorRate,
            characterErrorRate: accuracy?.characterErrorRate,
            referenceText: accuracy?.reference,
            notes: options.backend.note
        )
    }

    private static func runWhisperKit(
        inputURL: URL,
        options: BenchOptions,
        runIndex: Int
    ) async throws -> BenchReport {
        let model = "openai_whisper-large-v3-v20240930_turbo_632MB"
        let downloadBase = whisperModelSearchRoots().first
        let localModelFolder = localWhisperModelFolder(for: model)
        let localTokenizerFolder = localWhisperTokenizerFolder(for: model)
        let shouldDownload = !options.offline && localModelFolder == nil

        let loadStart = Date()
        let config = WhisperKitConfig(
            model: model,
            downloadBase: downloadBase,
            modelFolder: localModelFolder,
            tokenizerFolder: localTokenizerFolder,
            computeOptions: ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU,
                prefillCompute: .cpuOnly
            ),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: shouldDownload
        )
        let whisperKit = try await WhisperKit(config)
        let loadSeconds = Date().timeIntervalSince(loadStart)

        let decodingOptions = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: options.language.whisperLanguage,
            temperature: 0,
            usePrefillPrompt: true,
            usePrefillCache: true,
            detectLanguage: options.language == .auto,
            skipSpecialTokens: true,
            withoutTimestamps: true,
            wordTimestamps: false
        )

        let transcribeStart = Date()
        let results = try await whisperKit.transcribe(audioPath: inputURL.path, decodeOptions: decodingOptions)
        let totalSeconds = Date().timeIntervalSince(transcribeStart)
        let transcript = results.map(\.text).joined(separator: " ").cleanedTranscript
        let audioDurationSeconds = try inputURL.audioDurationSeconds()
        let accuracy = options.accuracy(for: transcript)

        return BenchReport(
            backend: options.backend.rawValue,
            runIndex: runIndex,
            inputPath: inputURL.path,
            audioDurationSeconds: audioDurationSeconds,
            loadSeconds: loadSeconds,
            totalProcessingSeconds: totalSeconds,
            finalizationSeconds: totalSeconds,
            maxProcessSliceSeconds: nil,
            rtfx: audioDurationSeconds / max(totalSeconds, 0.000_001),
            partialUpdates: 0,
            transcript: transcript,
            confidence: nil,
            wordErrorRate: accuracy?.wordErrorRate,
            characterErrorRate: accuracy?.characterErrorRate,
            referenceText: accuracy?.reference,
            notes: options.backend.note
        )
    }
}

private struct BenchOptions {
    var inputPath = ""
    var backend: BenchBackend = .parakeetV3ANE
    var language: BenchLanguage = .auto
    var runs = 1
    var feedSeconds = 0.10
    var reference: String?
    var offline = false
    var json = false
    var showProgress = false
    var help = false

    var progressHandler: DownloadUtils.ProgressHandler? {
        guard showProgress else { return nil }
        return { progress in
            let percent = Int((progress.fractionCompleted * 100.0).rounded())
            print("download_progress=\(percent)%")
        }
    }

    static let usage = """
    Usage:
      presstalk-asr-bench --input <audio-file> [--backend <name>] [options]

    Backends:
      parakeet-v3-ane       Parakeet TDT 0.6B v3, encoder on CPU+ANE
      parakeet-v3-gpu       Parakeet TDT 0.6B v3, encoder on CPU+GPU
      parakeet-eou-160      Parakeet EOU 120M true streaming, 160ms tier
      parakeet-eou-320      Parakeet EOU 120M true streaming, 320ms tier
      parakeet-eou-1280     Parakeet EOU 120M true streaming, 1280ms tier
      nemotron-560          Nemotron English streaming 0.6B, 560ms tier
      nemotron-1120         Nemotron English streaming 0.6B, 1120ms tier
      nemotron-2240         Nemotron English streaming 0.6B, 2240ms tier
      stock-v1-gpu          PressTalk v1 WhisperKit large-v3-turbo, CPU+GPU, no ANE

    Options:
      --language <auto|en|de|fr|es|it|pt|...>   v3 script hint; streaming ignores this
      --reference <text-or-path>                 reference text for WER/CER scoring
      --runs <n>                                repeat benchmark, default 1
      --feed-ms <n>                             simulated streaming feed interval, default 100
      --offline                                 fail instead of downloading missing models
      --progress                                print model download progress
      --json                                    print JSON report line after each run
      --help                                    print this help
    """

    static func parse(_ rawArguments: ArraySlice<String>) throws -> BenchOptions {
        var options = BenchOptions()
        var arguments = Array(rawArguments)

        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--input":
                options.inputPath = try arguments.popValue(after: argument)
            case "--backend":
                let value = try arguments.popValue(after: argument)
                guard let backend = BenchBackend(rawValue: value) else {
                    throw BenchError.invalidBackend(value)
                }
                options.backend = backend
            case "--language":
                let value = try arguments.popValue(after: argument)
                guard let language = BenchLanguage(rawValue: value) else {
                    throw BenchError.invalidLanguage(value)
                }
                options.language = language
            case "--runs":
                let value = try arguments.popValue(after: argument)
                guard let runs = Int(value), runs > 0 else {
                    throw BenchError.invalidNumber("--runs", value)
                }
                options.runs = runs
            case "--feed-ms":
                let value = try arguments.popValue(after: argument)
                guard let feedMilliseconds = Double(value), feedMilliseconds > 0 else {
                    throw BenchError.invalidNumber("--feed-ms", value)
                }
                options.feedSeconds = feedMilliseconds / 1000.0
            case "--reference":
                let value = try arguments.popValue(after: argument)
                options.reference = try Self.loadReference(value)
            case "--offline":
                options.offline = true
            case "--progress":
                options.showProgress = true
            case "--json":
                options.json = true
            case "--help", "-h":
                options.help = true
            default:
                throw BenchError.unknownArgument(argument)
            }
        }

        if !options.help && options.inputPath.isEmpty {
            throw BenchError.missingInput
        }

        return options
    }

    private static func loadReference(_ value: String) throws -> String {
        let expanded = (value as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return try String(contentsOfFile: expanded, encoding: .utf8)
        }
        return value
    }

    func accuracy(for transcript: String) -> AccuracyScores? {
        guard let reference else { return nil }
        return AccuracyScores(reference: reference, hypothesis: transcript)
    }
}

private enum BenchBackend: String {
    case parakeetV3ANE = "parakeet-v3-ane"
    case parakeetV3GPU = "parakeet-v3-gpu"
    case parakeetEOU160 = "parakeet-eou-160"
    case parakeetEOU320 = "parakeet-eou-320"
    case parakeetEOU1280 = "parakeet-eou-1280"
    case nemotron560 = "nemotron-560"
    case nemotron1120 = "nemotron-1120"
    case nemotron2240 = "nemotron-2240"
    case stockV1GPU = "stock-v1-gpu"

    enum Kind {
        case parakeetV3
        case streaming
        case whisperKit
    }

    var kind: Kind {
        switch self {
        case .parakeetV3ANE, .parakeetV3GPU:
            return .parakeetV3
        case .parakeetEOU160, .parakeetEOU320, .parakeetEOU1280, .nemotron560, .nemotron1120, .nemotron2240:
            return .streaming
        case .stockV1GPU:
            return .whisperKit
        }
    }

    var encoderComputeUnits: MLComputeUnits? {
        switch self {
        case .parakeetV3GPU:
            return .cpuAndGPU
        default:
            return nil
        }
    }

    var streamingComputeUnits: MLComputeUnits {
        switch self {
        case .parakeetEOU160, .parakeetEOU320, .parakeetEOU1280:
            return .cpuAndNeuralEngine
        case .nemotron560, .nemotron1120, .nemotron2240:
            return .cpuAndNeuralEngine
        case .parakeetV3ANE, .parakeetV3GPU, .stockV1GPU:
            return .cpuAndNeuralEngine
        }
    }

    var streamingVariant: StreamingModelVariant {
        switch self {
        case .parakeetEOU160:
            return .parakeetEou160ms
        case .parakeetEOU320:
            return .parakeetEou320ms
        case .parakeetEOU1280:
            return .parakeetEou1280ms
        case .nemotron560:
            return .nemotron560ms
        case .nemotron1120:
            return .nemotron1120ms
        case .nemotron2240:
            return .nemotron2240ms
        case .parakeetV3ANE, .parakeetV3GPU, .stockV1GPU:
            return .parakeetEou160ms
        }
    }

    var note: String {
        switch self {
        case .parakeetV3ANE:
            return "Parakeet v3 batch/sliding-window; default encoder placement is CPU+ANE."
        case .parakeetV3GPU:
            return "Parakeet v3 batch/sliding-window; encoder forced to CPU+GPU for throughput comparison."
        case .parakeetEOU160:
            return "True streaming Parakeet EOU 120M, lowest-latency tier."
        case .parakeetEOU320:
            return "True streaming Parakeet EOU 120M, balanced tier."
        case .parakeetEOU1280:
            return "True streaming Parakeet EOU 120M, highest-throughput tier."
        case .nemotron560:
            return "True streaming Nemotron 0.6B English, lowest-latency tier."
        case .nemotron1120:
            return "True streaming Nemotron 0.6B English, balanced tier."
        case .nemotron2240:
            return "True streaming Nemotron 0.6B English, highest-throughput tier."
        case .stockV1GPU:
            return "Frozen PressTalk v1 route: WhisperKit large-v3-turbo with cpu-gpu-no-ane compute placement."
        }
    }
}

private enum BenchLanguage: String {
    case auto
    case english = "en"
    case german = "de"
    case french = "fr"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    case dutch = "nl"
    case polish = "pl"
    case czech = "cs"
    case slovak = "sk"
    case slovenian = "sl"
    case croatian = "hr"
    case russian = "ru"
    case ukrainian = "uk"
    case greek = "el"

    var fluidLanguage: Language? {
        switch self {
        case .auto:
            return nil
        case .english:
            return .english
        case .german:
            return .german
        case .french:
            return .french
        case .spanish:
            return .spanish
        case .italian:
            return .italian
        case .portuguese:
            return .portuguese
        case .dutch:
            return .dutch
        case .polish:
            return .polish
        case .czech:
            return .czech
        case .slovak:
            return .slovak
        case .slovenian:
            return .slovenian
        case .croatian:
            return .croatian
        case .russian:
            return .russian
        case .ukrainian:
            return .ukrainian
        case .greek:
            return .greek
        }
    }

    var whisperLanguage: String? {
        switch self {
        case .auto:
            return nil
        default:
            return rawValue
        }
    }
}

private struct AccuracyScores: Codable {
    let reference: String
    let wordErrorRate: Double
    let characterErrorRate: Double

    init(reference: String, hypothesis: String) {
        self.reference = reference
        let referenceWords = Self.normalizedWords(reference)
        let hypothesisWords = Self.normalizedWords(hypothesis)
        let referenceCharacters = Array(Self.normalizedText(reference))
        let hypothesisCharacters = Array(Self.normalizedText(hypothesis))
        wordErrorRate = Self.errorRate(reference: referenceWords, hypothesis: hypothesisWords)
        characterErrorRate = Self.errorRate(reference: referenceCharacters, hypothesis: hypothesisCharacters)
    }

    private static func normalizedWords(_ text: String) -> [String] {
        normalizedText(text)
            .split(separator: " ")
            .map(String.init)
    }

    private static func normalizedText(_ text: String) -> String {
        let folded = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var normalized = ""
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
            } else {
                normalized.append(" ")
            }
        }
        return normalized
            .split(separator: " ")
            .joined(separator: " ")
    }

    private static func errorRate<T: Equatable>(reference: [T], hypothesis: [T]) -> Double {
        guard !reference.isEmpty else { return hypothesis.isEmpty ? 0 : 1 }
        let distance = levenshtein(reference, hypothesis)
        return Double(distance) / Double(reference.count)
    }

    private static func levenshtein<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1)
                current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}

private struct BenchReport: Codable {
    let backend: String
    let runIndex: Int
    let inputPath: String
    let audioDurationSeconds: Double
    let loadSeconds: Double
    let totalProcessingSeconds: Double
    let finalizationSeconds: Double
    let maxProcessSliceSeconds: Double?
    let rtfx: Double
    let partialUpdates: Int
    let transcript: String
    let confidence: Double?
    let wordErrorRate: Double?
    let characterErrorRate: Double?
    let referenceText: String?
    let notes: String

    var prettyPrinted: String {
        var lines = [
            "backend=\(backend) run=\(runIndex)",
            "audio=\(audioDurationSeconds.formattedSeconds) load=\(loadSeconds.formattedSeconds) processing=\(totalProcessingSeconds.formattedSeconds) final=\(finalizationSeconds.formattedSeconds) rtfx=\(rtfx.formattedNumber)",
        ]
        if let maxProcessSliceSeconds {
            lines.append("max_process_slice=\(maxProcessSliceSeconds.formattedSeconds) partial_updates=\(partialUpdates)")
        }
        if let confidence {
            lines.append("confidence=\(confidence.formattedNumber)")
        }
        if let wordErrorRate, let characterErrorRate {
            lines.append("wer=\(wordErrorRate.formattedPercent) cer=\(characterErrorRate.formattedPercent)")
        }
        lines.append("transcript=\(transcript)")
        return lines.joined(separator: "\n")
    }
}

private struct BenchAggregate {
    let reports: [BenchReport]

    var prettyPrinted: String {
        let processing = reports.map(\.totalProcessingSeconds).median
        let final = reports.map(\.finalizationSeconds).median
        let rtfx = reports.map(\.rtfx).median
        var parts = ["median runs=\(reports.count) processing=\(processing.formattedSeconds) final=\(final.formattedSeconds) rtfx=\(rtfx.formattedNumber)"]
        let werValues = reports.compactMap(\.wordErrorRate)
        let cerValues = reports.compactMap(\.characterErrorRate)
        if !werValues.isEmpty, !cerValues.isEmpty {
            parts.append("wer=\(werValues.median.formattedPercent) cer=\(cerValues.median.formattedPercent)")
        }
        return parts.joined(separator: " ")
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    func increment() {
        lock.lock()
        storage += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private enum BenchError: Error, CustomStringConvertible {
    case missingInput
    case inputMissing(String)
    case invalidBackend(String)
    case invalidLanguage(String)
    case invalidNumber(String, String)
    case missingValue(String)
    case unknownArgument(String)
    case bufferAllocationFailed

    var description: String {
        switch self {
        case .missingInput:
            return "Missing --input <audio-file>.\n\(BenchOptions.usage)"
        case .inputMissing(let path):
            return "Input file does not exist: \(path)"
        case .invalidBackend(let value):
            return "Invalid backend: \(value)"
        case .invalidLanguage(let value):
            return "Invalid language: \(value)"
        case .invalidNumber(let flag, let value):
            return "Invalid numeric value for \(flag): \(value)"
        case .missingValue(let flag):
            return "Missing value after \(flag)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        }
    }
}

private extension Array where Element == String {
    mutating func popValue(after flag: String) throws -> String {
        guard !isEmpty else { throw BenchError.missingValue(flag) }
        return removeFirst()
    }
}

private extension Array where Element == Double {
    var median: Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2.0
        }
        return sorted[middle]
    }
}

private extension JSONEncoder {
    static var presstalk: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private extension URL {
    func audioDurationSeconds() throws -> Double {
        let audioFile = try AVAudioFile(forReading: self)
        return Double(audioFile.length) / audioFile.processingFormat.sampleRate
    }
}

private extension String {
    var cleanedTranscript: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

private extension Double {
    var formattedSeconds: String {
        String(format: "%.3fs", self)
    }

    var formattedNumber: String {
        String(format: "%.2f", self)
    }

    var formattedPercent: String {
        String(format: "%.2f%%", self * 100.0)
    }
}

private func whisperModelSearchRoots() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
        home.appendingPathComponent("Library/Application Support/JarvisTap/Models", isDirectory: true)
    ]
}

private func whisperTokenizerSearchRoots() -> [URL] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
        home.appendingPathComponent("Library/Application Support/JarvisTap/Tokenizers", isDirectory: true),
        home.appendingPathComponent("Library/Application Support/JarvisTap/Models", isDirectory: true)
    ]
}

private func localWhisperModelFolder(for model: String) -> String? {
    for root in whisperModelSearchRoots() {
        for folder in localWhisperModelFolderCandidates(root: root, model: model) {
            if isUsableLocalWhisperModelFolder(folder, model: model) {
                return folder.path
            }
        }
    }
    return nil
}

private func localWhisperModelFolderCandidates(root: URL, model: String) -> [URL] {
    let repositoryPath = "argmaxinc/whisperkit-coreml"
    return [
        root
            .appendingPathComponent(repositoryPath, isDirectory: true)
            .appendingPathComponent(model, isDirectory: true),
        root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(repositoryPath, isDirectory: true)
            .appendingPathComponent(model, isDirectory: true)
    ]
}

private func localWhisperTokenizerFolder(for model: String) -> URL? {
    guard let tokenizerModelName = whisperTokenizerModelName(for: model) else { return nil }
    for root in whisperTokenizerSearchRoots() {
        for folder in localWhisperTokenizerFolderCandidates(root: root, tokenizerModelName: tokenizerModelName) {
            let tokenizerPath = folder.appendingPathComponent("tokenizer.json")
            let tokenizerConfigPath = folder.appendingPathComponent("tokenizer_config.json")
            if FileManager.default.fileExists(atPath: tokenizerPath.path),
               FileManager.default.fileExists(atPath: tokenizerConfigPath.path) {
                return folder
            }
        }
    }
    return nil
}

private func whisperTokenizerModelName(for model: String) -> String? {
    switch model {
    case let name where name.contains("whisper-large-v3"):
        return "whisper-large-v3"
    default:
        return nil
    }
}

private func localWhisperTokenizerFolderCandidates(root: URL, tokenizerModelName: String) -> [URL] {
    return [
        root
            .appendingPathComponent("openai", isDirectory: true)
            .appendingPathComponent(tokenizerModelName, isDirectory: true),
        root
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("openai", isDirectory: true)
            .appendingPathComponent(tokenizerModelName, isDirectory: true)
    ]
}

private func isUsableLocalWhisperModelFolder(_ folder: URL, model: String) -> Bool {
    requiredWhisperModelFiles(for: model).allSatisfy { relativePath in
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(relativePath).path)
    }
}

private func requiredWhisperModelFiles(for model: String) -> [String] {
    switch model {
    case let name where name.contains("whisper-large-v3") && name.contains("turbo"):
        return [
            "config.json",
            "generation_config.json",
            "AudioEncoder.mlmodelc/model.mil",
            "AudioEncoder.mlmodelc/weights/weight.bin",
            "MelSpectrogram.mlmodelc/model.mil",
            "MelSpectrogram.mlmodelc/weights/weight.bin",
            "TextDecoder.mlmodelc/model.mil",
            "TextDecoder.mlmodelc/weights/weight.bin",
            "TextDecoderContextPrefill.mlmodelc/model.mil",
            "TextDecoderContextPrefill.mlmodelc/weights/weight.bin"
        ]
    default:
        return []
    }
}
