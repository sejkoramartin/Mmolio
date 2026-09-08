//
//  CredentialStore.swift
//  MedProbe
//
//  Keychain-backed storage for LibreLinkUp credentials and session tokens.
//
//  Nothing here may be written to UserDefaults, to the capture file, or to the log.
//  Accessors deliberately return values rather than logging them, and the diagnostic log
//  is never handed a token.
//

import Foundation
import Security

/// Stores a small named secret in the Keychain.
protocol SecretStoring: AnyObject {
    func set(_ value: String?, for key: String) throws
    func value(for key: String) -> String?
    func removeAll() throws
}

enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}

/// Keychain implementation.
///
/// Items use `kSecAttrAccessibleAfterFirstUnlock` so a background refresh can read them
/// while the phone is locked, which is required for the app to keep working on the wrist
/// without the user unlocking the phone first.
final class KeychainSecretStore: SecretStoring {

    private let service: String

    init(service: String = "cz.sejkora.MedProbe.librelinkup") {
        self.service = service
    }

    private func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func set(_ value: String?, for key: String) throws {
        // Delete first: SecItemUpdate would need a separate not-found path, and this keeps
        // "set to nil means remove" in one place.
        SecItemDelete(query(for: key) as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }

        var attributes = query(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func value(for key: String) -> String? {
        var attributes = query(for: key)
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(attributes as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }

        return String(data: data, encoding: .utf8)
    }

    func removeAll() throws {
        let status = SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ] as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory store, for tests. Never used in the app.
final class InMemorySecretStore: SecretStoring {

    private var storage: [String: String] = [:]

    func set(_ value: String?, for key: String) throws {
        storage[key] = value
    }

    func value(for key: String) -> String? {
        storage[key]
    }

    func removeAll() throws {
        storage.removeAll()
    }
}

/// The credentials and session state LibreLinkUp needs, kept together so nothing leaks
/// into general app storage.
final class LibreCredentials {

    private enum Key {
        static let email = "email"
        static let password = "password"
        static let token = "token"
        static let accountID = "accountId"
        static let patientID = "patientId"
        static let region = "region"
    }

    private let store: SecretStoring

    init(store: SecretStoring) {
        self.store = store
    }

    var email: String? {
        get { store.value(for: Key.email) }
        set { try? store.set(newValue, for: Key.email) }
    }

    var password: String? {
        get { store.value(for: Key.password) }
        set { try? store.set(newValue, for: Key.password) }
    }

    /// Bearer token from the last successful sign-in.
    var token: String? {
        get { store.value(for: Key.token) }
        set { try? store.set(newValue, for: Key.token) }
    }

    /// Account identifier, hashed into a required request header by the API.
    var accountID: String? {
        get { store.value(for: Key.accountID) }
        set { try? store.set(newValue, for: Key.accountID) }
    }

    /// The followed patient whose readings we fetch.
    var patientID: String? {
        get { store.value(for: Key.patientID) }
        set { try? store.set(newValue, for: Key.patientID) }
    }

    var region: LibreRegion {
        get { LibreRegion(rawValue: store.value(for: Key.region) ?? "") ?? .europe }
        set { try? store.set(newValue.rawValue, for: Key.region) }
    }

    var hasLogin: Bool {
        guard let email, let password else { return false }
        return !email.isEmpty && !password.isEmpty
    }

    var hasSession: Bool {
        token != nil && accountID != nil
    }

    /// Drops the session but keeps the login, so a 401 can be retried by signing in again.
    func clearSession() {
        token = nil
        accountID = nil
        patientID = nil
    }

    /// Removes everything, for sign-out.
    func clearAll() {
        try? store.removeAll()
    }
}
