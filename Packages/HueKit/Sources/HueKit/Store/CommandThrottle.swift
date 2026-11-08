import Foundation

/// Coalesces rapid commands per target so sliders don't flood the bridge.
///
/// The first command goes out immediately. While it is in flight or the interval
/// hasn't elapsed, newer commands for the same target are merged into one pending
/// payload, and the latest state always lands last.
actor CommandThrottle {
    struct Target: Hashable, Sendable {
        var type: String
        var id: String
    }

    typealias Send = @Sendable (Target, JSONValue) async -> Void

    private var pending: [Target: JSONValue] = [:]
    private var busy: Set<Target> = []
    private let send: Send

    init(send: @escaping Send) {
        self.send = send
    }

    /// Signify's guidance: ~10 commands/s for lights, ~1/s for group broadcasts.
    /// Groups get a slightly faster pace so dragging still feels live.
    static func interval(for target: Target) -> Duration {
        target.type == "grouped_light" ? .milliseconds(450) : .milliseconds(110)
    }

    func submit(_ body: JSONValue, to target: Target) {
        pending[target] = pending[target].map { $0.merging(body) } ?? body
        guard !busy.contains(target) else { return }
        busy.insert(target)
        Task { await drain(target) }
    }

    private func drain(_ target: Target) async {
        while let body = pending.removeValue(forKey: target) {
            let started = ContinuousClock.now
            await send(target, body)
            // Stay busy for the rest of the interval so the next command keeps its distance.
            let remaining = Self.interval(for: target) - (ContinuousClock.now - started)
            if remaining > .zero {
                try? await Task.sleep(for: remaining)
            }
        }
        busy.remove(target)
    }
}
