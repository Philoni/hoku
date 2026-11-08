import Foundation
import Testing
@testable import HueKit

// MARK: - Sign-in

@Suite struct CloudAuthorizationTests {
    let authorization = CloudAuthorization(clientID: "client-1", deviceName: "Mac", state: "state-1", codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")

    @Test func challengeIsS256OfVerifier() {
        // RFC 7636, Appendix B.
        #expect(authorization.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func authorizeURLCarriesPKCEAndState() throws {
        let items = try #require(URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(authorization.url.host() == "api.meethue.com")
        #expect(query["client_id"] == "client-1")
        #expect(query["response_type"] == "code")
        #expect(query["state"] == "state-1")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == authorization.codeChallenge)
        // The secret never goes to the browser.
        #expect(!authorization.url.absoluteString.contains("secret"))
    }

    @Test func callbackNeedsMatchingState() throws {
        #expect(try authorization.code(from: URL(string: "hoku://oauth?code=abc&state=state-1")!) == "abc")
        #expect(throws: CloudAuthorization.CallbackError.wrongState) {
            try authorization.code(from: URL(string: "hoku://oauth?code=abc&state=forged")!)
        }
        #expect(throws: CloudAuthorization.CallbackError.denied("access_denied")) {
            try authorization.code(from: URL(string: "hoku://oauth?error=access_denied&state=state-1")!)
        }
        #expect(throws: CloudAuthorization.CallbackError.missingCode) {
            try authorization.code(from: URL(string: "hoku://oauth?state=state-1")!)
        }
    }

    @Test func randomValuesAreLongAndDistinct() {
        let a = CloudAuthorization(clientID: "c", deviceName: "Mac")
        let b = CloudAuthorization(clientID: "c", deviceName: "Mac")
        #expect(a.state != b.state)
        #expect(a.codeVerifier.count == 43)
        #expect(!a.codeVerifier.contains("="))
    }
}

// MARK: - Cloud client

/// Answers requests from a script and remembers what was sent.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Handler = (URLRequest) -> (Int, String)
    private let lock = NSLock()
    private var handler: Handler
    private(set) var requests: [URLRequest] = []

    init(_ handler: @escaping Handler) { self.handler = handler }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body) = lock.withLock {
            requests.append(request)
            return handler(request)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    var paths: [String] { lock.withLock { requests.map { "\($0.httpMethod ?? "GET") \($0.url!.path())" } } }

    static func form(_ request: URLRequest) -> [String: String] {
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            return (parts[0], parts.count > 1 ? parts[1] : "")
        })
    }
}

