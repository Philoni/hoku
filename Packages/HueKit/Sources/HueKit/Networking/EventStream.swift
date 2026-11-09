import Foundation

/// One container from the bridge's event stream. `data` holds partial resources:
/// `id` and `type` plus only the properties that changed.
public struct HueEvent: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        case add, update, delete, error
        case unknown

        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }

    public var type: Kind
    public var data: [JSONValue]

    public init(type: Kind, data: [JSONValue]) {
        self.type = type
        self.data = data
    }
}

/// Line-oriented Server-Sent Events parser for the bridge's event stream.
struct SSEParser {
    private var dataLines: [String] = []
    private(set) var lastEventID: String?

    /// Feed one line (without the trailing newline). Returns events when a message completes.
    mutating func consume(_ line: String) -> [HueEvent] {
        let line = line.hasSuffix("\r") ? String(line.dropLast()) : line

        if line.isEmpty {
            defer { dataLines.removeAll() }
            guard !dataLines.isEmpty,
                  let data = dataLines.joined(separator: "\n").data(using: .utf8)
            else { return [] }
            return (try? JSONDecoder().decode([HueEvent].self, from: data)) ?? []
        }

        if line.hasPrefix("data:") {
            dataLines.append(Self.value(of: line, prefix: "data:"))
        } else if line.hasPrefix("id:") {
            lastEventID = Self.value(of: line, prefix: "id:")
        }
        // ":" comments (the bridge sends ": hi" on connect) and other fields are ignored.
        return []
    }

    private static func value(of line: String, prefix: String) -> String {
        let rest = line.dropFirst(prefix.count)
        return String(rest.hasPrefix(" ") ? rest.dropFirst() : rest)
    }
}

public enum EventStreamMessage: Sendable {
    /// The stream (re)connected. Events may have been missed, so resync state.
    case connected
    case events([HueEvent])
    case disconnected(String)
    /// The application key was rejected. The stream stops; the app must pair again.
    case unauthorized
}

extension HueClient {
    /// Connects to `/eventstream/clip/v2` and keeps reconnecting with backoff until cancelled.
    public func eventStream(_ credentials: BridgeCredentials) -> AsyncStream<EventStreamMessage> {
        AsyncStream(bufferingPolicy: .bufferingNewest(64)) { continuation in
            let task = Task {
                var parser = SSEParser()
                var backoff: Duration = .seconds(1)

                while !Task.isCancelled {
                    do {
                        var request = try authorizedRequest(credentials, path: "/eventstream/clip/v2")
                        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                        if let lastID = parser.lastEventID {
                            request.setValue(lastID, forHTTPHeaderField: "Last-Event-ID")
                        }

                        let (bytes, response) = try await streamSession.bytes(for: request)
                        guard let http = response as? HTTPURLResponse else {
                            throw HueError.bridgeUnreachable(String(localized: "keine HTTP-Antwort", bundle: .hueKit))
                        }
                        if http.statusCode == 401 || http.statusCode == 403 { throw HueError.unauthorized }
                        guard http.statusCode == 200 else { throw HueError.http(http.statusCode, nil) }

                        backoff = .seconds(1)
                        continuation.yield(.connected)

                        // AsyncBytes.lines drops empty lines, but SSE needs them as separators.
                        var line = [UInt8]()
                        for try await byte in bytes {
                            guard byte == UInt8(ascii: "\n") else {
                                line.append(byte)
                                continue
                            }
                            let events = parser.consume(String(decoding: line, as: UTF8.self))
                            line.removeAll(keepingCapacity: true)
                            if !events.isEmpty { continuation.yield(.events(events)) }
                        }
                        continuation.yield(.disconnected(String(localized: "Stream beendet", bundle: .hueKit)))
                    } catch is CancellationError {
                        break
                    } catch HueError.unauthorized {
                        continuation.yield(.unauthorized)
                        break
                    } catch {
                        if Task.isCancelled { break }
                        continuation.yield(.disconnected(error.localizedDescription))
                    }

                    try? await Task.sleep(for: backoff)
                    backoff = min(backoff * 2, .seconds(30))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
