import CryptoKit
import Foundation
import XCTest
@testable import PressTalkCore

final class AccessLicenseTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let key = Curve25519.Signing.PrivateKey()
    private func encoded(schema: Int = 2, days: Double? = 7, entitlement: String = "trial_extension") throws -> String {
        try PressTalkLicenseIssuer(keyID: "test", privateKey: key).issue(PressTalkLicense(
            schemaVersion: schema, keyID: "test", productID: PressTalkLicense.productIdentifier,
            licenseID: UUID().uuidString, entitlement: entitlement, issuedAt: start,
            maxMajorVersion: 0, expiresAt: days.map { start.addingTimeInterval($0 * 86400) }))
    }
    private var verifier: PressTalkLicenseVerifier {
        PressTalkLicenseVerifier(trustedKeys: ["test": key.publicKey], runningMajorVersion: 1)
    }
    func testJavaScriptExtensionIsAcceptedAndExpiresAtTheExactBoundary() throws {
        struct Fixture: Decodable { let publicKey: String; let license: String }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/access-license.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: XCTUnwrap(Data(base64Encoded: fixture.publicKey)))
        let verifier = PressTalkLicenseVerifier(trustedKeys: ["test-only": publicKey], runningMajorVersion: 99)
        let expiry = start.addingTimeInterval(7 * 86400)
        let license = try verifier.verify(fixture.license, now: expiry.addingTimeInterval(-0.001)).get()
        XCTAssertEqual(license.expiresAt, expiry)
        XCTAssertEqual(license.entitlementKind, .trialExtension)
        XCTAssertFalse(license.accessSummary.contains("Permanent"))
        XCTAssertEqual(verifier.verify(fixture.license, now: expiry), .failure(.expired))
        XCTAssertEqual(verifier.verify(fixture.license, now: expiry.addingTimeInterval(1)), .failure(.expired))
    }
    func testAnExtensionCannotMasqueradeAsAPermanentLicenceOrOmitExpiry() throws {
        for candidate in [try encoded(schema: 1), try encoded(days: nil), try encoded(days: -1),
                          try encoded(entitlement: "founder"), try encoded(schema: 1, days: nil)] {
            guard case .failure = verifier.verify(candidate, now: start) else { return XCTFail("Invalid extension was accepted") }
        }
    }
    func testExpiryIsRecheckedWithoutRestartAndLongerOrPermanentAccessIsProtected() throws {
        let suite = "PressTalk.AccessTest.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var now = start
        let store = OfflineLicenseStore(defaults: defaults, verifier: verifier, now: { now })
        let short = try encoded(), long = try encoded(days: 30), permanent = try encoded(schema: 1, days: nil, entitlement: "founder")
        _ = try store.importLicense(short).get()
        now = start.addingTimeInterval(7 * 86400)
        XCTAssertNil(store.license, "App kept granting access after expiry")
        let state = EntitlementPolicy().state(verifiedEntitlement: store.license?.entitlement,
            priorUse: .init(predatesPaidLicensing: false), trialStartedAt: start, now: now)
        XCTAssertFalse(state.allowsDictation)
        XCTAssertEqual(store.importLicense(short), .failure(.expired))
        _ = try store.importLicense(long).get()
        now = start
        XCTAssertEqual(store.importLicense(short), .failure(.existingLicenseIsBetter))
        XCTAssertEqual(defaults.string(forKey: "PressTalk.License"), long)
        _ = try store.importLicense(permanent).get()
        XCTAssertEqual(store.importLicense(long), .failure(.existingLicenseIsBetter))
        XCTAssertEqual(defaults.string(forKey: "PressTalk.License"), permanent)
        now = start.addingTimeInterval(10000 * 86400)
        XCTAssertNotNil(store.license)
    }
}
