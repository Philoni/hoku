import Foundation
import Network
import Synchronization

/// A long-running Bonjour search for Hue bridges that reports how macOS answers it.
///
/// The first Bonjour search is what makes macOS ask for local network access; there is
/// no API to ask or check directly (TN3179). So the setup assistant explains first,
/// then starts this browser and follows its state: while the prompt is open, or after
/// "Don't Allow", the browser waits with "policy denied"; once allowed — even later in
/// System Settings — it becomes ready and finds bridges on its own.
public final class BridgeBrowser: Sendable {
    public enum Event: Sendable, Equatable {
        /// Local network access works.
        case allowed
        /// The prompt is open, or access was denied.
        case deniedOrPending
        /// Bridges announced themselves (resolved IPv4 addresses).
        case found([String])
        case failed(String)
    }

    private let browser: NWBrowser

    public init() {
        browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_hue._tcp", domain: "local."), using: .tcp)
    }

    /// Starts browsing; events arrive until the stream's consumer stops listening.
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            browser.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    continuation.yield(.allowed)
                case .waiting where Self.isPolicyDenied(state):
                    continuation.yield(.deniedOrPending)
                case let .failed(error):
                    continuation.yield(.failed(error.localizedDescription))
                default:
                    break
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                let endpoints = results.map(\.endpoint)
                Task {
                    let hosts = await BridgeDiscovery.resolve(endpoints)
                    if !hosts.isEmpty { continuation.yield(.found(hosts)) }
                }
            }
            continuation.onTermination = { [browser] _ in browser.cancel() }
            browser.start(queue: .global(qos: .userInitiated))
        }
    }

    public func cancel() {
        browser.cancel()
    }

    /// `kDNSServiceErr_PolicyDenied`: the system blocked the search (local network privacy).
    static func isPolicyDenied(_ state: NWBrowser.State) -> Bool {
        switch state {
        case let .waiting(error), let .failed(error):
            if case let .dns(code) = error { return code == -65570 }
            return false
        default:
            return false
        }
    }
}
