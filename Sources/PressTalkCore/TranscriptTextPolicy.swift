import Foundation

public struct TranscriptTextPolicy {
    public let shortHoldNoSpeechSuppressionSeconds: TimeInterval

    public init(shortHoldNoSpeechSuppressionSeconds: TimeInterval = 1.5) {
        self.shortHoldNoSpeechSuppressionSeconds = shortHoldNoSpeechSuppressionSeconds
    }

    public func cleanedText(_ text: String) -> String {
        let trimmedOriginal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let suppressedNonSpeechTerms = [
            "music", "musik", "gibberish", "humming", "hum", "hums", "noise", "noises",
            "background noise", "background noises", "ambient noise", "static", "buzz", "buzzing",
            "rustling", "rustle", "crackling", "distortion", "inaudible", "unclear", "silence",
            "giggle", "giggles", "laugh", "laughs", "laughing", "laughter", "kiss", "kisses",
            "cough", "coughs", "coughing", "clear throat", "clears throat", "clearing throat",
            "sigh", "sighs", "sighing", "breathes", "breathing", "mumbling", "mumbles",
            "whistle", "whistles", "whistling", "applause", "clapping", "typing", "tapping",
            "clicking", "clicks", "beep", "beeps", "beeping", "sniff", "sniffs", "sniffing",
            "sneeze", "sneezes", "sneezing"
        ]
        let suppressedNonSpeechPhrases = Set(suppressedNonSpeechTerms)
        let suppressedNonSpeechTokens = Set(
            suppressedNonSpeechTerms
                .flatMap { $0.components(separatedBy: CharacterSet.alphanumerics.inverted) }
                .filter { !$0.isEmpty }
        )

        let fullWrappedStageDirectionPatterns = [
            #"^\s*(?:\*+|_+)\s*.+?\s*(?:\*+|_+)\s*$"#,
            #"^\s*[\[(]\s*.+?\s*[\])]\s*$"#
        ]
        if fullWrappedStageDirectionPatterns.contains(where: {
            trimmedOriginal.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }) {
            return ""
        }

        var cleaned = text

        let stageDirectionPatterns = [
            #"[(*\[]\s*(?:musik|music|gibberish|humming|hums?|summt|summen|räusper(?:t|n)?|räuspert sich|hust(?:e|en|et)?|lacht|lachen|laugh(?:s|ing)?|giggles?|cough(?:s|ing)?|clears? throat|räuspern|seufzt|sigh(?:s|ing)?|atmet|breath(?:es|ing)?|mumbling|mumbles?|whistl(?:e|es|ing)|applause|clapping|noise|background noise|ambient noise|static|buzz(?:ing)?|rustl(?:e|ing)|crackl(?:e|ing)|distortion|inaudible|unclear|typing|tapping|click(?:ing|s)?|beep(?:ing|s)?|sniff(?:ing|s)?|sneez(?:e|es|ing)?)\s*[*)\]]"#,
            #"(?:\*+|_+)\s*(?:musik|music|gibberish|humming|hums?|summt|summen|räusper(?:t|n)?|räuspert sich|hust(?:e|en|et)?|lacht|lachen|laugh(?:s|ing)?|giggles?|cough(?:s|ing)?|clears? throat|räuspern|seufzt|sigh(?:s|ing)?|atmet|breath(?:es|ing)?|mumbling|mumbles?|whistl(?:e|es|ing)|applause|clapping|noise|background noise|ambient noise|static|buzz(?:ing)?|rustl(?:e|ing)|crackl(?:e|ing)|distortion|inaudible|unclear|typing|tapping|click(?:ing|s)?|beep(?:ing|s)?|sniff(?:ing|s)?|sneez(?:e|es|ing)?)\s*(?:\*+|_+)"#
        ]

        for pattern in stageDirectionPatterns {
            cleaned = cleaned.replacingOccurrences(
                of: pattern,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        cleaned = cleaned
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([(\[])\s+"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+([)\]])"#, with: "$1", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        cleaned = cleaned.replacingOccurrences(
            of: #"^[,.;:!?…\-\s]+"#,
            with: "",
            options: .regularExpression
        )

        let normalizedStandalonePhrase = normalizedTokensPhrase(cleaned)
        if suppressedNonSpeechPhrases.contains(normalizedStandalonePhrase) {
            return ""
        }

        let normalizedTokens = normalizedStandalonePhrase
            .split(separator: " ")
            .map(String.init)
        if !normalizedTokens.isEmpty,
           normalizedTokens.count <= 5,
           normalizedTokens.allSatisfy({ suppressedNonSpeechTokens.contains($0) }) {
            return ""
        }

        return cleaned
    }

    public func normalizedPhrase(_ text: String) -> String {
        normalizedTokensPhrase(cleanedText(text))
    }

    private func normalizedTokensPhrase(_ text: String) -> String {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    public func tokens(_ text: String) -> [String] {
        cleanedText(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { !$0.isEmpty }
    }

    public func isPlausibleTranscript(_ text: String) -> Bool {
        let cleaned = cleanedText(text)
        guard !cleaned.isEmpty, cleaned != "Waiting for speech..." else { return false }

        let scalars = cleaned.unicodeScalars
        let letterOrDigitCount = scalars.filter(CharacterSet.alphanumerics.contains).count
        guard letterOrDigitCount >= 2 else { return false }

        let punctuationCount = scalars.filter(CharacterSet.punctuationCharacters.contains).count
        if punctuationCount > letterOrDigitCount {
            return false
        }

        let lowercasedTokens = tokens(cleaned)
        guard !lowercasedTokens.isEmpty else { return false }
        if lowercasedTokens.count <= 3 {
            return true
        }

        let uniqueTokenCount = Set(lowercasedTokens).count
        let uniqueTokenRatio = Double(uniqueTokenCount) / Double(lowercasedTokens.count)
        let mostCommonTokenCount = Dictionary(grouping: lowercasedTokens, by: { $0 })
            .values
            .map(\.count)
            .max() ?? 0

        if lowercasedTokens.count >= 5 && uniqueTokenRatio < 0.45 {
            return false
        }
        if lowercasedTokens.count >= 5 && Double(mostCommonTokenCount) / Double(lowercasedTokens.count) > 0.55 {
            return false
        }
        if cleaned.contains(",,,") || cleaned.contains("...") {
            return false
        }

        return true
    }

    public func isLikelySilenceHallucination(
        _ text: String,
        signalRMS: Double,
        signalPeak: Double,
        captureDurationSeconds: TimeInterval
    ) -> Bool {
        let normalized = normalizedPhrase(text)
        guard !normalized.isEmpty else { return false }

        let weakAudio = signalRMS < 0.0035 && signalPeak < 0.045
        let shortCapture = captureDurationSeconds < shortHoldNoSpeechSuppressionSeconds
        guard weakAudio || shortCapture else { return false }

        // Silence cannot produce speech, so on genuinely dead audio nothing is
        // acceptable and no phrase list is needed.
        //
        // This used to be an exact-match denylist -- "you", "thank you",
        // "thanks" -- and on 2026-09-06 it lost to its own recovery path.
        // Whisper returned "you" on a silent recording, the list caught it, and
        // being caught is exactly what triggers the relaxed-decoding retry. The
        // retry returned "you you", which is not in the list, so it was
        // accepted and pasted. A denylist sitting behind a mutation generator
        // leaks by construction; enumerating "you you" would only have moved
        // the leak to "you you you".
        if signalRMS <= CaptureIntegrity.silenceRMSFloor
            && signalPeak <= CaptureIntegrity.silenceRMSFloor {
            return true
        }

        let words = normalized.split(separator: " ").map(String.init)

        // A single distinct word repeated is the shape of a decoder looping on
        // noise, whatever the word happens to be.
        if words.count >= 2, Set(words).count == 1 { return true }

        let silenceHallucinationStems: Set<String> = [
            "you", "thank you", "thanks", "thank you very much",
            "thank you so much", "bye", "okay", "so",
            "untertitel der amara org community", "untertitelung des zdf",
            "vielen dank", "danke",
        ]
        if silenceHallucinationStems.contains(normalized) { return true }

        // Repeats of a known stem: "you you", "thanks thanks", and the rest of
        // an unbounded family the list can never finish naming.
        for stem in silenceHallucinationStems {
            let stemWords = stem.split(separator: " ").map(String.init)
            guard !stemWords.isEmpty, words.count % stemWords.count == 0,
                  words.count > stemWords.count else { continue }
            var matches = true
            for (index, word) in words.enumerated()
            where word != stemWords[index % stemWords.count] {
                matches = false
                break
            }
            if matches { return true }
        }

        return false
    }

    public func bestTranscriptCandidate(from texts: [String]) -> String {
        texts
            .map(cleanedText)
            .filter(isPlausibleTranscript)
            .max(by: { $0.count < $1.count }) ?? ""
    }
}
