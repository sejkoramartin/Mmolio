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

    /// The raw status, plus a name for the ones that actually come up, so a failure can be
    /// acted on rather than merely reported.
    var diagnosticDescription: String {
        guard case .unexpectedStatus(let status) = self else { return "unknown" }
        switch status {
        case errSecMissingEntitlement:
            return "missing entitlement (\(status)) — the app is not allowed to use the Keychain"
        case errSecNotAvailable:
            return "Keychain unavailable (\(status)) — the device may still be locked"
        case errSecAuthFailed:
            return "authentication failed (\(status))"
        case errSecItemNotFound:
            return "written but not readable back (\(status))"
        case errSecInteractionNotAllowed:
            return "interaction not allowed (\(status)) — locked device"
        default:
            return "OSStatus \(status)"
        }
    }
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
///
/// Writes report failure rather than swallowing it. An earlier version used `try?`
/// everywhere, so a Keychain that refused to store anything left the app claiming to be
/// signed in while `hasLogin` stayed false — the sign-in form disappeared and the source
/// then said "no LibreLinkUp account configured", with nothing to explain the difference.
final class LibreCredentials {

    fileprivate enum Key {
        static let email = "email"
        static let password = "password"
        static let token = "token"
        static let accountID = "accountId"
        static let patientID = "patientId"
        static let region = "region"
        static let host = "host"
    }

    private let store: SecretStoring

    /// Last write failure, so the UI can show what actually went wrong.
    private(set) var lastStoreError: KeychainError?

    init(store: SecretStoring) {
        self.store = store
    }

    /// Writes a value, remembering any failure instead of discarding it.
    private func write(_ value: String?, for key: String) {
        do {
            try store.set(value, for: key)
            lastStoreError = nil
        } catch let error as KeychainError {
            lastStoreError = error
        } catch {
            lastStoreError = .unexpectedStatus(errSecInternalError)
        }
    }

    /// Stores the login and confirms it can be read back.
    ///
    /// The round trip is the point: a write that reports success but stores nothing is
    /// exactly the failure this is here to catch.
    @discardableResult
    func storeLogin(email: String, password: String, region: LibreRegion) -> Result<Void, KeychainError> {
        self.region = region
        write(email, for: Key.email)
        write(password, for: Key.password)
        clearSession()

        if let error = lastStoreError {
            return .failure(error)
        }
        guard hasLogin else {
            // Nothing threw, yet nothing came back. Report it rather than let the UI
            // believe the sign-in worked.
            return .failure(.unexpectedStatus(errSecItemNotFound))
        }
        return .success(())
    }

    var email: String? {
        get { store.value(for: Key.email) }
        set { write(newValue, for: Key.email) }
    }

    var password: String? {
        get { store.value(for: Key.password) }
        set { write(newValue, for: Key.password) }
    }

    /// Bearer token from the last successful sign-in.
    var token: String? {
        get { store.value(for: Key.token) }
        set { write(newValue, for: Key.token) }
    }

    /// Account identifier, hashed into a required request header by the API.
    var accountID: String? {
        get { store.value(for: Key.accountID) }
        set { write(newValue, for: Key.accountID) }
    }

    /// The followed patient whose readings we fetch.
    var patientID: String? {
        get { store.value(for: Key.patientID) }
        set { write(newValue, for: Key.patientID) }
    }

    /// Host the last successful sign-in ended up on, after any redirect. Nil until the
    /// first success, in which case the global entry point is used.
    var host: String? {
        get { store.value(for: Key.host) }
        set { write(newValue, for: Key.host) }
    }

    var region: LibreRegion {
        get { LibreRegion(rawValue: store.value(for: Key.region) ?? "") ?? .europe }
        set { write(newValue.rawValue, for: Key.region) }
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
        // The host is deliberately kept: it was discovered by the service and is still
        // correct even when the token has expired.
    }

    /// Removes everything, for sign-out.
    func clearAll() {
        try? store.removeAll()
    }
}
