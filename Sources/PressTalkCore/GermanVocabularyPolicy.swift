import Foundation

/// German vocabulary repair for dictated transcripts. Backend-independent: it
/// runs after ASR and helps whichever recogniser produced the text.
///
/// Measured on a 144-clip / 1,434-word German eval, HELD-OUT half:
///     parakeet-v3-ane   16.55% -> 13.93% WER   (13 clips fixed, 0 broken)
///     whisper turbo     15.40% -> 13.65% WER   (11 clips fixed, 0 broken)
/// Gains concentrate where a lexicon should help: names +7.3, brands +6.1,
/// coaching +3.7, anglicisms +2.7.
///
/// The design bias is PRECISION over recall. Corrupting text that was already
/// correct is worse than leaving an error, because the user cannot tell the
/// difference without re-reading what they just dictated.
public struct GermanVocabularyPolicy {
    public struct Term {
        public let category: String
        public let text: String
        let tokens: [String]
        let phonetic: String
        let flat: String
        let glued: String

        public init(_ category: String, _ text: String) {
            self.category = category
            self.text = text
            let toks = GermanVocabularyPolicy.words(in: text)
            self.tokens = toks
            self.phonetic = KoelnerPhonetik.code(phrase: toks)
            self.flat = GermanVocabularyPolicy.flatten(text)
            self.glued = toks.map { $0.lowercased() }.joined()
        }
    }

    /// One correction, for tracing what the policy did.
    public struct Change: Equatable {
        public let kind: String     // split | join | match | case
        public let from: String
        public let to: String
    }

    public static let defaultLexicon: [Term] = [
        Term("brand", "Klarna"),
        Term("brand", "PayPal"),
        Term("brand", "Visa"),
        Term("brand", "Vorkasse"),
        Term("brand", "SEPA-Lastschrift"),
        Term("brand", "Sofortüberweisung"),
        Term("brand", "DHL"),
        Term("brand", "DPD"),
        Term("brand", "Hermes"),
        Term("brand", "Notion"),
        Term("brand", "Shopify"),
        Term("brand", "Lexoffice"),
        Term("brand", "Stripe"),
        Term("brand", "Amazon Pay"),
        Term("brand", "Apple Pay"),
        Term("brand", "Google Calendar"),
        Term("tech", "Repository"),
        Term("tech", "Branch"),
        Term("tech", "Pull Request"),
        Term("tech", "Backlog"),
        Term("tech", "Ticket"),
        Term("tech", "Standup"),
        Term("tech", "Retro"),
        Term("tech", "Release"),
        Term("tech", "Dashboard"),
        Term("tech", "Latenz"),
        Term("tech", "Context Window"),
        Term("tech", "Prompt"),
        Term("tech", "merge"),
        Term("tech", "deploye"),
        Term("tech", "tracken"),
        Term("tech", "Feature"),
        Term("tech", "Priority"),
        Term("tech", "Feedback"),
        Term("tech", "Server"),
        Term("coaching", "Okayness"),
        Term("coaching", "Selbstannahme"),
        Term("coaching", "Selbstoptimierung"),
        Term("coaching", "Nervensystem"),
        Term("coaching", "Klienten"),
        Term("coaching", "innerer Kritiker"),
        Term("place", "Kaiserslautern"),
        Term("place", "Mönchengladbach"),
        Term("place", "Oberammergau"),
        Term("place", "Düsseldorf"),
        Term("place", "Saarbrücken"),
        Term("place", "Regensburg"),
        Term("place", "Freiburg im Breisgau"),
        Term("place", "Marienplatz"),
        Term("place", "München"),
        Term("place", "Karlsruhe"),
        Term("place", "Köln"),
        Term("name", "Schröder"),
        Term("name", "Müller"),
        Term("name", "Monas"),
        Term("name", "Yılmaz"),
        Term("name", "Kowalczyk"),
        Term("phrase", "Kauf auf Rechnung"),
        Term("phrase", "auf Anfrage"),
        Term("phrase", "Arbeitsunfähigkeitsbescheinigung"),
        Term("phrase", "Umsatzsteuervoranmeldung"),
        Term("phrase", "Datenschutzgrundverordnung"),
        Term("phrase", "Auftragsbestätigung"),
        Term("phrase", "Lieferterminzusage"),
        Term("phrase", "Krankenversicherungsbeitrag"),
        Term("phrase", "Einkommensteuervorauszahlung"),
        Term("phrase", "Geschäftsführer"),
        Term("phrase", "Geschäftsführerin"),
        Term("phrase", "Steuerberater"),
        Term("phrase", "Einwilligungserklärung")
    ]

