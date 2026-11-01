//  WHAT: The generated package's `Transport/` folder: what carries a request and brings its answer back, the answer
//        itself, URLSession's transport for the app, and the mock tests and SwiftUI previews send through.

enum TransportTemplates {
    static let httpTransport = #"""
    import Foundation

    /// What carries a request to the server and brings its answer back: `URLSessionTransport` in the app,
    /// `MockTransport` in tests and previews.
    public protocol HTTPTransport: Sendable {
        func send(_ request: URLRequest) async throws -> HTTPResponse
    }

    """#

    static let httpResponse = #"""
    import Foundation

    /// A server's answer: its status, its headers and its body.
    public struct HTTPResponse: Sendable, Hashable {
        public var status: Int
        public var headers: [String: String]
        public var body: Data

        public init(status: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.status = status
            self.headers = headers
            self.body = body
        }

        /// The value of the header `name`, whatever its case: `retry-after` finds `Retry-After`.
        public func header(_ name: String) -> String? {
            if let value = headers[name] { return value }
            return headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    """#

    static let urlSessionTransport = #"""
    import Foundation

    /// Requests sent with a `URLSession`: the transport an app uses.
    public struct URLSessionTransport: HTTPTransport {
        public let session: URLSession

        public init(session: URLSession = .shared) {
            self.session = session
        }

        public func send(_ request: URLRequest) async throws -> HTTPResponse {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            var headers: [String: String] = [:]
            for (name, value) in http.allHeaderFields {
                if let name = name as? String { headers[name] = "\(value)" }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        }
    }

    """#

    static let mockTransport = #"""
    import Foundation
    import os

    /// A transport that answers from what it was given and keeps every request it was sent, with no network: what
    /// tests and SwiftUI previews send through.
    ///
    /// ```swift
    /// let transport = MockTransport()
    /// transport.enqueue(json: #"{"id": "1"}"#)                     // the next request's answer
    /// transport.route(.get, "/v1/recipes/{id}", json: #"{…}"#)      // the answer of every request it matches
    /// let client = __STEM__Client(baseURL: URL(string: "https://example.com")!, transport: transport, tokens: MemoryTokenStore())
    /// ```
    ///
    /// A queued answer is used first, in order; then the last route whose method and path match (a `{name}` segment
    /// matches any one segment, `*` the rest). A request nothing answers throws `MockTransport.Unanswered`.
    public final class MockTransport: HTTPTransport, Sendable {
        /// What the mock throws for a request it has no answer for.
        public struct Unanswered: Error, CustomStringConvertible {
            public let method: String
            public let path: String
            public var description: String { "no answer is queued or routed for \(method) \(path)" }
        }

        private struct Route: Sendable {
            var method: HTTPMethod?
            var segments: [String]
            var response: HTTPResponse

            func matches(_ method: String, _ path: String) -> Bool {
                if let expected = self.method, expected.rawValue != method { return false }
                let parts = path.split(separator: "/").map(String.init)
                for (index, segment) in segments.enumerated() {
                    if segment == "*" { return true }
                    guard index < parts.count else { return false }
                    if segment.hasPrefix("{"), segment.hasSuffix("}") { continue }
                    if segment != parts[index] { return false }
                }
                return parts.count == segments.count
            }
        }

        private struct State: Sendable {
            var queue: [HTTPResponse] = []
            var routes: [Route] = []
            var requests: [URLRequest] = []
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        public init() {}

        /// Answers the next request that nothing queued before answers.
        public func enqueue(_ response: HTTPResponse) {
            state.withLock { $0.queue.append(response) }
        }

        /// Answers the next request with `json`.
        public func enqueue(json: String, status: Int = 200, headers: [String: String] = [:]) {
            enqueue(HTTPResponse(status: status, headers: Self.json(headers), body: Data(json.utf8)))
        }

        /// Answers every request `method` sends to `path` (any method when nil) with `response`.
        public func route(_ method: HTTPMethod?, _ path: String, _ response: HTTPResponse) {
            let segments = path.split(separator: "/").map(String.init)
            state.withLock { $0.routes.append(Route(method: method, segments: segments, response: response)) }
        }

        /// Answers every request `method` sends to `path` with `json`.
        public func route(_ method: HTTPMethod?, _ path: String, json: String, status: Int = 200, headers: [String: String] = [:]) {
            route(method, path, HTTPResponse(status: status, headers: Self.json(headers), body: Data(json.utf8)))
        }

        /// Answers every request `method` sends to `path` with `value`, written as the API writes JSON.
        public func route(_ method: HTTPMethod?, _ path: String, value: some Encodable, status: Int = 200,
                          encoder: JSONEncoder = __STEM__Coding.encoder()) throws {
            route(method, path, HTTPResponse(status: status, headers: Self.json([:]), body: try encoder.encode(value)))
        }

        /// Every request sent, in order.
        public var requests: [URLRequest] { state.withLock { $0.requests } }

        /// The request sent last.
        public var lastRequest: URLRequest? { state.withLock { $0.requests.last } }

        /// Forgets the queue, the routes and the requests.
        public func reset() {
            state.withLock { $0 = State() }
        }

        public func send(_ request: URLRequest) async throws -> HTTPResponse {
            let method = request.httpMethod ?? "GET"
            let path = request.url?.path ?? "/"
            let answer: HTTPResponse? = state.withLock { state in
                state.requests.append(request)
                if !state.queue.isEmpty { return state.queue.removeFirst() }
                return state.routes.last { $0.matches(method, path) }?.response
            }
            guard let answer else { throw Unanswered(method: method, path: path) }
            return answer
        }

        private static func json(_ headers: [String: String]) -> [String: String] {
            var headers = headers
            if !headers.keys.contains(where: { $0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
                headers["Content-Type"] = "application/json"
            }
            return headers
        }
    }

    """#
}
