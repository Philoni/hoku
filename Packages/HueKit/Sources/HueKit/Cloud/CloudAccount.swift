import Foundation
import Security

/// The user's own Hue remote app, registered at developers.meethue.com.
/// Every user brings their own: Signify's terms forbid sharing these credentials,
/// and an open-source app cannot keep a shared secret secret.
public struct CloudAppCredentials: Codable, Hashable, Sendable {
    public var clientID: String
    public var clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clientSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isComplete: Bool { !clientID.isEmpty && !clientSecret.isEmpty }
}

public struct CloudTokens: Codable, Hashable, Sendable {
    public var accessToken: String
    /// Never expires, but every refresh replaces it and invalidates the old one.
    public var refreshToken: String
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Refresh a little early, so a request never races the expiry.
    public func needsRefresh(at now: Date = .now) -> Bool {
        expiresAt.timeIntervalSince(now) < 5 * 60
    }
}

/// Everything Hoku keeps for the remote API, stored as one Keychain item.
public struct CloudAccount: Codable, Hashable, Sendable {
    public var app: CloudAppCredentials
    public var tokens: CloudTokens?
    /// The bridge whitelist key created through the cloud, separate from the local one.
    public var applicationKey: String?
    /// The bridge the Hue account granted access to (lower-cased).
    public var bridgeID: String?

    public init(app: CloudAppCredentials, tokens: CloudTokens? = nil, applicationKey: String? = nil, bridgeID: String? = nil) {
        self.app = app
        self.tokens = tokens
        self.applicationKey = applicationKey
        self.bridgeID = bridgeID
    }

    /// Usable only with the bridge known: without it Hoku can't check that the account
    /// grants the paired bridge, and a half-finished sign-in must be repeated.
    public var isSignedIn: Bool { tokens != nil && applicationKey != nil && bridgeID != nil }
}

/// Where secrets live. The Keychain in the app, memory in tests.
public protocol SecretStore: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func delete() throws
}

public enum SecretStoreError: Error, LocalizedError, Sendable {
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .keychain(status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Code \(status)"
            return String(localized: "Schlüsselbund: \(message)", bundle: .module)
        }
    }
}

/// A generic password item in the login keychain. Never synced to iCloud; by default
/// only the app that created it (same code signature) can read it without asking.
public struct KeychainSecretStore: SecretStore {
    public let service: String
    public let account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    public func load() throws -> Data? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        return result as? Data
    }

    public func save(_ data: Data) throws {
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError.keychain(update) }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Hoku – Hue-Fernzugriff"
        // Only the data protection keychain enforces this; the login keychain (no team
        // ID in self-signed builds) ignores it. What keeps the item local is
        // kSecAttrSynchronizable = false: it never goes to iCloud.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw SecretStoreError.keychain(add) }
    }

    public func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}

/// For tests and previews.
public final class MemorySecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?

    public init(_ data: Data? = nil) { self.data = data }

    public func load() throws -> Data? { lock.withLock { data } }
    public func save(_ data: Data) throws { lock.withLock { self.data = data } }
    public func delete() throws { lock.withLock { data = nil } }
}

/// Reads and writes the `CloudAccount` as JSON in a `SecretStore`.
public struct CloudAccountStore: Sendable {
    public static let keychain = CloudAccountStore(
        secrets: KeychainSecretStore(service: "io.github.philoni.hoku.cloud", account: "hue-remote")
    )

    let secrets: any SecretStore

    public init(secrets: any SecretStore) {
        self.secrets = secrets
    }

    public func load() throws -> CloudAccount? {
        guard let data = try secrets.load() else { return nil }
        // A damaged item is an error to show, not \"never set up\" to overwrite silently.
        do { return try JSONDecoder().decode(CloudAccount.self, from: data) }
        catch { throw CloudError.unexpected(String(localized: "Gespeicherte Hue-Anmeldung ist beschädigt. Bitte neu einrichten.", bundle: .module)) }
    }

    public func save(_ account: CloudAccount) throws {
        try secrets.save(try JSONEncoder().encode(account))
    }

    public func delete() throws {
        try secrets.delete()
    }
}
