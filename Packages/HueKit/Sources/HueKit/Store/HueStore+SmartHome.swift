import Foundation

/// Whether the bridge is already connected to a smart-home ecosystem. Decides which
/// Siri commands Hoku offers: with Apple Home, Siri switches rooms already, so Hoku only
/// adds what Home can't do (scenes, effects, timers) and never competes for "Zimmer an".
public struct SmartHomeLinks: Equatable, Sendable {
    public enum Ecosystem: String, Sendable, CaseIterable {
        case apple, google, amazon, other
    }

    /// Paired with Apple Home through HomeKit (Bridge v2).
    public var isHomeKitPaired: Bool
    /// Ecosystems connected through Matter (e.g. Bridge Pro).
    public var matter: Set<Ecosystem>

    public var hasAppleHome: Bool { isHomeKitPaired || matter.contains(.apple) }

    public static let none = SmartHomeLinks(isHomeKitPaired: false, matter: [])

    /// Matter vendor IDs from the CSA list.
    static func ecosystem(vendorID: Int) -> Ecosystem {
        switch vendorID {
        case 4937: .apple       // 0x1349
        case 24582: .google     // 0x6006
        case 4631: .amazon      // 0x1217
        default: .other
        }
    }
}

extension HueStore {
    /// Read from the bridge's `homekit` and `matter_fabric` resources (kept raw).
    public var smartHomeLinks: SmartHomeLinks {
        var links = SmartHomeLinks.none
        for value in raw.values {
            switch value["type"]?.stringValue {
            case "homekit":
                if value["status"]?.stringValue == "paired" { links.isHomeKitPaired = true }
            case "matter_fabric":
                guard value["status"]?.stringValue == "paired" else { continue }
                if case let .number(vendor)? = value["fabric_data"]?["vendor_id"] {
                    links.matter.insert(SmartHomeLinks.ecosystem(vendorID: Int(vendor)))
                } else {
                    links.matter.insert(.other)
                }
            default:
                continue
            }
        }
        return links
    }
}
