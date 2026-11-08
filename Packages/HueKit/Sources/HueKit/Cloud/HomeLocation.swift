import CryptoKit
import Darwin
import Foundation
import SystemConfiguration

/// Is the Mac at home? Decided only from the local network, without location access:
///
/// - **Home** when the paired bridge answers directly on a Wi-Fi/Ethernet subnet with
///   its own certificate, or when the router is one Hoku has seen at home before
///   (the bridge may just be unplugged or still waking up).
/// - **Away** only when there is a router and it is not a home router.
/// - **Unknown** otherwise (no network yet, or Hoku has never seen the home router).
///   Unknown never triggers anything.
///
/// A VPN never counts as home: tunnel interfaces are ignored for both checks, so a
/// company VPN that is on at home changes nothing, and one that is on at work does
/// not make work look like home.
public enum HomeLocation: Equatable, Sendable {
    case home
    case away
    case unknown

    /// What the network looks like right now.
    public struct Observation: Equatable, Sendable {
        /// The bridge answered with the pinned certificate.
        public var bridgeVerified: Bool
        /// The bridge's address lies in the subnet of a non-tunnel interface.
        public var bridgeOnLocalSubnet: Bool
        /// Fingerprints of the current routers on non-tunnel interfaces.
        public var routers: Set<String>

        public init(bridgeVerified: Bool, bridgeOnLocalSubnet: Bool, routers: Set<String>) {
            self.bridgeVerified = bridgeVerified
            self.bridgeOnLocalSubnet = bridgeOnLocalSubnet
            self.routers = routers
        }
    }

    /// The decision, plus the routers to remember as home (learned while provably home).
    public static func decide(_ observation: Observation, knownHomeRouters: Set<String>) -> (HomeLocation, learned: Set<String>) {
        if observation.bridgeVerified, observation.bridgeOnLocalSubnet {
            return (.home, knownHomeRouters.union(observation.routers))
        }
        if observation.routers.isEmpty || knownHomeRouters.isEmpty {
            return (.unknown, knownHomeRouters)
        }
        if !observation.routers.isDisjoint(with: knownHomeRouters) {
            return (.home, knownHomeRouters)
        }
        return (.away, knownHomeRouters)
    }

    // MARK: Interfaces

    /// VPNs and other tunnels: utun (WireGuard, IKEv2, most VPN apps), ipsec, ppp, …
    static let tunnelPrefixes = ["utun", "ipsec", "ppp", "tun", "tap", "gif", "stf"]

    public static func isTunnel(_ interface: String) -> Bool {
        tunnelPrefixes.contains { interface.hasPrefix($0) }
    }

    public struct InterfaceAddress: Equatable, Sendable {
        public var name: String
        public var address: UInt32
        public var netmask: UInt32

        public init(name: String, address: String, netmask: String) {
            self.name = name
            self.address = HomeLocation.ipv4(address) ?? 0
            self.netmask = HomeLocation.ipv4(netmask) ?? 0
        }

        init(name: String, address: UInt32, netmask: UInt32) {
            self.name = name
            self.address = address
            self.netmask = netmask
        }
    }

    /// True if `host` is an IPv4 address inside the subnet of a non-tunnel interface.
    public static func isOnLocalSubnet(_ host: String, interfaces: [InterfaceAddress]) -> Bool {
        guard let target = ipv4(host) else { return false }
        return interfaces.contains { interface in
            !isTunnel(interface.name)
                && interface.netmask != 0
                && interface.address & interface.netmask == target & interface.netmask
        }
    }

    static func ipv4(_ string: String) -> UInt32? {
        var address = in_addr()
        guard inet_pton(AF_INET, string, &address) == 1 else { return nil }
        return UInt32(bigEndian: address.s_addr)
    }

    /// The Mac's current IPv4 interfaces.
    public static func currentInterfaces() -> [InterfaceAddress] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var result: [InterfaceAddress] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  let netmask = entry.ifa_netmask,
                  entry.ifa_flags & UInt32(IFF_UP) != 0
            else { continue }
            func value(_ socket: UnsafeMutablePointer<sockaddr>) -> UInt32 {
                socket.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            }
            result.append(InterfaceAddress(name: String(cString: entry.ifa_name), address: value(address), netmask: value(netmask)))
        }
        return result
    }

    // MARK: Routers

    /// IPv4 routers of the active network services, without tunnels — also while a
    /// VPN is the primary service.
    public static func currentRouterAddresses() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "Hoku" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv4" as CFString) as? [String]
        else { return [] }
        return keys.compactMap { key in
            guard let info = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let router = info["Router"] as? String,
                  let interface = info["InterfaceName"] as? String,
                  !isTunnel(interface)
            else { return nil }
            return router
        }
    }

    /// The router's hardware address from the ARP table, e.g. "0:0:5e:0:53:af".
    /// Read with /usr/sbin/arp, which needs no privileges.
    public static func hardwareAddress(of ip: String) -> String? {
        guard ipv4(ip) != nil else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseARP(String(decoding: data, as: UTF8.self))
    }

    /// "? (198.51.100.1) at 0:0:5e:0:53:af on en0 ifscope [ethernet]" → "00:00:5e:00:53:af".
    static func parseARP(_ output: String) -> String? {
        guard let range = output.range(of: " at ") else { return nil }
        let rest = output[range.upperBound...]
        guard let token = rest.split(separator: " ").first else { return nil }
        let parts = token.split(separator: ":")
        guard parts.count == 6, parts.allSatisfy({ (1...2).contains($0.count) && $0.allSatisfy(\.isHexDigit) }) else {
            return nil // "(incomplete)" while the router has not answered yet
        }
        return parts.map { $0.count == 1 ? "0\($0)" : String($0) }.joined(separator: ":").lowercased()
    }

    /// Hoku stores only a hash of each home router's hardware address.
    public static func fingerprint(_ hardwareAddress: String) -> String {
        let digest = SHA256.hash(data: Data("hoku-router:\(hardwareAddress.lowercased())".utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// Fingerprints of the routers the Mac uses right now.
    public static func currentRouters() -> Set<String> {
        Set(currentRouterAddresses().compactMap(hardwareAddress(of:)).map(fingerprint))
    }
}

extension HomeLocation {
    /// Looks at the network now. Asks the bridge for its public config with the
    /// certificate pinned to its ID, so a different device at the same address
    /// (another network that reuses 192.168.x.x) never passes.
    public static func observe(bridge credentials: BridgeCredentials, using client: HueClient) async -> Observation {
        let onSubnet = isOnLocalSubnet(credentials.host, interfaces: currentInterfaces())
        var verified = false
        if onSubnet {
            client.trust.pin(host: credentials.host, bridgeID: credentials.bridgeID)
            if let config = try? await client.config(host: credentials.host) {
                verified = config.bridgeID.lowercased() == credentials.bridgeID.lowercased()
            }
        }
        let routers = await Task.detached(priority: .utility) { currentRouters() }.value
        return Observation(bridgeVerified: verified, bridgeOnLocalSubnet: onSubnet, routers: routers)
    }
}
