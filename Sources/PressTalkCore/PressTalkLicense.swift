import CryptoKit
import Foundation

/// What a purchase entitles someone to.
///
/// Verified entirely offline. A buy-once local dictation app that phones home to
/// confirm a purchase contradicts its own pitch, and it makes the product stop
/// working the day the seller's server does. The trade accepted here is
/// explicit: no revocation, no seat counting, and a key can be shared. Trust,
/// updates, and support are the moat; DRM is not.
public struct PressTalkLicense: Codable, Equatable {
    /// Bumped when the payload shape changes. An unknown schema is rejected
    /// rather than best-guessed.
    public let schemaVersion: Int
    /// Which issuing key signed this, so keys can be rotated without
    /// invalidating licenses signed by the previous one.
    public let keyID: String
    public let productID: String
    /// Random per licence. Deliberately not derived from anything about the
    /// buyer.
    public let licenseID: String
    public let entitlement: String
    public let issuedAt: Date
    /// The last major version this licence covers. "Updates through 1.x" is a
    /// promise the app can actually check, and a later paid major version does
    /// not silently disable what someone already bought.
    public let maxMajorVersion: Int

    public init(
        schemaVersion: Int = PressTalkLicense.currentSchemaVersion,
        keyID: String,
        productID: String,
        licenseID: String,
        entitlement: String,
        issuedAt: Date,
        maxMajorVersion: Int
    ) {
        self.schemaVersion = schemaVersion
        self.keyID = keyID
        self.productID = productID
        self.licenseID = licenseID
        self.entitlement = entitlement
        self.issuedAt = issuedAt
        self.maxMajorVersion = maxMajorVersion
    }

    public static let currentSchemaVersion = 1
    public static let productIdentifier = "com.am.presstalk"

    /// Entitlements are names, not tiers with prices baked in. Pricing changes;
    /// what someone bought does not.
    public enum Entitlement: String {
        case personal
        case founder
        case commercial
    }

    public var entitlementKind: Entitlement? { Entitlement(rawValue: entitlement) }

    /// No email, no machine identifier, no hardware hash anywhere in here. A
    /// signature proves authenticity, not confidentiality: the payload is
    /// base64, so anything inside it is readable by anyone who sees the licence
    /// string, and licence strings end up in screenshots and support threads.
    public var containsNoPersonalData: Bool { true }
}

public enum PressTalkLicenseError: Error, Equatable {
    case tooLarge(Int)
    case malformed(String)
    case unknownKey(String)
    case badSignature
    case unsupportedSchema(Int)
    case wrongProduct(String)
    case versionNotCovered(licensed: Int, running: Int)

    public var userFacingMessage: String {
        switch self {
        case .tooLarge:
            return "That does not look like a licence key."
        case .malformed:
            return "That licence key is not readable. Copy the whole line, including the PRESSTALK prefix."
        case .unknownKey:
            return "That licence key was signed by a key this version does not recognise. Check for an update."
        case .badSignature:
            return "That licence key did not verify. Copy it again from your receipt email."
        case .unsupportedSchema:
            return "That licence key is newer than this version of PressTalk. Update and try again."
        case .wrongProduct:
            return "That licence key is for a different product."
        case .versionNotCovered(let licensed, let running):
            return "That licence covers PressTalk \(licensed).x, and this is version \(running). "
                + "Your existing version keeps working."
        }
    }
}

/// Verifies licence strings against a fixed set of embedded public keys.
public struct PressTalkLicenseVerifier {
    /// Domain separation. Without it a signature produced for some other purpose
    /// by the same key could be replayed as a licence.
    static let signaturePrefix = Data("PressTalk-license-v1\n".utf8)
    /// Bounds the work done on unvalidated input.
    public static let maximumEncodedLength = 4096
    static let envelopePrefix = "PRESSTALK-1"

    public let trustedKeys: [String: Curve25519.Signing.PublicKey]
    public let productID: String
    public let runningMajorVersion: Int