/// Holds the token request until the test releases it, to interleave other calls.
final class GatedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<(Int, String), Never>?

    var waiting: Int { lock.withLock { continuation == nil ? 0 : 1 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (status, body): (Int, String) = request.url!.path() == "/v2/oauth2/token"
            ? await withCheckedContinuation { continuation in lock.withLock { self.continuation = continuation } }
            : (200, #"{"errors":[],"data":[]}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func release(status: Int, body: String) {
        let pending = lock.withLock { () -> CheckedContinuation<(Int, String), Never>? in
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: (status, body))
    }
}

@Suite struct HueCloudTests {
    static let app = CloudAppCredentials(clientID: "cid", clientSecret: "secret")
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func tokens(_ n: Int, expiresIn: Int = 604_799) -> String {
        #"{"access_token":"access-\#(n)","refresh_token":"refresh-\#(n)","expires_in":\#(expiresIn),"token_type":"bearer"}"#
    }

    func cloud(_ store: CloudAccountStore, _ transport: FakeTransport) -> HueCloud {
        HueCloud(store: store, transport: transport, now: { Self.now })
    }

    @Test func signInExchangesCodeThenCreatesRemoteKey() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        let transport = FakeTransport { request in
            switch request.url!.path() {
            case "/v2/oauth2/token": (200, Self.tokens(1))
            case "/route/api/0/config": (200, #"[{"success":{"/config/linkbutton":true}}]"#)
            case "/route/api": (200, #"[{"success":{"username":"remote-key"}}]"#)
            case "/route/clip/v2/resource/bridge": (200, #"{"errors":[],"data":[{"id":"b","type":"bridge","bridge_id":"ABC123"}]}"#)
            default: (404, "")
            }
        }
        let cloud = cloud(store, transport)
        try await cloud.saveApp(Self.app)
        let authorization = CloudAuthorization(clientID: "cid", deviceName: "Mac")
        let account = try await cloud.completeSignIn(code: "the-code", authorization: authorization, deviceType: "Hoku#Mac")

        #expect(account.isSignedIn)
        #expect(account.applicationKey == "remote-key")
        #expect(account.bridgeID == "abc123")
        #expect(account.tokens?.expiresAt == Self.now.addingTimeInterval(604_799))
        #expect(try store.load() == account)

        let exchange = transport.requests[0]
        #expect(exchange.value(forHTTPHeaderField: "Authorization") == "Basic " + Data("cid:secret".utf8).base64EncodedString())
        let form = FakeTransport.form(exchange)
        #expect(form["grant_type"] == "authorization_code")
        #expect(form["code"] == "the-code")
        #expect(form["code_verifier"] == authorization.codeVerifier)
        #expect(form["client_secret"] == nil)

        #expect(transport.paths == [
            "POST /v2/oauth2/token", "PUT /route/api/0/config", "POST /route/api", "GET /route/clip/v2/resource/bridge",
        ])
        #expect(transport.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer access-1")
        #expect(transport.requests[3].value(forHTTPHeaderField: "hue-application-key") == "remote-key")
    }

    @Test func expiredTokenIsRefreshedAndRotationSavedBeforeUse() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(CloudAccount(
            app: Self.app,
            tokens: CloudTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: Self.now.addingTimeInterval(60)),
            applicationKey: "remote-key"
        ))
        let transport = FakeTransport { request in
            switch request.url!.path() {
            case "/v2/oauth2/token":
                // The account must not be used with the old token anymore.
                (200, Self.tokens(2))
            case "/route/clip/v2/resource":
                request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                    ? (200, #"{"errors":[],"data":[]}"#) : (401, "")
            default: (404, "")
            }
        }
        _ = try await cloud(store, transport).resources()
        #expect(transport.paths == ["POST /v2/oauth2/token", "GET /route/clip/v2/resource"])
        #expect(FakeTransport.form(transport.requests[0])["refresh_token"] == "refresh-1")
        #expect(try store.load()?.tokens?.refreshToken == "refresh-2")
    }

    @Test func unauthorizedTriggersOneRefreshAndRetry() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(CloudAccount(
            app: Self.app,
            tokens: CloudTokens(accessToken: "revoked", refreshToken: "refresh-1", expiresAt: Self.now.addingTimeInterval(86400)),
            applicationKey: "remote-key"
        ))
        let transport = FakeTransport { request in
            switch request.url!.path() {
            case "/v2/oauth2/token": (200, Self.tokens(2))
            default: request.value(forHTTPHeaderField: "Authorization") == "Bearer access-2"
                ? (200, #"{"errors":[],"data":[]}"#) : (401, "")
            }
        }
        try await cloud(store, transport).setOn(false, groupedLight: "home")
        #expect(transport.paths == [
            "PUT /route/clip/v2/resource/grouped_light/home", "POST /v2/oauth2/token", "PUT /route/clip/v2/resource/grouped_light/home",
        ])
        let body = try JSONDecoder().decode(JSONValue.self, from: try #require(transport.requests[2].httpBody))
        #expect(body == ["on": ["on": false]])
    }

    @Test func rejectedRefreshMeansSignInAgain() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(CloudAccount(
            app: Self.app,
            tokens: CloudTokens(accessToken: "a", refreshToken: "gone", expiresAt: Self.now),
            applicationKey: "remote-key"
        ))
        let transport = FakeTransport { _ in (400, #"{"error":"invalid_grant"}"#) }
        await #expect(throws: CloudError.signInRequired) {
            try await cloud(store, transport).resources()
        }
        let account = try #require(try store.load())
        #expect(account.tokens == nil)
        #expect(account.app == Self.app) // The app credentials stay for the next sign-in.
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(CloudAccount(
            app: Self.app,
            tokens: CloudTokens(accessToken: "a", refreshToken: "refresh-1", expiresAt: Self.now),
            applicationKey: "remote-key"
        ))
        let transport = FakeTransport { request in
            request.url!.path() == "/v2/oauth2/token" ? (200, Self.tokens(2)) : (200, #"{"errors":[],"data":[]}"#)
        }
        let cloud = cloud(store, transport)
        async let first = cloud.resources()
        async let second = cloud.resources()
        _ = try await (first, second)
        #expect(transport.paths.filter { $0.hasSuffix("/token") }.count == 1)
    }

    @Test func changingClientIDDropsOldTokens() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(CloudAccount(
            app: Self.app,
            tokens: CloudTokens(accessToken: "a", refreshToken: "r", expiresAt: Self.now),
            applicationKey: "k", bridgeID: "b"
        ))
        let cloud = cloud(store, FakeTransport { _ in (500, "") })
        try await cloud.saveApp(CloudAppCredentials(clientID: " other\n", clientSecret: "s2"))
        #expect(try store.load() == CloudAccount(app: CloudAppCredentials(clientID: "other", clientSecret: "s2")))
    }

    @Test func signOutKeepsOrDropsTheApp() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(CloudAccount(app: Self.app, tokens: CloudTokens(accessToken: "a", refreshToken: "r", expiresAt: Self.now), applicationKey: "k"))
        let cloud = cloud(store, FakeTransport { _ in (500, "") })
        try await cloud.signOut(keepingApp: true)
        #expect(try store.load() == CloudAccount(app: Self.app))
        try await cloud.signOut(keepingApp: false)
        #expect(try store.load() == nil)
    }


    // MARK: Failure paths (review 08.11.2026)

    static func expiredAccount() -> CloudAccount {
        CloudAccount(
            app: app,
            tokens: CloudTokens(accessToken: "access-1", refreshToken: "refresh-1", expiresAt: now.addingTimeInterval(-10)),
            applicationKey: "remote-key",
            bridgeID: "abc123"
        )
    }

    @Test func temporaryRefreshFailureKeepsTheTokens() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(Self.expiredAccount())
        var status = 500
        let transport = FakeTransport { _ in (status, "") }
        let cloud = cloud(store, transport)
        await #expect(throws: CloudError.self) { _ = try await cloud.resources() }
        #expect(try store.load()?.tokens?.refreshToken == "refresh-1")
        status = 429
        await #expect(throws: CloudError.rateLimited) { _ = try await cloud.resources() }
        #expect(try store.load()?.tokens?.refreshToken == "refresh-1") // Wi-Fi trouble never signs out.
    }

    @Test func signOutDuringRefreshStaysSignedOut() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        try store.save(Self.expiredAccount())
        let transport = GatedTransport()
        let cloud = HueCloud(store: store, transport: transport, now: { Self.now })
        let check = Task { try await cloud.resources() }
        while transport.waiting == 0 { try await Task.sleep(for: .milliseconds(5)) }
        try await cloud.signOut(keepingApp: false)
        transport.release(status: 200, body: Self.tokens(2))
        await #expect(throws: (any Error).self) { _ = try await check.value }
        #expect(try store.load() == nil)
    }

    @Test func signInWithoutBridgeIsNotUsable() async throws {
        let store = CloudAccountStore(secrets: MemorySecretStore())
        let transport = FakeTransport { request in
            switch request.url!.path() {
            case "/v2/oauth2/token": (200, Self.tokens(1))
            case "/route/api/0/config": (200, #"[{"success":{"/config/linkbutton":true}}]"#)
            case "/route/api": (200, #"[{"success":{"username":"remote-key"}}]"#)
            case "/route/clip/v2/resource/bridge": (200, #"{"errors":[],"data":[]}"#)
            default: (404, "")
            }
        }
        let cloud = cloud(store, transport)
        try await cloud.saveApp(Self.app)
        await #expect(throws: (any Error).self) {
            _ = try await cloud.completeSignIn(code: "c", authorization: CloudAuthorization(clientID: "cid", deviceName: "Mac"), deviceType: "Hoku#Mac")
        }
        // Without the bridge Hoku can't check it is the paired one: sign in again.
        #expect(try store.load()?.isSignedIn == false)
    }

    @Test func damagedKeychainItemIsAnError() throws {
        let secrets = MemorySecretStore()
        try secrets.save(Data("not json".utf8))
        #expect(throws: CloudError.self) { _ = try CloudAccountStore(secrets: secrets).load() }
    }

    @Test func expiresInAsString() throws {
        let tokens = try HueCloud.decodeTokens(Data(#"{"access_token":"a","refresh_token":"r","expires_in":"604799"}"#.utf8), now: Self.now)
        #expect(tokens.expiresAt == Self.now.addingTimeInterval(604_799))
    }

    @Test func formBodyEncodesReservedCharacters() {
        let body = String(decoding: HueCloud.formBody(["code": "a+b/c=d&e"]), as: UTF8.self)
        #expect(body == "code=a%2Bb%2Fc%3Dd%26e")
    }
}

// MARK: - Home or away

@Suite struct HomeLocationTests {
    typealias Observation = HomeLocation.Observation

    @Test func bridgeOnWiFiMeansHomeAndLearnsRouter() {
        let (location, learned) = HomeLocation.decide(
            Observation(bridgeVerified: true, bridgeOnLocalSubnet: true, routers: ["home-router"]),
            knownHomeRouters: []
        )
        #expect(location == .home)
        #expect(learned == ["home-router"])
    }

    @Test func knownRouterWithoutBridgeIsStillHome() {
        // Just woke up, or the bridge is unplugged: no false alarm at home.
        let (location, _) = HomeLocation.decide(
            Observation(bridgeVerified: false, bridgeOnLocalSubnet: true, routers: ["home-router"]),
            knownHomeRouters: ["home-router"]
        )
        #expect(location == .home)
    }

    @Test func otherRouterIsAway() {
        let (location, learned) = HomeLocation.decide(
            Observation(bridgeVerified: false, bridgeOnLocalSubnet: false, routers: ["phone-hotspot"]),
            knownHomeRouters: ["home-router"]
        )
        #expect(location == .away)
        #expect(learned == ["home-router"]) // Never learns away routers.
    }

    @Test func noRouterOrNothingLearnedIsUnknown() {
        #expect(HomeLocation.decide(Observation(bridgeVerified: false, bridgeOnLocalSubnet: false, routers: []), knownHomeRouters: ["home-router"]).0 == .unknown)
        #expect(HomeLocation.decide(Observation(bridgeVerified: false, bridgeOnLocalSubnet: false, routers: ["x"]), knownHomeRouters: []).0 == .unknown)
    }

    @Test func bridgeOnlyThroughTunnelIsNotHome() {
        // A bridge answering via VPN does not prove the Mac is home.
        let (location, learned) = HomeLocation.decide(
            Observation(bridgeVerified: true, bridgeOnLocalSubnet: false, routers: ["office"]),
            knownHomeRouters: ["home-router"]
        )
        #expect(location == .away)
        #expect(learned == ["home-router"])
    }

    @Test func subnetIgnoresTunnels() {
        let interfaces = [
            HomeLocation.InterfaceAddress(name: "utun4", address: "100.64.0.2", netmask: "255.192.0.0"),
            HomeLocation.InterfaceAddress(name: "en0", address: "198.51.100.20", netmask: "255.255.255.0"),
            HomeLocation.InterfaceAddress(name: "lo0", address: "127.0.0.1", netmask: "255.0.0.0"),
        ]
        #expect(HomeLocation.isOnLocalSubnet("198.51.100.5", interfaces: interfaces))
        #expect(!HomeLocation.isOnLocalSubnet("203.0.113.5", interfaces: interfaces))
        #expect(!HomeLocation.isOnLocalSubnet("100.64.1.3", interfaces: interfaces)) // only via the VPN
        #expect(!HomeLocation.isOnLocalSubnet("bridge.local", interfaces: interfaces))
        #expect(HomeLocation.isTunnel("utun0") && HomeLocation.isTunnel("ipsec0") && !HomeLocation.isTunnel("en0"))
    }

    @Test func parsesARPOutput() {
        #expect(HomeLocation.parseARP("? (198.51.100.1) at 0:0:5e:0:53:af on en0 ifscope [ethernet]\n") == "00:00:5e:00:53:af")
        #expect(HomeLocation.parseARP("? (198.51.100.1) at (incomplete) on en0 ifscope [ethernet]\n") == nil)
        #expect(HomeLocation.parseARP("198.51.100.1 (198.51.100.1) -- no entry\n") == nil)
    }

    @Test func fingerprintHidesTheAddress() {
        let fingerprint = HomeLocation.fingerprint("00:00:5E:00:53:AF")
        #expect(fingerprint == HomeLocation.fingerprint("00:00:5e:00:53:af"))
        #expect(fingerprint.count == 24)
        #expect(!fingerprint.contains("a4"))
    }

    @Test func readsThisMacsNetwork() {
        // Smoke test against the real system: must not crash, loopback is never a router.
        #expect(HomeLocation.currentInterfaces().contains { $0.name == "lo0" })
        #expect(!HomeLocation.currentRouterAddresses().contains("127.0.0.1"))
    }
}

// MARK: - Lights left on

@MainActor
@Suite struct LeftOnReminderTests {
    static func resources(lit: Set<String>) throws -> [JSONValue] {
        try HueStoreTests.fixture().map { resource in
            guard resource["type"] == "light", let id = resource["id"]?.stringValue else { return resource }
            return resource.merging(["on": ["on": .bool(lit.contains(id))]])
        }
    }

    static let floorLamp = "483bcb38-7a0b-4ba0-88e5-56ff282bdfe6"

    @Test func reportsRoomsWithLightsOn() throws {
        let report = LeftOnReport.from(resources: try Self.resources(lit: [Self.floorLamp]))
        #expect(report.rooms == ["Living Room"])
        #expect(report.lightIDs == [Self.floorLamp])
        #expect(report.homeGroupedLightID == "2e715d41-bc06-4c6e-ae03-259148b4f3cf")
        #expect(report.message == "Living Room · 1 Lampe an")
        #expect(LeftOnReport.from(resources: try Self.resources(lit: [])).isEmpty)
    }

    @Test func messages() {
        var report = LeftOnReport(rooms: ["Küche", "Bad"], lightIDs: ["a", "b", "c"])
        #expect(report.message == "Küche und Bad · 3 Lampen an")
        report.rooms = ["Küche", "Bad", "Flur"]
        #expect(report.message == "Küche, Bad und Flur · 3 Lampen an")
        report.rooms = ["A", "B", "C", "D", "E"]
        #expect(report.message == "A, B und 3 weitere Räume · 3 Lampen an")
        report.rooms = []
        #expect(report.message == "3 Lampen an")
    }

    @Test func failedReminderIsTriedAgain() {
        var policy = LeftOnPolicy()
        let lit = LeftOnReport(rooms: ["Flur"], lightIDs: ["a"])
        let start = Date(timeIntervalSince1970: 0)
        let first = policy.record(lit, at: start)
        #expect(first)
        policy.reminderFailed()
        let again = policy.record(lit, at: start.addingTimeInterval(LeftOnPolicy.recheckInterval))
        #expect(again)
    }

    @Test func remindsOncePerTripUnlessSomethingChanges() {
        let start = Date(timeIntervalSince1970: 0)
        var policy = LeftOnPolicy()
        let one = LeftOnReport(rooms: ["Zimmer"], lightIDs: ["a"])
        let two = LeftOnReport(rooms: ["Zimmer"], lightIDs: ["a", "b"])

        #expect(policy.shouldCheck(.arrival, at: start))
        let r1 = policy.record(one, at: start)
        #expect(r1)
        #expect(!policy.shouldCheck(.arrival, at: start.addingTimeInterval(30)))
        #expect(!policy.shouldCheck(.timer, at: start.addingTimeInterval(600)))
        #expect(policy.shouldCheck(.timer, at: start.addingTimeInterval(1800)))
        let r2 = policy.record(one, at: start.addingTimeInterval(1800))
        #expect(!r2) // Same lights: quiet.
        let r3 = policy.record(two, at: start.addingTimeInterval(3600))
        #expect(r3) // More lights: tell again.

        let r4 = policy.record(LeftOnReport(rooms: [], lightIDs: []), at: start.addingTimeInterval(5400))
        #expect(!r4)
        let r5 = policy.record(one, at: start.addingTimeInterval(7200))
        #expect(r5) // On again after all off.

        policy.cameHome()
        #expect(policy.shouldCheck(.timer, at: start.addingTimeInterval(7201)))
        let r6 = policy.record(one, at: start.addingTimeInterval(7201))
        #expect(r6) // New trip.
    }
}

// MARK: - Keychain

@Suite(.serialized) struct KeychainSecretStoreTests {
    @Test func roundTripInTheLoginKeychain() throws {
        let store = KeychainSecretStore(service: "io.github.philoni.hoku.tests", account: UUID().uuidString)
        defer { try? store.delete() }
        #expect(try store.load() == nil)
        try store.save(Data("one".utf8))
        try store.save(Data("two".utf8))
        #expect(try store.load() == Data("two".utf8))
        try store.delete()
        #expect(try store.load() == nil)
        try store.delete() // Deleting twice is fine.
    }
}
