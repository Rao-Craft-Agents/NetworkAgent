//  WHAT: The generated package's client: one `Sendable` class holding where it sends (a base URL that may change while
//        the app runs), how it signs requests, how it codes JSON and when it tries again, and one generic `send`.
//  PIN:  THE BASE URL IS STATE, BEHIND A LOCK. One app talks to many instances: a person picks another, the app sets
//        `baseURL`, and every request after goes there, from any task, with that host's own token.

enum ClientTemplates {
    /// `__ABOUT__` (the API in a few words), `__BASE_DECL__` (the default base URL's declaration, or nothing),
    /// `__BASE_DEFAULT__` (` = __STEM__Client.defaultBaseURL`, or nothing), `__EXAMPLE_BASE__` and `__AUTH__` are filled
    /// per call.
    static let client = #"""
    import Foundation
    import os

    /// The typed client of __ABOUT__: where it sends (`baseURL`, which may change while the app runs, so one client
    /// follows the server a person picks), how it signs requests (`auth`, with the token kept per host in `tokens`), how
    /// it reads and writes JSON, and when it tries a failed request again.
    ///
    /// ```swift
    /// let client = __STEM__Client(baseURL: URL(string: "__EXAMPLE_BASE__")!)
    /// client.baseURL = URL(string: "https://another.example")!   // every request after goes there
    /// ```
    ///
    /// Each endpoint is a method (`Endpoints/`); `send(_:)` sends any other `Request`.
    public final class __STEM__Client: Sendable {
    __BASE_DECL__    /// How a request proves who sends it.
        public let auth: AuthScheme
        /// Where the tokens are kept, one a host.
        public let tokens: any TokenStore
        /// What carries the requests.
        public let transport: any HTTPTransport
        /// When a failed request is sent again.
        public let retry: RetryPolicy
        /// Reads the answers: `__STEM__Coding.decoder()` unless the client was given another.
        public let decoder: JSONDecoder
        /// Writes the bodies: `__STEM__Coding.encoder()` unless the client was given another.
        public let encoder: JSONEncoder

        private struct State: Sendable {
            var baseURL: URL
            var headers: [String: String]
        }

        private let state: OSAllocatedUnfairLock<State>

        public init(baseURL: URL__BASE_DEFAULT__, auth: AuthScheme = __AUTH__, tokens: any TokenStore = KeychainTokenStore(),
                    transport: any HTTPTransport = URLSessionTransport(), retry: RetryPolicy = .standard,
                    decoder: JSONDecoder = __STEM__Coding.decoder(), encoder: JSONEncoder = __STEM__Coding.encoder(),
                    headers: [String: String] = [:]) {
            self.state = OSAllocatedUnfairLock(initialState: State(baseURL: baseURL, headers: headers))
            self.auth = auth
            self.tokens = tokens
            self.transport = transport
            self.retry = retry
            self.decoder = decoder
            self.encoder = encoder
        }

        /// Where requests go: a scheme, a host and, optionally, a path each endpoint's path is added to.
        public var baseURL: URL {
            get { state.withLock { $0.baseURL } }
            set { state.withLock { $0.baseURL = newValue } }
        }

        /// Headers every request carries beside its own: a `User-Agent`, an app version.
        public var headers: [String: String] {
            get { state.withLock { $0.headers } }
            set { state.withLock { $0.headers = newValue } }
        }

        /// A client like this one that sends to `baseURL`: the same transport, tokens, retries and coding.
        public func withBaseURL(_ baseURL: URL) -> __STEM__Client {
            __STEM__Client(baseURL: baseURL, auth: auth, tokens: tokens, transport: transport, retry: retry, decoder: decoder,
                           encoder: encoder, headers: headers)
        }

        /// `example.com`, `https://example.com/` or `http://localhost:8080` as a base URL: `https` when the text names no
        /// scheme; nil when it names no host.
        public static func url(from text: String) -> URL? {
            var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            if !text.contains("://") { text = "https://" + text }
            while text.hasSuffix("/") { text.removeLast() }
            guard let url = URL(string: text), url.host != nil, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                return nil
            }
            return url
        }

        // MARK: - Signing in

        /// The token kept for the current host; nil when signed out there.
        public var token: String? { tokens.token(for: Self.hostKey(baseURL)) }

        /// Whether a token is kept for the current host.
        public var isSignedIn: Bool { token != nil }

        /// Keeps `token` for the current host: every request to it carries the token after.
        public func signIn(token: String) throws {
            try tokens.setToken(token, for: Self.hostKey(baseURL))
        }

        /// Keeps `user:password` for the current host, for `.basic` auth.
        public func signIn(user: String, password: String) throws {
            try signIn(token: "\(user):\(password)")
        }

        /// Forgets the current host's token.
        public func signOut() throws {
            try tokens.setToken(nil, for: Self.hostKey(baseURL))
        }

        /// The host a token is kept under: `example.com`, or `localhost:8080` with a port.
        static func hostKey(_ url: URL) -> String {
            let host = url.host(percentEncoded: false)?.lowercased() ?? ""
            return url.port.map { "\(host):\($0)" } ?? host
        }

        // MARK: - Sending

        /// Sends `request` and answers what its answer reads as; throws `__STEM__Error` for anything else.
        public func send<Response>(_ request: Request<Response>) async throws -> Response {
            try await exchange(request).value
        }

