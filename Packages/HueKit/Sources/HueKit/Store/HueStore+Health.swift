import Foundation

/// Something about a device that deserves attention.
public struct DeviceIssue: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case battery(level: Int?, critical: Bool)
        case unreachable
        case update
    }

    public var deviceID: String
    public var kind: Kind
    public var id: String { "\(deviceID)-\(kind)" }
}

/// A device's health at a glance.
public struct DeviceHealth: Sendable {
    public var batteryLevel: Int?
    public var batteryState: String?
    public var isConnected: Bool
    public var hasUpdate: Bool
}

extension HueStore {
    /// Devices worth listing (everything but the bridge itself), lights first.
    public var sortedDevices: [Device] {
        devices.values
            .filter { $0.productData?.productArchetype != "bridge_v2" && $0.metadata?.archetype?.hasPrefix("bridge") != true }
            .sorted {
                ($0.lightIDs.isEmpty ? 1 : 0, $0.metadata?.name ?? "") < ($1.lightIDs.isEmpty ? 1 : 0, $1.metadata?.name ?? "")
            }
    }

    public func health(of device: Device) -> DeviceHealth {
        let power = devicePower.values.first { $0.owner?.rid == device.id }?.powerState
        let link = connectivity.values.first { $0.owner?.rid == device.id }
        let update = softwareUpdates.values.first { $0.owner?.rid == device.id }
        return DeviceHealth(
            batteryLevel: power?.batteryLevel,
            batteryState: power?.batteryState,
            isConnected: link?.isConnected ?? true,
            hasUpdate: update?.hasUpdate ?? false
        )
    }

    /// False when the bridge can't reach the lamp, e.g. because it was switched off at
    /// the wall. Its last known state is stale then.
    public func isReachable(_ light: Light) -> Bool {
        guard let owner = light.owner?.rid else { return true }
        return !connectivity.values.contains { $0.owner?.rid == owner && !$0.isConnected }
    }

    public func room(of device: Device) -> HueGroup? {
        sortedRooms.first { room in room.children?.contains { $0.rid == device.id } == true }
    }

    /// Low batteries (≤ 20 % or flagged by the bridge), unreachable devices, pending updates.
    public var deviceIssues: [DeviceIssue] {
        sortedDevices.flatMap { device -> [DeviceIssue] in
            let health = health(of: device)
            var issues: [DeviceIssue] = []
            if !health.isConnected {
                issues.append(DeviceIssue(deviceID: device.id, kind: .unreachable))
            }
            let flagged = health.batteryState == "low" || health.batteryState == "critical"
            if flagged || (health.batteryLevel.map { $0 <= 20 } ?? false) {
                issues.append(DeviceIssue(
                    deviceID: device.id,
                    kind: .battery(level: health.batteryLevel, critical: health.batteryState == "critical")
                ))
            }
            if health.hasUpdate {
                issues.append(DeviceIssue(deviceID: device.id, kind: .update))
            }
            return issues
        }
    }
}
