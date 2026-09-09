import CryptoKit
import Foundation
import XCTest
@testable import PressTalkCore

final class OfflineLicenseStoreTests: XCTestCase {
    private func fixture() throws -> (String, Curve25519.Signing.PublicKey) {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/commerce-license.json")
        let value = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        return (value.license, try Curve25519.Signing.PublicKey(
            rawRepresentation: XCTUnwrap(Data(base64Encoded: value.publicKey))))
    }
    private struct Fixture: Decodable { let license: String; let publicKey: String }

    func testJavaScriptIssuedLicenseSurvivesStoreRecreationAndExpiredTrialAndFutureMajorUpdate() throws {
        let (encoded, key) = try fixture()
        let suite = "PressTalk.LicenseTest.\(UUID().uuidString)"
        let firstDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { firstDefaults.removePersistentDomain(forName: suite) }
        let verifier = PressTalkLicenseVerifier(trustedKeys: ["test-only": key], runningMajorVersion: 1)
        let first = OfflineLicenseStore(defaults: firstDefaults, verifier: verifier)
        XCTAssertNil(first.license)
        guard case .success = first.importLicense(encoded) else { return XCTFail("service licence rejected") }
        firstDefaults.synchronize()

        let reloadedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let future = OfflineLicenseStore(defaults: reloadedDefaults,
            verifier: PressTalkLicenseVerifier(trustedKeys: ["test-only": key], runningMajorVersion: 99))
        XCTAssertEqual(future.license?.entitlement, "founder")
        let now = Date()
        let state = EntitlementPolicy().state(verifiedEntitlement: future.license?.entitlement,
            priorUse: .init(predatesPaidLicensing: false),
            trialStartedAt: now.addingTimeInterval(-10 * 365 * 86400), now: now)
        XCTAssertEqual(state, .licensed(entitlement: "founder"))
        XCTAssertTrue(state.allowsDictation)

        guard case .failure = future.importLicense(encoded + "broken") else { return XCTFail("bad key accepted") }
        XCTAssertEqual(future.license, first.license, "invalid activation replaced a working licence")
    }

    func testActivationURLAndFileTransportSameSignedLicense() throws {
        let (encoded, key) = try fixture()
        let url = try XCTUnwrap(URL(string: "presstalk://activate?license=\(encoded)"))
        XCTAssertEqual(try LicenseActivation.encodedLicense(from: url), encoded)
        XCTAssertEqual(try LicenseActivation.encodedLicense(from:
            XCTUnwrap(URL(string: "PressTalk://ACTIVATE?license=\(encoded)"))), encoded)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).presstalk-license")
        defer { try? FileManager.default.removeItem(at: file) }
        try (encoded + "\n").write(to: file, atomically: true, encoding: .utf8)
        let fromFile = try LicenseActivation.encodedLicense(from: file)
        let verifier = PressTalkLicenseVerifier(trustedKeys: ["test-only": key], runningMajorVersion: 1)
        guard case .success = verifier.verify(fromFile) else { return XCTFail("downloaded file rejected") }
        try String(repeating: "x", count: 4097).write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try LicenseActivation.encodedLicense(from: file))
    }

    func testUnexpectedActivationURLsAreRejected() throws {
        for raw in ["https://activate?license=abc", "presstalk://other?license=abc",
                    "presstalk://activate?license=a&license=b", "presstalk://activate/path?license=a",
                    "presstalk://activate?license=a#extra", "presstalk://user@activate?license=a",
                    "presstalk://activate:12?license=a", "presstalk://activate?license=",
                    "presstalk://activate?license=a&redirect=https://example.com"] {
            XCTAssertThrowsError(try LicenseActivation.encodedLicense(from: XCTUnwrap(URL(string: raw))), raw)
        }
    }
}
