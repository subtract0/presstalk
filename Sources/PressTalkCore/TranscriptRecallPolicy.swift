import Foundation

public struct TranscriptRecallPolicy {
    public struct Decision {
        public let logMessage: String
        public let fallbackReason: String?
    }

    public let chunkedWhisperFallbackMinimumCaptureSeconds: TimeInterval
    public let textPolicy: TranscriptTextPolicy

    public init(
        chunkedWhisperFallbackMinimumCaptureSeconds: TimeInterval = 7.5,
        textPolicy: TranscriptTextPolicy = TranscriptTextPolicy()
    ) {
        self.chunkedWhisperFallbackMinimumCaptureSeconds = chunkedWhisperFallbackMinimumCaptureSeconds
        self.textPolicy = textPolicy
    }

    public func wordCount(_ text: String) -> Int {
        tokens(text).count
    }

    public func tokens(_ text: String) -> [String] {
        textPolicy.tokens(text)
    }

    public func shouldDeferShortWhisperCandidateForRecall(
        whisperTranscript: String,
        parakeetTranscript: String?,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Decision? {
        if let decision = shouldDeferShortWhisperCandidateForParakeetRecall(
            whisperTranscript: whisperTranscript,
            parakeetTranscript: parakeetTranscript,
            captureDurationSeconds: captureDurationSeconds,
            context: context
        ) {
            return decision
        }
        return shouldDeferShortWhisperCandidateForStreamingRecall(
            whisperTranscript: whisperTranscript,
            streamingTranscript: streamingTranscript,
            captureDurationSeconds: captureDurationSeconds,
            context: context
        )
    }

    public func shouldRejectWhisperCandidateForRecallQuality(
        whisperTranscript: String,
        parakeetTranscript: String?,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Decision? {
        let recallTranscript = parakeetTranscript ?? streamingTranscript
        guard let recallTranscript else { return nil }

        let recallWordCount = wordCount(recallTranscript)
        let whisperWordCount = wordCount(whisperTranscript)
        guard recallWordCount >= 8,
              (
                lacksRecallPrefix(whisperTranscript, recallTranscript: recallTranscript) ||
                    losesRecallOpening(whisperTranscript, recallTranscript: recallTranscript)
              ),
              captureDurationSeconds >= 2.0 else {
            return nil
        }

        if finalTranscriptHasDanglingEnding(whisperTranscript) {
            return Decision(
                logMessage: "Whisper candidate rejected because it loses recall prefix and ends mid-phrase context=\(context) whisper_words=\(whisperWordCount) recall_words=\(recallWordCount) duration_seconds=\(formatSeconds(captureDurationSeconds))",
                fallbackReason: nil
            )
        }

        if hasContentStemRepetition(whisperTranscript) {
            return Decision(
                logMessage: "Whisper candidate rejected because it loses recall prefix and looks repetitive context=\(context) whisper_words=\(whisperWordCount) recall_words=\(recallWordCount) duration_seconds=\(formatSeconds(captureDurationSeconds))",
                fallbackReason: nil
            )
        }

        return Decision(
            logMessage: "Whisper candidate rejected because it loses recall prefix context=\(context) whisper_words=\(whisperWordCount) recall_words=\(recallWordCount) duration_seconds=\(formatSeconds(captureDurationSeconds))",
            fallbackReason: nil
        )
    }

    public func parakeetStreamingRecallFallback(
        parakeetTranscript: String,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Decision? {
        guard let streamingTranscript else { return nil }

        let parakeetWordCount = wordCount(parakeetTranscript)
        let streamingWordCount = wordCount(streamingTranscript)
        guard captureDurationSeconds >= chunkedWhisperFallbackMinimumCaptureSeconds,
              streamingWordCount >= 14,
              streamingWordCount > parakeetWordCount else {
            return nil
        }

        let wordDelta = streamingWordCount - parakeetWordCount
        let ratio = Double(parakeetWordCount) / Double(max(1, streamingWordCount))
        if wordDelta >= 6, ratio < 0.86 {
            let ratioText = formatRatio(ratio)
            return Decision(
                logMessage: "Parakeet v3 ANE transcript accepted but shorter than streaming recall context=\(context) parakeet_words=\(parakeetWordCount) streaming_words=\(streamingWordCount) ratio=\(ratioText) duration_seconds=\(formatSeconds(captureDurationSeconds))",
                fallbackReason: "shorter_than_streaming_recall parakeet_words=\(parakeetWordCount) streaming_words=\(streamingWordCount) ratio=\(ratioText)"
            )
        }

        if wordDelta >= 3, finalTranscriptHasDanglingEnding(parakeetTranscript) {
            return Decision(
                logMessage: "Parakeet v3 ANE transcript accepted but ends like a truncated prefix context=\(context) parakeet_words=\(parakeetWordCount) streaming_words=\(streamingWordCount) duration_seconds=\(formatSeconds(captureDurationSeconds))",
                fallbackReason: "dangling_ending_with_streaming_recall parakeet_words=\(parakeetWordCount) streaming_words=\(streamingWordCount)"
            )
        }

        return nil
    }

    public func finalTranscriptHasDanglingEnding(_ text: String) -> Bool {
        let tokenList = tokens(text)
        guard let lastToken = tokenList.last else { return false }

        let danglingEndingTokens: Set<String> = [
            "a", "an", "and", "as", "at", "but", "by", "for", "from", "if", "in", "of", "on", "or", "that", "the", "to", "when", "with",
            "aber", "auf", "dass", "das", "dem", "den", "der", "des", "die", "ein", "eine", "einem", "einen", "einer", "im", "in", "mit", "oder", "und", "von", "wenn", "weil", "zu",
        ]
        return danglingEndingTokens.contains(lastToken)
    }

    public func hasContentStemRepetition(_ text: String) -> Bool {
        let tokenList = tokens(text)
        guard tokenList.count >= 24 else { return false }

        let stopwords: Set<String> = [
            "aber", "and", "are", "auf", "but", "das", "den", "der", "die", "for", "in", "ist", "mit", "oder", "the", "und", "was", "wenn", "with", "you",
        ]
        let stems = tokenList.compactMap { token -> String? in
            guard token.count >= 4, !stopwords.contains(token) else { return nil }
            return String(token.prefix(4))
        }
        guard stems.count >= 16 else { return false }

        let stemCounts = Dictionary(grouping: stems, by: { $0 }).mapValues(\.count)
        let repeatedStemCounts = stemCounts.values.filter { $0 >= 3 }
        let repeatedTokenCount = repeatedStemCounts.reduce(0, +)
        return repeatedStemCounts.count >= 2 && Double(repeatedTokenCount) / Double(stems.count) >= 0.22
    }

    public func lacksRecallPrefix(_ candidateTranscript: String, recallTranscript: String) -> Bool {
        let candidateTokens = Set(tokens(candidateTranscript))
        let prefixTokens = tokens(recallTranscript)
            .prefix(10)
            .filter { $0.count >= 3 }
        guard prefixTokens.count >= 5 else { return false }

        let overlapCount = prefixTokens.filter { candidateTokens.contains($0) }.count
        return overlapCount <= 1
    }

    public func losesRecallOpening(_ candidateTranscript: String, recallTranscript: String) -> Bool {
        let candidateTokens = Set(tokens(candidateTranscript))
        let openingTokens = tokens(recallTranscript)
            .prefix(5)
            .filter { $0.count >= 3 }
            .prefix(3)
        guard openingTokens.count >= 3 else { return false }

        let overlapCount = openingTokens.filter { candidateTokens.contains($0) }.count
        return overlapCount <= 1
    }

    public func mergeTranscriptSegments(_ segments: [String]) -> String {
        segments.reduce(into: "") { partialResult, segment in
            let cleanedSegment = textPolicy.cleanedText(segment)
            guard !cleanedSegment.isEmpty else { return }
            guard !partialResult.isEmpty else {
                partialResult = cleanedSegment
                return
            }

            let normalizedExisting = textPolicy.normalizedPhrase(partialResult)
            let normalizedSegment = textPolicy.normalizedPhrase(cleanedSegment)
            guard !normalizedExisting.contains(normalizedSegment) else { return }

            if partialResult.last?.isWhitespace == false {
                partialResult += " "
            }
            partialResult += cleanedSegment
        }
    }

    private func shouldDeferShortWhisperCandidateForParakeetRecall(
        whisperTranscript: String,
        parakeetTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Decision? {
        guard let parakeetTranscript else { return nil }

        let whisperWordCount = wordCount(whisperTranscript)
        let parakeetWordCount = wordCount(parakeetTranscript)
        guard captureDurationSeconds >= 12.0,
              parakeetWordCount >= 24,
              parakeetWordCount - whisperWordCount >= 10 else {
            return nil
        }

        let ratio = Double(whisperWordCount) / Double(max(1, parakeetWordCount))
        guard ratio < 0.78 else { return nil }

        return Decision(
            logMessage: "Whisper candidate deferred because it is much shorter than accepted Parakeet recall candidate context=\(context) whisper_words=\(whisperWordCount) parakeet_words=\(parakeetWordCount) ratio=\(formatRatio(ratio)) duration_seconds=\(formatSeconds(captureDurationSeconds))",
            fallbackReason: nil
        )
    }

    private func shouldDeferShortWhisperCandidateForStreamingRecall(
        whisperTranscript: String,
        streamingTranscript: String?,
        captureDurationSeconds: TimeInterval,
        context: String
    ) -> Decision? {
        guard let streamingTranscript else { return nil }

        let whisperWordCount = wordCount(whisperTranscript)
        let streamingWordCount = wordCount(streamingTranscript)
        guard captureDurationSeconds >= chunkedWhisperFallbackMinimumCaptureSeconds,
              streamingWordCount >= 14,
              streamingWordCount - whisperWordCount >= 6 else {
            return nil
        }

        let ratio = Double(whisperWordCount) / Double(max(1, streamingWordCount))
        guard ratio < 0.70 else { return nil }

        return Decision(
            logMessage: "Whisper candidate deferred because it is much shorter than streaming recall candidate context=\(context) whisper_words=\(whisperWordCount) streaming_words=\(streamingWordCount) ratio=\(formatRatio(ratio)) duration_seconds=\(formatSeconds(captureDurationSeconds))",
            fallbackReason: nil
        )
    }

    private func formatRatio(_ ratio: Double) -> String {
        String(format: "%.2f", ratio)
    }

    private func formatSeconds(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", seconds)
    }
}
