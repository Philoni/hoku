import Foundation

public enum CloudError: Error, LocalizedError, Equatable, Sendable {
    case notConfigured
    case signInRequired
    case rateLimited
    case http(Int, String?)
    case unreachable(String)
    case unexpected(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured: String(localized: "Der Hue-Fernzugriff ist noch nicht eingerichtet.", bundle: .hueKit)
        case .signInRequired: String(localized: "Bitte melde dich erneut bei Hue an.", bundle: .hueKit)
        case .rateLimited: String(localized: "Die Hue-Cloud bremst gerade. Später noch einmal versuchen.", bundle: .hueKit)
        case let .http(code, message): String(localized: "Hue-Cloud-Fehler \(code)", bundle: .hueKit) + (message.map { ": \($0)" } ?? "")
        case let .unreachable(detail): String(localized: "Hue-Cloud nicht erreichbar (\(detail)).", bundle: .hueKit)
        case let .unexpected(detail): String(localized: "Unerwartete Antwort der Hue-Cloud: \(detail)", bundle: .hueKit)
        }
    }
}

/// Sends HTTP requests. URLSession in the app, a fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw CloudError.unreachable(String(localized: "keine HTTP-Antwort", bundle: .hueKit)) }
            return (data, http)
        } catch let error as URLError {
            throw CloudError.unreachable(error.localizedDescription)
        }
    }
}