        /// Sends `request` and answers what its answer reads as, with the answer itself (its status and headers): for
        /// paging by the `Link` header, and anything else a header says.
        public func exchange<Response>(_ request: Request<Response>) async throws -> (value: Response, response: HTTPResponse) {
            let urlRequest = try urlRequest(for: request)
            var attempt = 1
            while true {
                try Task.checkCancellation()
                let answer: HTTPResponse
                do {
                    answer = try await transport.send(urlRequest)
                } catch {
                    if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                        throw CancellationError()
                    }
                    if let wait = retry.delay(after: error, attempt: attempt, method: request.method) {
                        try await RetryPolicy.wait(wait)
                        attempt += 1
                        continue
                    }
                    throw __STEM__Error.transport(error)
                }
                if (200..<300).contains(answer.status) {
                    do {
                        return (try request.decode(answer.body, decoder), answer)
                    } catch let error as DecodingError {
                        throw __STEM__Error(decoding: error, as: Response.self)
                    } catch let error as __STEM__Error {
                        throw error
                    } catch {
                        throw __STEM__Error.decoding(type: String(describing: Response.self), path: "the top", reason: "\(error)")
                    }
                }
                if let wait = retry.delay(after: answer, attempt: attempt, method: request.method) {
                    try await RetryPolicy.wait(wait)
                    attempt += 1
                    continue
                }
                throw __STEM__Error(answer)
            }
        }

        /// The `URLRequest` `request` is sent as: the base URL and the path, the query, the headers, the body and the
        /// token of the request's host.
        public func urlRequest<Response>(for request: Request<Response>) throws -> URLRequest {
            let base = baseURL
            var made: URLComponents?
            if let url = request.url {
                made = URLComponents(url: url, resolvingAgainstBaseURL: true)
            } else if var components = URLComponents(url: base, resolvingAgainstBaseURL: true) {
                var basePath = components.percentEncodedPath
                while basePath.hasSuffix("/") { basePath.removeLast() }
                var path = request.path.addingPercentEncoding(withAllowedCharacters: .encodedPathAllowed) ?? request.path
                if !path.isEmpty, !path.hasPrefix("/") { path = "/" + path }
                components.percentEncodedPath = basePath + path
                made = components
            }
            guard var components = made, components.host != nil else {
                throw __STEM__Error.invalidRequest(String(localized: "\(base.absoluteString) and \(request.path) make no URL."))
            }
            let host = components.host.map { host in components.port.map { "\(host.lowercased()):\($0)" } ?? host.lowercased() } ?? ""
            let token = tokens.token(for: host)

            var query = components.percentEncodedQuery.map { [$0] } ?? []
            var items = request.query
            if case .query(let name) = auth, let token { items.append(URLQueryItem(name: name, value: token)) }
            query += items.map { Self.encoded($0.name) + "=" + Self.encoded($0.value ?? "") }
            components.percentEncodedQuery = query.isEmpty ? nil : query.joined(separator: "&")
            guard let url = components.url else {
                throw __STEM__Error.invalidRequest(String(localized: "\(base.absoluteString) and \(request.path) make no URL."))
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = request.method.rawValue
            if let timeout = request.timeout { urlRequest.timeoutInterval = timeout }
            urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
            for (name, value) in headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
            if let token {
                switch auth {
                case .bearer: urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                case .basic: urlRequest.setValue("Basic \(Data(token.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
                case .header(let name): urlRequest.setValue(token, forHTTPHeaderField: name)
                case .none, .query: break
                }
            }
            switch request.body {
            case .json(let value)?:
                do {
                    urlRequest.httpBody = try encoder.encode(value)
                } catch {
                    throw __STEM__Error.invalidRequest(String(localized: "The request's body could not be written: \(error.localizedDescription)"))
                }
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            case .multipart(let form)?:
                urlRequest.httpBody = form.data
                urlRequest.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            case .form(let fields)?:
                let pairs = fields.map { Self.encoded($0.name) + "=" + Self.encoded($0.value ?? "") }
                urlRequest.httpBody = Data(pairs.joined(separator: "&").utf8)
                urlRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            case .data(let data, let contentType)?:
                urlRequest.httpBody = data
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            case nil:
                break
            }
            for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
            return urlRequest
        }

        /// `text` with everything but letters, digits and `-._~` percent-encoded: a `+` or `&` in a value stays a value.
        static func encoded(_ text: String) -> String {
            text.addingPercentEncoding(withAllowedCharacters: .queryValueAllowed) ?? text
        }
    }

    extension CharacterSet {
        /// What a query name or value may hold as it is: RFC 3986's unreserved characters.
        static let queryValueAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        /// What an already encoded path may hold: a path's characters and `%`.
        static let encodedPathAllowed = CharacterSet.urlPathAllowed.union(CharacterSet(charactersIn: "%"))
    }

    """#

    static let package = #"""
    // swift-tools-version:6.0
    // __MODULE__: the typed client of __ABOUT__, for iOS 17 and macOS 14, with nothing but Foundation.

    import PackageDescription

    let package = Package(
        name: "__MODULE__",
        platforms: [.iOS(.v17), .macOS(.v14)],
        products: [
            .library(name: "__MODULE__", targets: ["__MODULE__"]),
        ],
        targets: [
            .target(
                name: "__MODULE__",
                swiftSettings: [.swiftLanguageMode(.v6)]),
            .testTarget(
                name: "__MODULE__Tests",
                dependencies: ["__MODULE__"],
                swiftSettings: [.swiftLanguageMode(.v6)]),
        ]
    )

    """#
}
