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
        throw HueError.bridge("Die Zeit ist abgelaufen. Drück die Link-Taste auf der Bridge und versuch es gleich noch einmal.")
    }
}
