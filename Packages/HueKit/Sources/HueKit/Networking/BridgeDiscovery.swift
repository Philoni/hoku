import Foundation
import Network
import Synchronization

public struct DiscoveredBridge: Hashable, Sendable, Identifiable {
    /// Lower-case bridge ID, e.g. `001788fffe123456`.
    public var id: String
    public var host: String
    public var name: String
    public var modelID: String?

    public init(id: String, host: String, name: String, modelID: String?) {
        self.id = id
        self.host = host
        self.name = name
        self.modelID = modelID
    }
}

/// Finds bridges the way Signify recommends: mDNS first, the cloud endpoint as a
/// fallback, and manual IP entry as the last resort. Every candidate is verified
/// against `/api/0/config` over pinned TLS before it is offered to the user.
public enum BridgeDiscovery {
    public struct Result: Sendable {
        public var bridges: [DiscoveredBridge]
        /// macOS answered the Bonjour search with "policy denied": local network access
        /// is off for Hoku (or its prompt is still open).
        public var isLocalNetworkDenied: Bool
    }

    /// `usesCloud`: ask `discovery.meethue.com` if mDNS finds nothing. Signify allows one
    /// request per 15 minutes, so background searches (e.g. after an IP change) pass false.
    public static func discover(using client: HueClient, timeout: Duration = .seconds(5), usesCloud: Bool = true) async -> [DiscoveredBridge] {
        await search(using: client, timeout: timeout, usesCloud: usesCloud).bridges
    }

    /// Like `discover`, but also reports whether local network access was denied. Without
    /// that permission the cloud fallback is pointless (its address can't be reached).
    public static func search(using client: HueClient, timeout: Duration = .seconds(5), usesCloud: Bool = true) async -> Result {
        let mdns = await mdnsSearch(timeout: timeout)
        var candidates = mdns.hosts
        if candidates.isEmpty && !mdns.isDenied && usesCloud {
            candidates = await cloudCandidates()
        }
        let bridges = await verify(candidates, using: client)
        return Result(bridges: bridges, isLocalNetworkDenied: bridges.isEmpty && mdns.isDenied)
    }

    /// Verifies candidate addresses against `/api/0/config` over pinned TLS.
    public static func verify(_ candidates: [String], using client: HueClient) async -> [DiscoveredBridge] {
        await withTaskGroup(of: DiscoveredBridge?.self) { group in
            for host in Set(candidates) {
                group.addTask { try? await bridge(at: host, using: client) }
            }
            var bridges: [String: DiscoveredBridge] = [:]
            for await bridge in group {
                if let bridge { bridges[bridge.id] = bridge }
            }
            return bridges.values.sorted { $0.name < $1.name }
        }
    }

    /// Verifies a manually entered address.
    public static func bridge(at host: String, using client: HueClient) async throws -> DiscoveredBridge {
        let config = try await client.config(host: host)
        guard config.supportsCLIPv2 else {
            throw HueError.bridge(String(localized: "Die Firmware der Bridge ist zu alt. Bitte in der Hue-App aktualisieren.", bundle: .hueKit))
        }
        // The certificate must belong to the bridge that answered, and from now on only to it.
        guard client.trust.observedBridgeID(for: host) == config.bridgeID.lowercased() else {
            throw HueError.bridge(String(localized: "Das Zertifikat unter \(host) passt nicht zur Bridge-ID.", bundle: .hueKit))
        }
        client.trust.pin(host: host, bridgeID: config.bridgeID)
        return DiscoveredBridge(
            id: config.bridgeID.lowercased(),
            host: host,
            name: "\(config.name) · \(config.bridgeID.suffix(6))",
            modelID: config.modelID
        )
    }

    // MARK: mDNS

    static func mdnsCandidates(timeout: Duration) async -> [String] {
        await mdnsSearch(timeout: timeout).hosts
    }

    static func mdnsSearch(timeout: Duration) async -> (hosts: [String], isDenied: Bool) {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: "local."),
            using: .tcp
        )
        let endpoints = Mutex<[NWEndpoint]>([])
        let denied = Mutex(false)
        browser.browseResultsChangedHandler = { results, _ in
            endpoints.withLock { $0 = results.map(\.endpoint) }
        }
        browser.stateUpdateHandler = { state in
            denied.withLock { $0 = BridgeBrowser.isPolicyDenied(state) }
        }
        browser.start(queue: .global(qos: .userInitiated))

        // Stop early once something showed up and had a moment to settle.
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        var firstSeen: ContinuousClock.Instant?
        while clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            if endpoints.withLock({ !$0.isEmpty }) {
                firstSeen = firstSeen ?? clock.now
                if clock.now - firstSeen! > .seconds(1) { break }
            }
        }
        browser.cancel()

        let found = endpoints.withLock { $0 }
        let hosts = await resolve(found)
        return (hosts, hosts.isEmpty && denied.withLock { $0 })
    }

    static func resolve(_ endpoints: [NWEndpoint]) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for endpoint in endpoints {
                group.addTask { await resolveIPv4(endpoint) }
            }
            var hosts: [String] = []
            for await host in group {
                if let host { hosts.append(host) }
            }
            return hosts
        }
    }

    /// Resolves a Bonjour service to an IPv4 address by briefly connecting to it.
    static func resolveIPv4(_ endpoint: NWEndpoint) async -> String? {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        let finished = Mutex(false)

        return await withCheckedContinuation { continuation in
            @Sendable func finish(_ host: String?) {
                let alreadyFinished = finished.withLock { done in
                    defer { done = true }
                    return done
                }
                guard !alreadyFinished else { return }
                connection.cancel()
                continuation.resume(returning: host)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint,
                       case let .ipv4(address) = host {
                        finish("\(address)")
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + 3) { finish(nil) }
        }
    }

    // MARK: Cloud fallback

    private struct CloudEntry: Decodable {
        var internalipaddress: String
    }

    /// `discovery.meethue.com` allows one request per 15 minutes, so only call it when mDNS found nothing.
    static func cloudCandidates() async -> [String] {
        guard let url = URL(string: "https://discovery.meethue.com/"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let entries = try? JSONDecoder().decode([CloudEntry].self, from: data)
        else { return [] }
        return entries.map(\.internalipaddress)
    }
}
