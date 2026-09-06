import Foundation
import Security
import PressTalkCore

/// One place a trial start date can be recorded.
protocol TrialAnchorStore {
    var name: String { get }
    func read() -> TrialAnchor.Reading
    /// Returns false if the write did not land, so a caller can log it rather
    /// than assume redundancy it does not have.
    @discardableResult func write(_ date: Date) -> Bool
}

/// UserDefaults. Convenient, and the first thing a reinstall removes.
struct UserDefaultsTrialAnchorStore: TrialAnchorStore {
    let name = "defaults"
    let defaults: UserDefaults
    let key: String

    func read() -> TrialAnchor.Reading {
        // UserDefaults has no failure mode to distinguish here: a missing key
        // and an unreadable domain look identical, so this can only ever report
        // found or absent. That is exactly why it is not the only store.
        guard let date = defaults.object(forKey: key) as? Date else { return .absent }
        return .found(date)
    }

    @discardableResult func write(_ date: Date) -> Bool {
        defaults.set(date, forKey: key)
        return true
    }
}

/// The login keychain.
///
/// This is what makes the trial survive "delete the app, delete the preference
/// file, download it again". Keychain items are not owned by the application
/// bundle, so removing the app leaves them in place.
///
/// It is not copy protection and is not meant to be. Someone who opens Keychain
/// Access and deletes the item gets another trial, and someone who creates a
/// second macOS user account gets another one too. The goal is that the reset
/// is a deliberate act rather than a side effect of reinstalling, which is what
/// separates "the trial ends" from "the trial ends until you drag the app to
/// the bin".
struct KeychainTrialAnchorStore: TrialAnchorStore {
    let name = "keychain"
    let service: String
    let account: String

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // Readable only while the Mac is unlocked, and never synced to
            // another device: a trial is a fact about this machine, and iCloud
            // Keychain would carry it to a Mac that never installed the app.
            kSecAttrSynchronizable as String: false,
        ]
    }

    func read() -> TrialAnchor.Reading {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let seconds = TimeInterval(text)
            else {
                // Present but unparseable. Not absent -- something is there and
                // this code cannot read it, which is the definition of
                // unavailable. Reporting absent would hand out a fresh trial.
                return .unavailable
            }
            return .found(Date(timeIntervalSince1970: seconds))
        case errSecItemNotFound:
            return .absent
        default:
            // errSecInteractionNotAllowed (locked keychain), errSecAuthFailed,
            // and everything else. The item may well exist.
            return .unavailable
        }
    }

    @discardableResult func write(_ date: Date) -> Bool {
        let payload = Data(String(date.timeIntervalSince1970).utf8)
        var attributes = baseQuery
        attributes[kSecValueData as String] = payload
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return true }
        if status == errSecDuplicateItem {
            // Only ever reached while healing, and healing writes the resolved
            // earliest date, so this cannot move a start date later.
            return SecItemUpdate(
                baseQuery as CFDictionary,
                [kSecValueData as String: payload] as CFDictionary) == errSecSuccess
        }
        return false
    }
}
