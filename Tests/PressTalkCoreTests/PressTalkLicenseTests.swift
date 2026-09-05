import CryptoKit
import XCTest
@testable import PressTalkCore

final class PressTalkLicenseTests: XCTestCase {
    private let issuingKey = Curve25519.Signing.PrivateKey()
    private let otherKey = Curve25519.Signing.PrivateKey()
    private let keyID = "test-2026"

    private var issuer: PressTalkLicenseIssuer {
        PressTalkLicenseIssuer(keyID: keyID, privateKey: issuingKey)
    }

    private func verifier(
        keys: [String: Curve25519.Signing.PublicKey]? = nil,
        runningMajorVersion: Int = 1
    ) -> PressTalkLicenseVerifier {
        PressTalkLicenseVerifier(
            trustedKeys: keys ?? [keyID: issuingKey.publicKey],
            runningMajorVersion: runningMajorVersion)
    }

    private func license(
        productID: String = PressTalkLicense.productIdentifier,
        entitlement: String = "founder",
        maxMajorVersion: Int = 1,
        schemaVersion: Int = PressTalkLicense.currentSchemaVersion,
        keyID: String? = nil
    ) -> PressTalkLicense {
        PressTalkLicense(
            schemaVersion: schemaVersion,
            keyID: keyID ?? self.keyID,
            productID: productID,
            licenseID: UUID().uuidString,
            entitlement: entitlement,
            issuedAt: Date(timeIntervalSince1970: 1_800_000_000),
            maxMajorVersion: maxMajorVersion)
    }

    func testAValidLicenceRoundTrips() throws {
        let original = license()
        let encoded = try issuer.issue(original)
        XCTAssertTrue(encoded.hasPrefix("PRESSTALK-1."))
        switch verifier().verify(encoded) {
        case .success(let decoded):
            XCTAssertEqual(decoded, original)
        case .failure(let error):
            XCTFail("valid licence rejected: \(error)")
        }
    }

    // Every byte of the payload is covered, so flipping any character breaks it.
    func testATamperedPayloadFails() throws {
        let encoded = try issuer.issue(license())
        var parts = encoded.split(separator: ".").map(String.init)
        var payload = Array(parts[2])
        payload[payload.count / 2] = payload[payload.count / 2] == "A" ? "B" : "A"
        parts[2] = String(payload)
        let result = verifier().verify(parts.joined(separator: "."))
        guard case .failure = result else { return XCTFail("tampered payload was accepted") }
    }

    func testASignatureFromAnotherKeyFails() throws {
        let rogue = PressTalkLicenseIssuer(keyID: keyID, privateKey: otherKey)
        let encoded = try rogue.issue(license())
        XCTAssertEqual(verifier().verify(encoded).failureError, .badSignature)
    }

    func testAnUnknownKeyIdIsRejectedBeforeAnythingElse() throws {
        let encoded = try PressTalkLicenseIssuer(keyID: "not-trusted", privateKey: issuingKey)
            .issue(license(keyID: "not-trusted"))
        XCTAssertEqual(verifier().verify(encoded).failureError, .unknownKey("not-trusted"))
    }

    // The envelope selects the verification key. If it were not signed, a
    // licence could be re-pointed at any other trusted key.
    func testTheEnvelopeKeyIdCannotBeSwapped() throws {
        let secondKey = Curve25519.Signing.PrivateKey()
        let encoded = try issuer.issue(license())
        var parts = encoded.split(separator: ".").map(String.init)
        parts[1] = "second-key"
        let result = PressTalkLicenseVerifier(
            trustedKeys: [keyID: issuingKey.publicKey, "second-key": secondKey.publicKey],
            runningMajorVersion: 1
        ).verify(parts.joined(separator: "."))
        XCTAssertEqual(result.failureError, .badSignature)
    }

    // A trusted key signing some other product must not unlock this one.
    func testALicenceForAnotherProductIsRejected() throws {
        let encoded = try issuer.issue(license(productID: "com.example.other"))
        XCTAssertEqual(verifier().verify(encoded).failureError, .wrongProduct("com.example.other"))
    }

    func testAnUnknownSchemaIsRejectedRatherThanGuessed() throws {
        let encoded = try issuer.issue(license(schemaVersion: 99))
        XCTAssertEqual(verifier().verify(encoded).failureError, .unsupportedSchema(99))
    }

    // "Updates through 1.x" has to be something the app can actually check.
    func testALicenceDoesNotCoverALaterMajorVersion() throws {
        let encoded = try issuer.issue(license(maxMajorVersion: 1))
        XCTAssertEqual(
            verifier(runningMajorVersion: 2).verify(encoded).failureError,
            .versionNotCovered(licensed: 1, running: 2))
    }

    func testALicenceCoversEarlierMajorVersions() throws {
        let encoded = try issuer.issue(license(maxMajorVersion: 2))
        guard case .success = verifier(runningMajorVersion: 1).verify(encoded) else {
            return XCTFail("a 2.x licence should still run 1.x")
        }
    }

    func testGarbageIsRejectedWithoutCrashing() {
        for junk in ["", ".", "PRESSTALK-1", "PRESSTALK-1.a.b", "hello world",
                     "PRESSTALK-1.k.!!!!.!!!!", "PRESSTALK-2.k.a.b"] {
            guard case .failure = verifier().verify(junk) else {
                return XCTFail("accepted junk: \(junk)")
            }
        }
    }

    // Bounds the work done on unvalidated input.
    func testOversizedInputIsRejectedOnLengthAlone() {
        let huge = "PRESSTALK-1." + String(repeating: "a", count: 5000)
        guard case .failure(.tooLarge) = verifier().verify(huge) else {
            return XCTFail("oversized input should be rejected on length")
        }
    }

    func testSurroundingWhitespaceIsForgiven() throws {
        let encoded = try issuer.issue(license())
        guard case .success = verifier().verify("\n  \(encoded)  \n") else {
            return XCTFail("a pasted licence with stray whitespace should still verify")
        }
    }

    // A licence string ends up in screenshots and support threads. A signature
    // proves authenticity, not confidentiality, so nothing identifying goes in.
    func testThePayloadCarriesNoPersonalData() throws {
        let encoded = try issuer.issue(license())
        let payload = String(encoded.split(separator: ".")[2])
        let decoded = String(data: Data(base64URLEncoded: payload)!, encoding: .utf8)!
        for forbidden in ["email", "@", "machine", "hardware", "uuid_hw", "serial"] {
            XCTAssertFalse(
                decoded.lowercased().contains(forbidden),
                "licence payload leaks \(forbidden): \(decoded)")
        }
    }

    func testEveryErrorExplainsItselfWithoutJargon() {
        let errors: [PressTalkLicenseError] = [
            .tooLarge(9000), .malformed("x"), .unknownKey("k"), .badSignature,
            .unsupportedSchema(9), .wrongProduct("p"), .versionNotCovered(licensed: 1, running: 2),
        ]
        for error in errors {
            XCTAssertGreaterThan(error.userFacingMessage.count, 20, "\(error) has no real message")
            XCTAssertFalse(error.userFacingMessage.contains("Error"), "\(error) leaks jargon")
        }
    }
}

private extension Result where Failure == PressTalkLicenseError {
    var failureError: PressTalkLicenseError? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
