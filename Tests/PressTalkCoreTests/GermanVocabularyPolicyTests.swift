import XCTest
@testable import PressTalkCore

/// Mirrors the Python reference suite in ~/Code/presstalk-vocab/test_corrector.py.
/// Every MUST-NOT-TOUCH case is a bug that actually happened during development.
final class GermanVocabularyPolicyTests: XCTestCase {
    /// The real guard list is a shipped resource; these are the words from it
    /// that matter for these cases, so the tests do not depend on file loading.
    let userWords: Set<String> = [
        "verträge", "ändern", "größere", "änderungen", "nötig", "wir", "müssen", "die",
        "zwischen", "reiz", "und", "reaktion", "liegt", "ein", "raum", "sind", "fällig",
        "ist", "für", "nicht", "private", "personen", "möglich", "auf", "der", "den",
        "betrag", "bitte", "prüfe", "zahlungsarten", "konferenz", "findet", "statt", "in",
    ]

    var policy: GermanVocabularyPolicy {
        GermanVocabularyPolicy(userVocabulary: userWords)
    }

    // MUST FIX
    func testSplitsGluedPhrase() {
        XCTAssertTrue(policy.correctedText("Kaufaufrechnung ist möglich.").contains("Kauf auf Rechnung"))
    }

    func testRepairsCorruptedBrands() {
        XCTAssertTrue(policy.correctedText("Zahlungsarten sind Wisa und Vorkasse.").contains("Visa"))
        XCTAssertTrue(policy.correctedText("Betrag der Seepalastschrift überweisen.").contains("SEPA-Lastschrift"))
    }

    func testRepairsPlaceName() {
        XCTAssertTrue(policy.correctedText("Die Konferenz findet in Münchengladbach statt.").contains("Mönchengladbach"))
    }

    func testJoinsSplitCompound() {
        let out = policy.correctedText("Die Umsatzsteuer vor Anmeldung ist fällig.")
        XCTAssertTrue(out.contains("Umsatzsteuervoranmeldung"), out)
    }

    func testRestoresGermanNounCapitalisation() {
        let out = policy.correctedText("Wir brauchen eine datenschutzgrundverordnung konforme Erklärung.")
        XCTAssertTrue(out.contains("Datenschutzgrundverordnung"), out)
    }

    // MUST NOT TOUCH — a false positive corrupts text that was already right,
    // which the user cannot detect without re-reading their own dictation.
    func testLeavesCorrectGermanPluralAlone() {
        // The inflection bug: a correct plural rewritten to the wrong singular.
        let input = "Die Krankenversicherungsbeiträge sind fällig."
        XCTAssertEqual(policy.correctedText(input), input)
    }

    func testLeavesCleanTextAlone() {
        let a = "Wir müssen die Verträge ändern, größere Änderungen sind nötig."
        XCTAssertEqual(policy.correctedText(a), a)
        let b = "Zwischen Reiz und Reaktion liegt ein Raum."
        XCTAssertEqual(policy.correctedText(b), b)
    }

    func testLeavesAlreadyCorrectBrandsAlone() {
        let s = "Die Zahlungsarten sind Klarna, PayPal, Visa und Vorkasse."
        XCTAssertEqual(policy.correctedText(s), s)
    }

    func testReportsWhatItChanged() {
        let (_, changes) = policy.corrected("Zahlungsarten sind Wisa und Vorkasse.")
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes.first?.kind, "match")
        XCTAssertEqual(changes.first?.to, "Visa")
    }

    // Phonetics: the reason Kölner was chosen over Soundex.
    func testKoelnerCollidesGermanCorruptions() {
        XCTAssertEqual(KoelnerPhonetik.code("Sofortüberweisung"), KoelnerPhonetik.code("SfortÜberweisung"))
        XCTAssertEqual(KoelnerPhonetik.code("Notion"), KoelnerPhonetik.code("Motion"))
        XCTAssertEqual(KoelnerPhonetik.code("Mönchengladbach"), KoelnerPhonetik.code("Münchengladbach"))
        XCTAssertEqual(KoelnerPhonetik.code("Visa"), KoelnerPhonetik.code("Wisa"))
    }

    func testShippedUserVocabularyLoads() {
        let words = GermanVocabularyPolicy.loadUserVocabulary(bundle: .module)
        XCTAssertGreaterThan(words.count, 20000, "guard list should ship with the package")
        XCTAssertTrue(words.contains("okayness"), "the user's own term must be present")
        XCTAssertFalse(words.contains("keines"), "'keines' is absent from 4.76M tokens of their speech")
    }
}
