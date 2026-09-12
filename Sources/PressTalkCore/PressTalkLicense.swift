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
    /// The last major version this licence covers, or
    /// `PressTalkLicense.allMajorVersions` for every future release.
    ///
    /// The offer sold is "every future Mac update, including major versions,
    /// free", so licences are issued unbounded. The field stays because a
    /// bounded entitlement is a thing a later commercial tier might need, and
    /// adding it back after the fact would mean a schema change and a second
    /// signing key rollout.
    public let maxMajorVersion: Int
    /// Only schema 2 grants expire. Schema 1 paid and gifted licences stay permanent.
    public let expiresAt: Date?

    public init(
        schemaVersion: Int = PressTalkLicense.currentSchemaVersion,
        keyID: String,
        productID: String,
        licenseID: String,
        entitlement: String,
        issuedAt: Date,
        maxMajorVersion: Int,
        expiresAt: Date? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.keyID = keyID
        self.productID = productID
        self.licenseID = licenseID
        self.entitlement = entitlement
        self.issuedAt = issuedAt
        self.maxMajorVersion = maxMajorVersion
        self.expiresAt = expiresAt
    }

    public static let currentSchemaVersion = 1
    public static let expiringSchemaVersion = 2
    public static let productIdentifier = "com.am.presstalk"
    /// Sentinel for "no upper bound". Zero rather than Int.max so the encoded
    /// payload stays short and readable.
    public static let allMajorVersions = 0

    /// Entitlements are names, not tiers with prices baked in. Pricing changes;
    /// what someone bought does not.
    public enum Entitlement: String {
        case personal
        case founder
        case commercial
        case trialExtension = "trial_extension"
    }

    public var entitlementKind: Entitlement? { Entitlement(rawValue: entitlement) }

    public var accessSummary: String {
        if let expiresAt {
            return "Free dictation until \(expiresAt.formatted(date: .abbreviated, time: .shortened)). No automatic charge."
        }
        return maxMajorVersion == Self.allMajorVersions
            ? "Permanent licence. Every future Mac update included."
            : "Permanent licence. Covers updates through \(maxMajorVersion).x."
    }

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
    case expired
    case existingLicenseIsBetter

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
        case .expired:
            return "That extension has expired. Open your invitation link for an updated licence, or buy PressTalk to keep dictating."
        case .existingLicenseIsBetter:
            return "Your saved licence already gives you longer access. It has been kept on this Mac."
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
    public func verify(_ encoded: String, now: Date = Date()) -> Result<PressTalkLicense, PressTalkLicenseError> {
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

        guard [PressTalkLicense.currentSchemaVersion, PressTalkLicense.expiringSchemaVersion].contains(license.schemaVersion) else {
            return .failure(.unsupportedSchema(license.schemaVersion))
        }
        if license.schemaVersion == PressTalkLicense.expiringSchemaVersion {
            guard license.entitlementKind == .trialExtension,
                  let expiry = license.expiresAt, expiry > license.issuedAt else {
                return .failure(.malformed("extension must have a valid expiry"))
            }
            guard now < expiry else { return .failure(.expired) }
        } else if license.expiresAt != nil || license.entitlementKind == .trialExtension {
            return .failure(.malformed("permanent schema cannot contain an extension"))
        }
        // A signature by a trusted key over someone else's product identifier
        // still must not unlock this one.
        guard license.productID == productID else {
            return .failure(.wrongProduct(license.productID))
        }
        guard license.keyID == envelopeKeyID else {
            return .failure(.malformed("key id does not match the envelope"))
        }
        if license.maxMajorVersion != PressTalkLicense.allMajorVersions,
           license.maxMajorVersion < runningMajorVersion {
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
