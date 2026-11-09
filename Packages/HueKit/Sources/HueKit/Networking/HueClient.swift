import Foundation

public enum HueError: Error, LocalizedError, Sendable {
    case unauthorized
    case bridgeUnreachable(String)
    case http(Int, String?)
    case linkButtonNotPressed
    case bridge(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            String(localized: "Die Bridge kennt diese App nicht mehr. Bitte neu koppeln.", bundle: .module)
        case let .bridgeUnreachable(detail):
            String(localized: "Bridge nicht erreichbar (\(detail)).", bundle: .module)
        case let .http(code, message):
            String(localized: "Bridge-Fehler \(code)", bundle: .module) + (message.map { ": \($0)" } ?? "")
        case .linkButtonNotPressed:
            String(localized: "Die Link-Taste wurde noch nicht gedrückt.", bundle: .module)
        case let .bridge(message):
            message
        case let .decoding(detail):
            String(localized: "Antwort der Bridge nicht lesbar: \(detail)", bundle: .module)
        }
    }
}

/// Everything the app needs to talk to one bridge.
public struct BridgeCredentials: Codable, Hashable, Sendable {
    public var bridgeID: String
    public var host: String
    public var applicationKey: String
    public var clientKey: String?
    public var name: String?

    public init(bridgeID: String, host: String, applicationKey: String, clientKey: String? = nil, name: String? = nil) {
        self.bridgeID = bridgeID
        self.host = host
        self.applicationKey = applicationKey
        self.clientKey = clientKey
        self.name = name
    }
}

/// Public, unauthenticated bridge info from `GET /api/0/config`.
public struct BridgeConfig: Codable, Hashable, Sendable {
    public var name: String
    public var bridgeID: String
    public var modelID: String
    public var swVersion: String
    public var apiVersion: String

    enum CodingKeys: String, CodingKey {
        case name
        case bridgeID = "bridgeid"
        case modelID = "modelid"
        case swVersion = "swversion"
        case apiVersion = "apiversion"
    }

    /// CLIP v2 needs firmware 1948086000 or newer.
    public var supportsCLIPv2: Bool {
        (Int(swVersion) ?? 0) >= 1_948_086_000
    }
}

/// Thin async wrapper around the CLIP v2 REST API.
public final class HueClient: Sendable {
    public let trust: BridgeTrustEvaluator
    let session: URLSession
    let streamSession: URLSession

    public init(trust: BridgeTrustEvaluator = BridgeTrustEvaluator()) {
        self.trust = trust

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        // The bridge answers 429 beyond ~3 concurrent requests.
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration, delegate: trust, delegateQueue: nil)