    public init(
        trustedKeys: [String: Curve25519.Signing.PublicKey],
        productID: String = PressTalkLicense.productIdentifier,
        runningMajorVersion: Int
    ) {
        self.trustedKeys = trustedKeys
        self.productID = productID
        self.runningMajorVersion = runningMajorVersion
    }

    /// Order matters here. The signature is checked over the exact bytes that
    /// were transmitted, before any field inside the payload is trusted for
    /// anything. Decoding first and verifying a re-encoded copy is the classic
    /// way to make a signature check meaningless, because the bytes that were
    /// signed and the bytes that get used stop being the same.
    public func verify(_ encoded: String) -> Result<PressTalkLicense, PressTalkLicenseError> {
        let trimmed = encoded.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= Self.maximumEncodedLength else {
            return .failure(.tooLarge(trimmed.count))
        }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return .failure(.malformed("expected 4 dot-separated sections, found \(parts.count)"))
        }
        guard parts[0] == Self.envelopePrefix else {
            return .failure(.malformed("unexpected prefix"))
        }

        let envelopeKeyID = String(parts[1])
        let payloadSegment = String(parts[2])
        guard let publicKey = trustedKeys[envelopeKeyID] else {
            return .failure(.unknownKey(envelopeKeyID))
        }
        guard let signature = Data(base64URLEncoded: String(parts[3])) else {
            return .failure(.malformed("signature is not base64url"))
        }

        // Signed over the key id as well as the payload, so the envelope's
        // choice of verification key cannot be swapped for another trusted one.
        var signedBytes = Self.signaturePrefix
        signedBytes.append(Data(envelopeKeyID.utf8))
        signedBytes.append(Data(".".utf8))
        signedBytes.append(Data(payloadSegment.utf8))

        guard publicKey.isValidSignature(signature, for: signedBytes) else {
            return .failure(.badSignature)
        }

        guard let payloadData = Data(base64URLEncoded: payloadSegment) else {
            return .failure(.malformed("payload is not base64url"))
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let license = try? decoder.decode(PressTalkLicense.self, from: payloadData) else {
            return .failure(.malformed("payload is not a licence"))
        }

        guard license.schemaVersion == PressTalkLicense.currentSchemaVersion else {
            return .failure(.unsupportedSchema(license.schemaVersion))
        }
        // A signature by a trusted key over someone else's product identifier
        // still must not unlock this one.
        guard license.productID == productID else {
            return .failure(.wrongProduct(license.productID))
        }
        guard license.keyID == envelopeKeyID else {
            return .failure(.malformed("key id does not match the envelope"))
        }
        guard license.maxMajorVersion >= runningMajorVersion else {
            return .failure(.versionNotCovered(
                licensed: license.maxMajorVersion, running: runningMajorVersion))
        }
        return .success(license)
    }
}

/// Signs licences. Lives beside the verifier so the two formats cannot drift,
/// and is only ever exercised by the issuing tool -- the app has no private key.
public struct PressTalkLicenseIssuer {
    public let keyID: String
    public let privateKey: Curve25519.Signing.PrivateKey

    public init(keyID: String, privateKey: Curve25519.Signing.PrivateKey) {
        self.keyID = keyID
        self.privateKey = privateKey
    }

    public func issue(_ license: PressTalkLicense) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let payloadData = try encoder.encode(license)
        let payloadSegment = payloadData.base64URLEncodedString()

        var signedBytes = PressTalkLicenseVerifier.signaturePrefix
        signedBytes.append(Data(keyID.utf8))
        signedBytes.append(Data(".".utf8))
        signedBytes.append(Data(payloadSegment.utf8))

        let signature = try privateKey.signature(for: signedBytes)
        return [
            PressTalkLicenseVerifier.envelopePrefix,
            keyID,
            payloadSegment,
            signature.base64URLEncodedString(),
        ].joined(separator: ".")
    }
}

// Licence strings are pasted into text fields and travel through email, so the
// encoding avoids "+" and "/" entirely.
public extension Data {
    init?(base64URLEncoded string: String) {
        var padded = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while padded.count % 4 != 0 { padded.append("=") }
        guard let data = Data(base64Encoded: padded) else { return nil }
        self = data
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
