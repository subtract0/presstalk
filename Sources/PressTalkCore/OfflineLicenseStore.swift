import Foundation

/// The paid licence lives in app preferences and is verified without a network
/// or Keychain read. Trial anchors are a separate concern.
public final class OfflineLicenseStore {
    private let defaults: UserDefaults
    private let verifier: PressTalkLicenseVerifier
    private let storageKey = "PressTalk.License"

    public init(defaults: UserDefaults, verifier: PressTalkLicenseVerifier) {
        self.defaults = defaults
        self.verifier = verifier
    }

    public var license: PressTalkLicense? {
        guard let encoded = defaults.string(forKey: storageKey),
              case .success(let value) = verifier.verify(encoded) else { return nil }
        return value
    }

    @discardableResult
    public func importLicense(_ encoded: String) -> Result<PressTalkLicense, PressTalkLicenseError> {
        let result = verifier.verify(encoded)
        if case .success = result {
            defaults.set(encoded.trimmingCharacters(in: .whitespacesAndNewlines), forKey: storageKey)
        }
        return result
    }
}