/// The Hue remote API (api.meethue.com): token exchange and rotation, the remote
/// bridge key, and the few CLIP v2 calls the "lights left on" reminder needs.
///
/// Tokens are written to the Keychain *before* they are used: every refresh
/// invalidates the previous refresh token, so losing a new one would lock Hoku out.
public actor HueCloud {
    public static let shared = HueCloud()

    static let host = "api.meethue.com"

    private let store: CloudAccountStore
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    /// A refresh in flight; concurrent callers wait for it instead of spending the
    /// same refresh token twice (the second attempt would sign the user out).
    private var refreshTask: Task<CloudTokens, Error>?

    public init(
        store: CloudAccountStore = .keychain,
        transport: any HTTPTransport = URLSessionTransport(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.transport = transport
        self.now = now
    }

    // MARK: Account

    public func account() throws -> CloudAccount? {
        try store.load()
    }

    /// Stores the user's remote app. A different client ID invalidates everything
    /// that was issued to the old one.
    public func saveApp(_ app: CloudAppCredentials) throws {
        var account = try store.load() ?? CloudAccount(app: app)
        if account.app.clientID != app.clientID {
            account = CloudAccount(app: app)
        }
        account.app = app
        try store.save(account)
    }

    /// Forgets the tokens and the remote key; `keepingApp` keeps the client ID and
    /// secret so signing in again is one click.
    public func signOut(keepingApp: Bool) throws {
        refreshTask?.cancel()
        refreshTask = nil
        guard keepingApp, let app = try store.load()?.app else {
            try store.delete()
            return
        }
        try store.save(CloudAccount(app: app))
    }

    // MARK: Sign-in

    /// Exchanges the code from the browser for tokens, then creates the remote
    /// bridge key and learns which bridge the account granted.
    public func completeSignIn(code: String, authorization: CloudAuthorization, deviceType: String) async throws -> CloudAccount {
        guard var account = try store.load(), account.app.isComplete else { throw CloudError.notConfigured }
        let tokens = try await requestTokens(app: account.app, form: [
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": authorization.codeVerifier,
        ])
        account.tokens = tokens
        account.applicationKey = nil
        account.bridgeID = nil
        try store.save(account)

        account.applicationKey = try await createApplicationKey(deviceType: deviceType)
        try store.save(account)

        account.bridgeID = try await bridgeID()
        try store.save(account)
        return account
    }

    // MARK: Resources

    /// All resources in one call (rate limits count calls, not bytes).
    public func resources() async throws -> [JSONValue] {
        let (data, _) = try await authorized(path: "/route/clip/v2/resource")
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
            throw CloudError.unexpected(String(localized: "Ressourcen nicht lesbar", bundle: .hueKit))
        }
        if let message = envelope.errors.first?.description, envelope.data.isEmpty {
            throw CloudError.unexpected(message)
        }
        return envelope.data
    }

    public func setOn(_ on: Bool, groupedLight id: String) async throws {
        let body = try JSONEncoder().encode(JSONValue.object(["on": ["on": .bool(on)]]))
        let (data, _) = try await authorized(path: "/route/clip/v2/resource/grouped_light/\(id)", method: "PUT", body: body)
        if let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.errors.first?.description {
            throw CloudError.unexpected(message)
        }
    }

    // MARK: Internals

    private func bridgeID() async throws -> String {
        let (data, _) = try await authorized(path: "/route/clip/v2/resource/bridge")
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let id = envelope.data.first?["bridge_id"]?.stringValue
        else { throw CloudError.unexpected(String(localized: "keine Bridge im Hue-Konto", bundle: .hueKit)) }
        return id.lowercased()
    }

    /// Virtually presses the link button through the cloud, then registers a key —
    /// the remote counterpart of local pairing.
    private func createApplicationKey(deviceType: String) async throws -> String {
        let press = try JSONEncoder().encode(JSONValue.object(["linkbutton": .bool(true)]))
        _ = try await authorized(path: "/route/api/0/config", method: "PUT", body: press, sendsKey: false)

        let body = try JSONEncoder().encode(JSONValue.object(["devicetype": .string(String(deviceType.prefix(40)))]))
        let (data, _) = try await authorized(path: "/route/api", method: "POST", body: body, sendsKey: false)
        let entries = (try? JSONDecoder().decode([JSONValue].self, from: data)) ?? []
        if let username = entries.first?["success"]?["username"]?.stringValue {
            return username
        }
        let message = entries.first?["error"]?["description"]?.stringValue ?? String(decoding: data, as: UTF8.self)
        throw CloudError.unexpected(message)
    }

    /// A request with a valid access token (and the remote key), refreshed and
    /// retried once if the cloud says the token is no longer good.
    private func authorized(
        path: String, method: String = "GET", body: Data? = nil, sendsKey: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        var tokens = try await validTokens()
        for attempt in 1...2 {
            guard let account = try store.load() else { throw CloudError.notConfigured }
            var components = URLComponents()
            components.scheme = "https"
            components.host = Self.host
            components.path = path
            var request = URLRequest(url: components.url!)
            request.httpMethod = method
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
            if sendsKey {
                guard let key = account.applicationKey else { throw CloudError.signInRequired }
                request.setValue(key, forHTTPHeaderField: "hue-application-key")
            }
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }

            let (data, response) = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                return (data, response)
            case 401 where attempt == 1:
                tokens = try await refresh(using: tokens)
            case 401, 403:
                throw CloudError.signInRequired
            case 429:
                throw CloudError.rateLimited
            default:
                throw CloudError.http(response.statusCode, Self.errorMessage(data))
            }
        }
        throw CloudError.signInRequired
    }

    private func validTokens() async throws -> CloudTokens {
        guard let account = try store.load() else { throw CloudError.notConfigured }
        guard let tokens = account.tokens else { throw CloudError.signInRequired }
        return tokens.needsRefresh(at: now()) ? try await refresh(using: tokens) : tokens
    }

    private func refresh(using stale: CloudTokens) async throws -> CloudTokens {
        if let refreshTask { return try await refreshTask.value }
        // Another caller may have refreshed while this one was waiting.
        if let current = try store.load()?.tokens, current != stale, !current.needsRefresh(at: now()) {
            return current
        }
        let task = Task { try await self.performRefresh() }
        refreshTask = task
        // A sign-out may have started a newer one meanwhile; leave that one alone.
        defer { if refreshTask == task { refreshTask = nil } }
        return try await task.value
    }

    private func performRefresh() async throws -> CloudTokens {
        guard let account = try store.load() else { throw CloudError.notConfigured }
        guard let refreshToken = account.tokens?.refreshToken else { throw CloudError.signInRequired }
        do {
            let tokens = try await requestTokens(app: account.app, form: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
            ])
            // The actor ran other work during the request: a sign-out must stay a
            // sign-out, so only write into the account this refresh started from.
            guard var latest = try store.load(), latest.tokens?.refreshToken == refreshToken else {
                throw CloudError.signInRequired
            }
            latest.tokens = tokens
            try store.save(latest)
            return tokens
        } catch CloudError.http(let code, _) where code == 400 || code == 401 {
            // The refresh token is gone (revoked in the Hue account, or rotated elsewhere).
            if var latest = try? store.load(), latest.tokens?.refreshToken == refreshToken {
                latest.tokens = nil
                try? store.save(latest)
            }
            throw CloudError.signInRequired
        }
    }

    private func requestTokens(app: CloudAppCredentials, form: [String: String]) async throws -> CloudTokens {
        var request = tokenRequest()
        let basic = Data("\(app.clientID):\(app.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.httpBody = Self.formBody(form)
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 200:
            return try Self.decodeTokens(data, now: now())
        case 429:
            throw CloudError.rateLimited
        default:
            throw CloudError.http(response.statusCode, Self.errorMessage(data))
        }
    }

    private func tokenRequest() -> URLRequest {
        var request = URLRequest(url: URL(string: "https://\(Self.host)/v2/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        return request
    }

    static func decodeTokens(_ data: Data, now: Date) throws -> CloudTokens {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data),
              let access = json["access_token"]?.stringValue,
              let refresh = json["refresh_token"]?.stringValue
        else { throw CloudError.unexpected(String(localized: "keine Tokens in der Antwort", bundle: .hueKit)) }
        // Signify's docs show `expires_in` both as a number and as a string.
        let seconds: Double = switch json["expires_in"] {
        case let .number(value): value
        case let .string(value): Double(value) ?? 3600
        default: 3600
        }
        return CloudTokens(accessToken: access, refreshToken: refresh, expiresAt: now.addingTimeInterval(seconds))
    }

    static func formBody(_ form: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let pairs = form.sorted { $0.key < $1.key }.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }

    /// The error text only, never the request — it would contain tokens.
    static func errorMessage(_ data: Data) -> String? {
        guard let json = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        return json["error_description"]?.stringValue
            ?? json["error"]?.stringValue
            ?? json["errors"].flatMap { if case let .array(items) = $0 { items.first?["description"]?.stringValue } else { nil } }
            ?? json["fault"]?["faultstring"]?.stringValue
    }
}
