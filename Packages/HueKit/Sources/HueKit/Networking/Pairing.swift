import Foundation

extension HueClient {
    /// Polls the bridge once a second until the link button is pressed or `timeout` passes.
    /// `onTick` reports the seconds remaining so the UI can show a countdown.
    public func pair(
        with bridge: DiscoveredBridge,
        deviceName: String,
        timeout: Duration = .seconds(60),
        onTick: @MainActor @Sendable (Int) -> Void = { _ in }
    ) async throws -> BridgeCredentials {
        // devicetype is "<app ≤20>#<device ≤19>".
        let device = String(deviceName.filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(19))
        let deviceType = "Hoku#\(device.isEmpty ? "Mac" : device)"

        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            try Task.checkCancellation()
            let remaining = Int((deadline - clock.now).components.seconds)
            await onTick(remaining)
            do {
                let result = try await requestApplicationKey(host: bridge.host, deviceType: deviceType)
                return BridgeCredentials(
                    bridgeID: bridge.id,
                    host: bridge.host,
                    applicationKey: result.key,
                    clientKey: result.clientKey,
                    name: bridge.name
                )
            } catch HueError.linkButtonNotPressed {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw HueError.bridge(String(localized: "Die Zeit ist abgelaufen. Drück die Link-Taste auf der Bridge und versuch es gleich noch einmal.", bundle: .hueKit))
    }
}

/// An application key the user already has, for example from another tool or an earlier setup.
public enum ApplicationKey {
    /// The key without surrounding whitespace, or `nil` if it cannot be one: bridges
    /// issue 20 to 64 letters, digits and hyphens.
    public static func normalized(_ text: String) -> String? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...64).contains(key.count),
              key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return key
    }
}

extension HueClient {
    /// Connects with an existing key instead of the link button. Throws if the bridge rejects it.
    public func connect(to bridge: DiscoveredBridge, applicationKey: String) async throws -> BridgeCredentials {
        let credentials = BridgeCredentials(bridgeID: bridge.id, host: bridge.host, applicationKey: applicationKey, name: bridge.name)
        do {
            _ = try await resource(credentials, type: "bridge", id: "")
        } catch HueError.unauthorized {
            throw HueError.bridge(String(localized: "Die Bridge kennt diesen Schlüssel nicht.", bundle: .hueKit))
        }
        return credentials
    }
}
