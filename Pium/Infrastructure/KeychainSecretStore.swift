import Foundation
import Security

/// The secret configuration values a plugin declares.
///
/// Secrets live in the Keychain and reach a child process only as environment
/// variables (PRD §10.5). Nothing in this phase reads one: the form reports
/// whether a secret is stored, never what it is.
@MainActor
protocol PluginSecretStoring {
    func hasSecret(pluginID: String, key: String) -> Bool
    /// `nil` removes the secret.
    func setSecret(_ value: String?, pluginID: String, key: String) throws
    func secret(pluginID: String, key: String) throws -> String?
    /// Every plugin with at least one stored secret, for finding orphans.
    func storedPluginIDs() -> Set<String>
    func removeSecrets(pluginID: String) throws
    /// Rebuilds the presence index from the Keychain.
    func reconcile()
}

enum SecretStoreError: Error, Equatable {
    case keychain(OSStatus)
}

@MainActor
final class KeychainSecretStore: PluginSecretStoring {
    /// The bundle identifier appears here, so it is written once. Changing it
    /// means migrating items stored under the old service name.
    static let defaultService = "com.lardissone.pium.plugin-secrets"

    private static let indexKey = "pium.plugin.storedSecrets"

    private let defaults: UserDefaults
    private let service: String

    init(defaults: UserDefaults = .standard, service: String = KeychainSecretStore.defaultService) {
        self.defaults = defaults
        self.service = service
    }

    // MARK: - Presence, answered without the Keychain

    func hasSecret(pluginID: String, key: String) -> Bool {
        storedAccounts().contains(Self.account(pluginID, key))
    }

    func storedPluginIDs() -> Set<String> {
        Set(storedAccounts().compactMap { $0.split(separator: "/").first.map(String.init) })
    }

    // MARK: - The Keychain itself

    func setSecret(_ value: String?, pluginID: String, key: String) throws {
        let account = Self.account(pluginID, key)
        guard let value, !value.isEmpty else {
            try delete(account: account)
            record(account: account, present: false)
            return
        }

        // Delete then add rather than update: an update on a missing item
        // fails, and branching on that is more code than removing first.
        try delete(account: account)
        // Reflect the deletion immediately: if SecItemAdd below fails, the
        // index must not keep claiming the old item is still there.
        record(account: account, present: false)
        var attributes = query(account: account)
        attributes[kSecValueData as String] = Data(value.utf8)
        // After first unlock: Pium can launch at login and read its own
        // secrets without the user being at the keyboard.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        record(account: account, present: true)
    }

    func secret(pluginID: String, key: String) throws -> String? {
        var attributes = query(account: Self.account(pluginID, key))
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        guard let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func removeSecrets(pluginID: String) throws {
        for account in storedAccounts() where account.hasPrefix("\(pluginID)/") {
            try delete(account: account)
            record(account: account, present: false)
        }
    }

    func reconcile() {
        var attributes = query(account: nil)
        attributes[kSecReturnAttributes as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitAll

        var items: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &items)
        guard status == errSecSuccess, let found = items as? [[String: Any]] else {
            // Nothing found is a legitimate answer; anything else leaves the
            // index alone rather than destroying it on a transient failure.
            if status == errSecItemNotFound { defaults.set([String](), forKey: Self.indexKey) }
            return
        }
        let accounts = found.compactMap { $0[kSecAttrAccount as String] as? String }
        defaults.set(accounts.sorted(), forKey: Self.indexKey)
    }

    // MARK: - Plumbing

    private func delete(account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecretStoreError.keychain(status)
        }
    }

    private func query(account: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    private func storedAccounts() -> Set<String> {
        Set(defaults.stringArray(forKey: Self.indexKey) ?? [])
    }

    /// The index the result list reads, kept in step with the item itself so
    /// the Keychain never sits on the query path.
    private func record(account: String, present: Bool) {
        var accounts = storedAccounts()
        if present { accounts.insert(account) } else { accounts.remove(account) }
        defaults.set(accounts.sorted(), forKey: Self.indexKey)
    }

    private static func account(_ pluginID: String, _ key: String) -> String {
        "\(pluginID)/\(key)"
    }
}

/// Stands in for the Keychain in every test that is not about the Keychain.
@MainActor
final class InMemorySecretStore: PluginSecretStoring {
    private var secrets: [String: String] = [:]

    init(secrets: [String: String] = [:]) {
        self.secrets = secrets
    }

    func hasSecret(pluginID: String, key: String) -> Bool {
        secrets["\(pluginID)/\(key)"] != nil
    }

    func setSecret(_ value: String?, pluginID: String, key: String) throws {
        let account = "\(pluginID)/\(key)"
        guard let value, !value.isEmpty else {
            secrets[account] = nil
            return
        }
        secrets[account] = value
    }

    func secret(pluginID: String, key: String) throws -> String? {
        secrets["\(pluginID)/\(key)"]
    }

    func storedPluginIDs() -> Set<String> {
        Set(secrets.keys.compactMap { $0.split(separator: "/").first.map(String.init) })
    }

    func removeSecrets(pluginID: String) throws {
        for key in secrets.keys where key.hasPrefix("\(pluginID)/") { secrets[key] = nil }
    }

    func reconcile() {}
}