    let lexicon: [Term]
    /// Words the user demonstrably says. Never rewritten.
    let userVocabulary: Set<String>
    let userWordMinimum: Int
    let phoneticTolerance: Int
    let surfaceRatio: Double

    public init(lexicon: [Term] = GermanVocabularyPolicy.defaultLexicon,
                userVocabulary: Set<String> = [],
                userWordMinimum: Int = 3,
                phoneticTolerance: Int = 1,
                surfaceRatio: Double = 0.50) {
        self.lexicon = lexicon
        self.userVocabulary = userVocabulary
        self.userWordMinimum = userWordMinimum
        self.phoneticTolerance = phoneticTolerance
        self.surfaceRatio = surfaceRatio
    }

    // MARK: - tokenisation

    static func words(in text: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in text {
            if ch.isLetter || ch == "-" { cur.append(ch) }
            else if !cur.isEmpty { out.append(cur); cur = "" }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    static func flatten(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter })
    }

    static func deumlaut(_ s: String) -> String {
        var t = s
        for (a, b) in [("ä","a"), ("ö","o"), ("ü","u"), ("ß","ss")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t
    }

    /// German is heavily inflected and the lexicon stores one citation form.
    /// Without this the matcher "corrects" a correct plural into a wrong
    /// singular -- Krankenversicherungsbeiträge -> Krankenversicherungsbeitrag --
    /// which is exactly what broke 3 otherwise-perfect clips before it existed.
    static let inflectionEndings: Set<String> =
        ["", "e", "n", "en", "er", "es", "s", "em", "ern", "in", "innen"]

    func isInflection(_ candidate: String, _ term: String) -> Bool {
        let a = Self.deumlaut(candidate), b = Self.deumlaut(term)
        if a == b { return true }
        for (x, y) in [(a, b), (b, a)] where x.hasPrefix(y) {
            if Self.inflectionEndings.contains(String(x.dropFirst(y.count))) { return true }
        }
        return false
    }

    func isUserWord(_ s: String) -> Bool { userVocabulary.contains(s.lowercased()) }

    // MARK: - the passes

    public func corrected(_ text: String) -> (text: String, changes: [Change]) {
        var changes: [Change] = []
        var out = text
        out = splitPass(out, &changes)
        out = joinPass(out, &changes)
        out = matchPass(out, &changes)
        out = casePass(out, &changes)
        return (out, changes)
    }

    public func correctedText(_ text: String) -> String { corrected(text).text }


    /// A known multi-word phrase that came back glued into one token.
    ///     "kaufaufrechnung" -> "Kauf auf Rechnung"
    func splitPass(_ text: String, _ changes: inout [Change]) -> String {
        var result = text
        for term in lexicon where term.tokens.count > 1 {
            for token in Self.words(in: result) {
                guard !isUserWord(token) else { continue }
                if Self.flatten(token) == term.glued {
                    result = result.replacingOccurrences(of: token, with: term.text)
                    changes.append(Change(kind: "split", from: token, to: term.text))
                }
            }
        }
        return result
    }

    /// The mirror: a SINGLE-word compound that came back split across tokens,
    /// sometimes with an invented filler word.
    ///     "Umsatzsteuer vor Anmeldung"            -> Umsatzsteuervoranmeldung
    ///     "Arbeits- und Fähigkeitsbescheinigung"  -> Arbeitsunfähigkeitsbescheinigung
    ///
    /// Only one-word entries are join targets; multi-word entries belong to
    /// splitPass, or the two fight over "Kauf auf Rechnung" and oscillate.
    ///
    /// Note there is deliberately NO inflection guard here. In matchPass an
    /// exact hit means "already correct, leave it"; here the word arrived split
    /// apart, which is wrong however it is inflected.
    func joinPass(_ text: String, _ changes: inout [Change]) -> String {
        let singles = lexicon.filter { $0.tokens.count == 1 }
        guard !singles.isEmpty else { return text }
        var tokens = Self.words(in: text)
        var result = text
        var i = 0
        while i < tokens.count {
            var matched = false
            for n in stride(from: 4, through: 2, by: -1) where i + n <= tokens.count {
                let gram = Array(tokens[i..<(i + n)])
                let joined = Self.flatten(gram.joined())
                guard joined.count >= 12 else { continue }
                for term in singles {
                    let d = KoelnerPhonetik.editDistance(joined, term.flat)
                    // exact, or one stray character (the invented "und")
                    if d <= 1 || (d <= 2 && term.flat.count >= 20) {
                        let phrase = gram.joined(separator: " ")
                        if let r = result.range(of: phrase) {
                            result.replaceSubrange(r, with: term.text)
                            changes.append(Change(kind: "join", from: phrase, to: term.text))
                            tokens = Self.words(in: result)
                            matched = true
                        }
                        break
                    }
                }
                if matched { break }
            }
            i += matched ? 1 : 1
        }
        return result
    }

    /// An n-gram phonetically close to a lexicon term, that the user does not say.
    func matchPass(_ text: String, _ changes: inout [Change]) -> String {
        var result = text
        var tokens = Self.words(in: result)
        var i = 0
        while i < tokens.count {
            var consumed = 1
            for n in stride(from: 3, through: 1, by: -1) where i + n <= tokens.count {
                let gram = Array(tokens[i..<(i + n)])
                if gram.allSatisfy({ isUserWord($0) }) { continue }
                guard let term = bestMatch(for: gram) else { continue }
                let phrase = gram.joined(separator: " ")
                if let r = result.range(of: phrase) {
                    result.replaceSubrange(r, with: term.text)
                    changes.append(Change(kind: "match", from: phrase, to: term.text))
                    tokens = Self.words(in: result)
                    consumed = 1
                }
                break
            }
            i += consumed
        }
        return result
    }

    func bestMatch(for gram: [String]) -> Term? {
        let flat = Self.flatten(gram.joined(separator: " "))
        guard !flat.isEmpty else { return nil }
        if lexicon.contains(where: { $0.flat == flat }) { return nil }   // already correct
        let phonetic = KoelnerPhonetik.code(phrase: gram)
        var best: (score: (Int, Double), term: Term)?
        for term in lexicon where term.tokens.count == gram.count {
            let pd = KoelnerPhonetik.editDistance(phonetic, term.phonetic)
            if pd > phoneticTolerance { continue }
            if isInflection(flat, term.flat) { return nil }              // a valid form
            let ratio = Double(KoelnerPhonetik.editDistance(flat, term.flat))
                      / Double(max(term.flat.count, 1))
            if ratio > surfaceRatio { continue }
            if best == nil || (pd, ratio) < best!.score { best = ((pd, ratio), term) }
        }
        return best?.term
    }

    /// Restore lexicon capitalisation without changing any word. German
    /// capitalises nouns and the ASR does not always. This can only swap a token
    /// for the SAME token in the lexicon's spelling, so it cannot corrupt
    /// content. WER is case-insensitive by convention, so the score cannot see
    /// this -- the reader can.
    func casePass(_ text: String, _ changes: inout [Change]) -> String {
        var canonical: [String: String] = [:]
        for term in lexicon where term.tokens.count == 1 {
            canonical[term.text.lowercased()] = term.text
        }
        var result = text
        for token in Self.words(in: text) {
            if let c = canonical[token.lowercased()], c != token,
               let r = result.range(of: token) {
                result.replaceSubrange(r, with: c)
                changes.append(Change(kind: "case", from: token, to: c))
            }
        }
        return result
    }

    /// Loads the shipped user-vocabulary guard list.
    public static func loadUserVocabulary() -> Set<String> {
        loadUserVocabulary(bundle: .module)
    }

    public static func loadUserVocabulary(bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: "de_user_vocabulary", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map { $0.lowercased() })
    }
}