        let streamConfiguration = URLSessionConfiguration.ephemeral
        // The event stream can be silent for a long time. A generous idle timeout
        // doubles as a watchdog for connections that died without notice.
        streamConfiguration.timeoutIntervalForRequest = 300
        streamConfiguration.timeoutIntervalForResource = .infinity
        streamSession = URLSession(configuration: streamConfiguration, delegate: trust, delegateQueue: nil)
    }

    // MARK: Unauthenticated

    public func config(host: String) async throws -> BridgeConfig {
        let request = URLRequest(url: try url(host: host, path: "/api/0/config"))
        let (data, _) = try await perform(request)
        do {
            return try JSONDecoder().decode(BridgeConfig.self, from: data)
        } catch {
            throw HueError.decoding(error.localizedDescription)
        }
    }

    /// One pairing attempt. Throws `linkButtonNotPressed` until the user presses the button.
    public func requestApplicationKey(host: String, deviceType: String) async throws -> (key: String, clientKey: String?) {
        var request = URLRequest(url: try url(host: host, path: "/api"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(PairingRequest(devicetype: deviceType, generateclientkey: true))
        let (data, _) = try await perform(request)

        let entries = (try? JSONDecoder().decode([PairingResponse].self, from: data)) ?? []
        if let success = entries.first?.success {
            return (success.username, success.clientkey)
        }
        if let error = entries.first?.error {
            if error.type == 101 { throw HueError.linkButtonNotPressed }
            throw HueError.bridge(error.description)
        }
        throw HueError.decoding(String(decoding: data, as: UTF8.self))
    }

    // MARK: Authenticated

    /// All resources in a single request, as raw JSON objects.
    public func allResources(_ credentials: BridgeCredentials) async throws -> [JSONValue] {
        try await resources(credentials, path: "/clip/v2/resource")
    }

    public func resource(_ credentials: BridgeCredentials, type: String, id: String) async throws -> JSONValue? {
        try await resources(credentials, path: "/clip/v2/resource/\(type)/\(id)").first
    }

    public func update(_ credentials: BridgeCredentials, type: String, id: String, body: JSONValue) async throws {
        var request = try authorizedRequest(credentials, path: "/clip/v2/resource/\(type)/\(id)")
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        // 429/503 mean "busy" — back off briefly and retry a couple of times.
        for attempt in 1...3 {
            do {
                let (data, _) = try await perform(request)
                let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
                if let message = envelope?.errors.first?.description {
                    throw HueError.bridge(message)
                }
                return
            } catch let HueError.http(code, _) where (code == 429 || code == 503) && attempt < 3 {
                try await Task.sleep(for: .milliseconds(250 * attempt))
            }
        }
    }

    /// Creates a resource and returns its new ID.
    public func create(_ credentials: BridgeCredentials, type: String, body: JSONValue) async throws -> String? {
        var request = try authorizedRequest(credentials, path: "/clip/v2/resource/\(type)")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, _) = try await perform(request)
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if let message = envelope?.errors.first?.description { throw HueError.bridge(message) }
        return envelope?.data.first?["rid"]?.stringValue
    }

    public func delete(_ credentials: BridgeCredentials, type: String, id: String) async throws {
        var request = try authorizedRequest(credentials, path: "/clip/v2/resource/\(type)/\(id)")
        request.httpMethod = "DELETE"
        let (data, _) = try await perform(request)
        let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        if let message = envelope?.errors.first?.description { throw HueError.bridge(message) }
    }

    // MARK: Internals

    private func resources(_ credentials: BridgeCredentials, path: String) async throws -> [JSONValue] {
        let request = try authorizedRequest(credentials, path: path)
        let (data, _) = try await perform(request)
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            if let message = envelope.errors.first?.description, envelope.data.isEmpty {
                throw HueError.bridge(message)
            }
            return envelope.data
        } catch let error as HueError {
            throw error
        } catch {
            throw HueError.decoding(error.localizedDescription)
        }
    }

    func authorizedRequest(_ credentials: BridgeCredentials, path: String) throws -> URLRequest {
        trust.pin(host: credentials.host, bridgeID: credentials.bridgeID)
        var request = URLRequest(url: try url(host: credentials.host, path: path))
        request.setValue(credentials.applicationKey, forHTTPHeaderField: "hue-application-key")
        return request
    }

    func url(host: String, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        guard let url = components.url else { throw HueError.bridgeUnreachable(String(localized: "ungültige Adresse \(host)", bundle: .module)) }
        return url
    }

    private func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw HueError.bridgeUnreachable(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw HueError.bridgeUnreachable(String(localized: "keine HTTP-Antwort", bundle: .module))
        }
        switch http.statusCode {
        case 200..<300:
            return (data, http)
        case 401, 403:
            // The square bridge answers a bad key with an HTML 403 page.
            throw HueError.unauthorized
        default:
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
            throw HueError.http(http.statusCode, envelope?.errors.first?.description)
        }
    }
}

struct Envelope: Decodable {
    struct BridgeError: Decodable {
        var description: String
    }

    var errors: [BridgeError]
    var data: [JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        errors = try container.decodeIfPresent([BridgeError].self, forKey: .errors) ?? []
        data = try container.decodeIfPresent([JSONValue].self, forKey: .data) ?? []
    }

    enum CodingKeys: String, CodingKey { case errors, data }
}

private struct PairingRequest: Encodable {
    var devicetype: String
    var generateclientkey: Bool
}

private struct PairingResponse: Decodable {
    struct Success: Decodable {
        var username: String
        var clientkey: String?
    }

    struct Failure: Decodable {
        var type: Int
        var description: String
    }

    var success: Success?
    var error: Failure?
}
