import Foundation
import Testing
@testable import HueKit

/// Read-only checks against the paired bridge (never switches anything).
/// Opt in: `HOKU_LIVE_BRIDGE=1 swift test --filter LiveBridgeTests`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HOKU_LIVE_BRIDGE"] != nil))
@MainActor struct LiveBridgeTests {
    @Test func directDecodingMatchesFoundationOnRealData() async throws {
        let credentials = try #require(CredentialStore.load(), "No paired bridge on this Mac")
        let resources = try await HueClient().allResources(credentials)
        let decoder = JSONValueDecoderTests()
        decoder.expectSame(Light.self, in: resources)
        decoder.expectSame(GroupedLight.self, in: resources)
        decoder.expectSame(HueGroup.self, in: resources)
        decoder.expectSame(Device.self, in: resources)
        decoder.expectSame(HueScene.self, in: resources)
        decoder.expectSame(SmartScene.self, in: resources)
        decoder.expectSame(BridgeHome.self, in: resources)
        decoder.expectSame(BehaviorScript.self, in: resources)
        decoder.expectSame(BehaviorInstance.self, in: resources)
        decoder.expectSame(DevicePower.self, in: resources)
        decoder.expectSame(ZigbeeConnectivity.self, in: resources)
        decoder.expectSame(DeviceSoftwareUpdate.self, in: resources)

        let store = HueStore()
        let clock = ContinuousClock()
        let elapsed = clock.measure { store.load(resources) }
        print("⏱ live load of \(resources.count) resources: \(elapsed)")
        #expect(!store.lights.isEmpty)
    }

    /// Wherever the Mac is: at home the bridge answers on Wi-Fi with its own
    /// certificate; elsewhere it must not look like home. Prints only booleans and
    /// counts, never addresses.
    @Test func homeOrAwayFromTheRealNetwork() async throws {
        let credentials = try #require(CredentialStore.load(), "No paired bridge on this Mac")
        let observation = await HomeLocation.observe(bridge: credentials, using: HueClient())
        print("🏠 bridge verified: \(observation.bridgeVerified), on local subnet: \(observation.bridgeOnLocalSubnet), routers: \(observation.routers.count)")
        let (location, learned) = HomeLocation.decide(observation, knownHomeRouters: [])
        if observation.bridgeVerified {
            #expect(location == .home)
            #expect(!learned.isEmpty)
            // The same network seen without the bridge (as right after waking) stays home.
            let later = HomeLocation.Observation(bridgeVerified: false, bridgeOnLocalSubnet: false, routers: observation.routers)
            #expect(HomeLocation.decide(later, knownHomeRouters: learned).0 == .home)
        } else {
            #expect(location == .unknown) // Nothing learned yet: never a false "away".
            #expect(HomeLocation.decide(observation, knownHomeRouters: ["some-other-router"]).0 == (observation.routers.isEmpty ? .unknown : .away))
        }
    }

    /// The manual path: verify the address, then connect with a key and without the
    /// link button. A wrong key must be refused. Prints only counts.
    @Test func connectsWithAnExistingKeyAndRefusesAWrongOne() async throws {
        let credentials = try #require(CredentialStore.load(), "No paired bridge on this Mac")
        let client = HueClient()
        let bridge = try await BridgeDiscovery.bridge(at: credentials.host, using: client)
        #expect(bridge.id == credentials.bridgeID.lowercased())

        let key = try #require(ApplicationKey.normalized(credentials.applicationKey))
        let connected = try await client.connect(to: bridge, applicationKey: key)
        #expect(connected.bridgeID == bridge.id)

        await #expect(throws: HueError.self) {
            _ = try await client.connect(to: bridge, applicationKey: String(repeating: "x", count: 40))
        }
    }

    @Test func readsEntertainmentAreas() async throws {
        let credentials = try #require(CredentialStore.load(), "No paired bridge on this Mac")
        let store = HueStore()
        store.load(try await HueClient().allResources(credentials))
        print("🎬 entertainment areas: \(store.entertainmentAreas.count), streaming: \(store.streamingAreas.count)")
        #expect(store.entertainmentAreas.values.allSatisfy { $0.status != nil })
    }
}
