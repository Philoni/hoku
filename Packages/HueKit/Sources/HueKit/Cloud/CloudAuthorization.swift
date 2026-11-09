import CryptoKit
import Foundation
import Security

/// One sign-in attempt with the Hue account: the browser URL, and checking what
/// comes back. Authorization code flow with PKCE (RFC 7636) and a `state` value
/// against forged callbacks (RFC 6749 §10.12), as RFC 8252 recommends for desktop apps.
public struct CloudAuthorization: Sendable {
    public static let callbackScheme = "hoku"
    public static let callbackURL = "hoku://oauth"
    static let authorizeEndpoint = URL(string: "https://api.meethue.com/v2/oauth2/authorize")!

    public let clientID: String
    public let state: String
    public let codeVerifier: String
    public let deviceName: String

    public init(clientID: String, deviceName: String) {
        self.init(clientID: clientID, deviceName: deviceName, state: Self.randomString(), codeVerifier: Self.randomString())
    }

    init(clientID: String, deviceName: String, state: String, codeVerifier: String) {
        self.clientID = clientID
        self.deviceName = deviceName
        self.state = state
        self.codeVerifier = codeVerifier
    }

    /// S256: base64url(SHA-256(verifier)), without padding.
    public var codeChallenge: String {
        Self.base64URL(Data(SHA256.hash(data: Data(codeVerifier.utf8))))
    }

    /// The page the browser opens. `devicename` shows up in the Hue account as
    /// "Hoku on <devicename>", so the user can revoke this Mac there.
    public var url: URL {
        var components = URLComponents(url: Self.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "devicename", value: deviceName),
        ]
        return components.url!
    }

    public enum CallbackError: Error, LocalizedError, Equatable, Sendable {
        case wrongState
        case denied(String)
        case missingCode

        public var errorDescription: String? {
            switch self {
            case .wrongState: String(localized: "Die Antwort passt nicht zu dieser Anmeldung. Bitte noch einmal versuchen.", bundle: .module)
            case let .denied(reason): String(localized: "Hue hat die Anmeldung abgelehnt (\(reason)).", bundle: .module)
            case .missingCode: String(localized: "Hue hat keinen Anmeldecode geschickt.", bundle: .module)
            }
        }
    }

    /// The authorization code from `hoku://oauth?code=…&state=…`. The state must be
    /// the one sent, otherwise the callback did not come from this sign-in.
    public func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == state else { throw CallbackError.wrongState }
        if let error = value("error") { throw CallbackError.denied(error) }
        guard let code = value("code"), !code.isEmpty else { throw CallbackError.missingCode }
        return code
    }

    /// 32 random bytes, base64url: 43 characters, inside PKCE's 43–128 range.
    static func randomString() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "No secure random bytes")
        return base64URL(Data(bytes))
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
