import Foundation

/// The paid licence lives in app preferences and is verified without a network
/// or Keychain read. Trial anchors are a separate concern.
public final class OfflineLicenseStore {
    private let defaults: UserDefaults
    private let verifier: PressTalkLicenseVerifier
    private let storageKey = "PressTalk.License"
    private let now: () -> Date

    public init(defaults: UserDefaults, verifier: PressTalkLicenseVerifier, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.verifier = verifier
        self.now = now
    }

    public var license: PressTalkLicense? {
        guard let encoded = defaults.string(forKey: storageKey),
              case .success(let value) = verifier.verify(encoded, now: now()) else { return nil }
        return value
    }

    @discardableResult
    public func importLicense(_ encoded: String) -> Result<PressTalkLicense, PressTalkLicenseError> {
        let result = verifier.verify(encoded, now: now())
        if case .success(let incoming) = result {
            if let existing = license {
                let oldExpiry = existing.expiresAt ?? .distantFuture
                let newExpiry = incoming.expiresAt ?? .distantFuture
                let oldMajor = existing.maxMajorVersion == 0 ? Int.max : existing.maxMajorVersion
                let newMajor = incoming.maxMajorVersion == 0 ? Int.max : incoming.maxMajorVersion
                if oldExpiry > newExpiry || oldMajor > newMajor {
                    return .failure(.existingLicenseIsBetter)
                }
            }
            defaults.set(encoded.trimmingCharacters(in: .whitespacesAndNewlines), forKey: storageKey)
        }
        return result
    }
}
