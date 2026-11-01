//  WHAT: The generated package's `Errors/` folder: what a call throws instead of answering, said so an app can show
//        it and a developer can find the cause, and when a failed request is sent again.

enum ErrorTemplates {
    static let error = #"""
    import Foundation

    /// What a call of the __STEM__ API throws instead of answering.
    public enum __STEM__Error: Error, LocalizedError {
        /// No answer came: no connection, a timeout, a host that cannot be found.
        case transport(any Error)
        /// The server answered with a status that is not a success; `message` is what its body says, when it says.
        case status(Int, message: String?, body: Data)
        /// The server wants a person signed in (401): the token is missing, or no longer good.
        case unauthorized(message: String?)
        /// The answer is not what the type reads: the type, where in the JSON (`items[3].author.name`), and why.
        case decoding(type: String, path: String, reason: String)
        /// The request could not be made: a base URL and path that make no URL, a body that does not encode.
        case invalidRequest(String)

        /// The server's answer as an error: 401 is `unauthorized`, anything else `status`, with what the body says.
        public init(_ response: HTTPResponse) {
            let message = Self.message(in: response.body)
            if response.status == 401 {
                self = .unauthorized(message: message)
            } else {
                self = .status(response.status, message: message, body: response.body)
            }
        }

        /// A decoding failure, said with the path to the value that failed.
        public init(decoding error: DecodingError, as type: Any.Type) {
            let name = String(describing: type)
            switch error {
            case .keyNotFound(let key, let context):
                self = .decoding(type: name, path: Self.path(context.codingPath + [key]), reason: "the key is missing")
            case .valueNotFound(_, let context):
                self = .decoding(type: name, path: Self.path(context.codingPath), reason: "the value is null")
            case .typeMismatch(let expected, let context):
                self = .decoding(type: name, path: Self.path(context.codingPath), reason: "it is not \(expected)")
            case .dataCorrupted(let context):
                self = .decoding(type: name, path: Self.path(context.codingPath), reason: context.debugDescription)
            @unknown default:
                self = .decoding(type: name, path: "", reason: "\(error)")
            }
        }

        /// The HTTP status, when the server answered.
        public var statusCode: Int? {
            switch self {
            case .status(let code, _, _): return code
            case .unauthorized: return 401
            default: return nil
            }
        }

        /// The body the server answered with, read as `type` (the API's own error type), when it reads as one.
        public func body<T: Decodable>(as type: T.Type, decoder: JSONDecoder = __STEM__Coding.decoder()) -> T? {
            guard case .status(_, _, let body) = self else { return nil }
            return try? decoder.decode(type, from: body)
        }

        public var errorDescription: String? {
            switch self {
            case .transport(let error):
                return String(localized: "The server could not be reached: \(error.localizedDescription)")
            case .status(let code, let message, _):
                return message ?? String(localized: "The server answered with status \(code).")
            case .unauthorized(let message):
                return message ?? String(localized: "Sign in again to do this.")
            case .decoding(let type, let path, let reason):
                return String(localized: "The server's answer could not be read as \(type) at \(path): \(reason).")
            case .invalidRequest(let reason):
                return reason
            }
        }

        /// `items[3].author.name` for a coding path.
        static func path(_ keys: [any CodingKey]) -> String {
            var path = ""
            for key in keys {
                if let index = key.intValue {
                    path += "[\(index)]"
                } else {
                    path += path.isEmpty ? key.stringValue : "." + key.stringValue
                }
            }
            return path.isEmpty ? "the top" : path
        }

        /// What an error body says, in the shapes APIs write it: `{"error": "…"}`, `{"message": "…"}`,
        /// `{"error": {"message": "…"}}`, `{"errors": [{"message": "…"}]}`, `{"detail": "…"}`, or a short text.
        static func message(in body: Data) -> String? {
            guard !body.isEmpty else { return nil }
            if let object = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) {
                return text(in: object)
            }
            let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty || text.count > 300 || text.hasPrefix("<") ? nil : text
        }

        private static func text(in object: Any) -> String? {
            if let string = object as? String { return string.isEmpty ? nil : string }
            if let array = object as? [Any] { return array.lazy.compactMap { text(in: $0) }.first }
            guard let dictionary = object as? [String: Any] else { return nil }
            for key in ["message", "error_description", "error", "detail", "errors", "msg", "reason", "title"] {
                if let value = dictionary[key], let found = text(in: value) { return found }
            }
            return nil
        }
    }

    """#

    static let retryPolicy = #"""
    import Foundation

    /// When a request that failed is sent again: after a 429 (too many requests), whatever its method; after a 408,
    /// 500, 502, 503 or 504 or a dropped connection, when sending it twice does no harm (GET, PUT, DELETE, HEAD). Each
    /// wait is what the server's `Retry-After` asks, else a backoff that doubles from `delay`, never past `maxDelay`.
    public struct RetryPolicy: Sendable, Hashable {
        /// How many times a request is sent at most, the first time included.
        public var attempts: Int
        /// The wait before the second try; each try after waits about twice the one before.
        public var delay: TimeInterval
        /// The longest wait, whatever `Retry-After` asks.
        public var maxDelay: TimeInterval

        public init(attempts: Int = 3, delay: TimeInterval = 0.5, maxDelay: TimeInterval = 30) {
            self.attempts = max(1, attempts)
            self.delay = max(0, delay)
            self.maxDelay = max(0, maxDelay)
        }

        /// Three tries, about half a second and a second apart.
        public static let standard = RetryPolicy()
        /// One try: a failure is thrown at once.
        public static let never = RetryPolicy(attempts: 1)

        /// The wait before sending `method` again after try `attempt` (from 1) was answered with `response`; nil when it
        /// is not sent again.
        public func delay(after response: HTTPResponse, attempt: Int, method: HTTPMethod) -> TimeInterval? {
            guard attempt < attempts else { return nil }
            switch response.status {
            case 429:
                break
            case 408, 500, 502, 503, 504:
                guard method.isIdempotent else { return nil }
            default:
                return nil
            }
            if let header = response.header("Retry-After"), let wait = Self.retryAfter(header) {
                return min(max(0, wait), maxDelay)
            }
            return backoff(attempt)
        }

        /// The wait before sending `method` again after try `attempt` failed with `error`; nil when it is not sent again.
        public func delay(after error: any Error, attempt: Int, method: HTTPMethod) -> TimeInterval? {
            let passing: [URLError.Code] = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed]
            guard attempt < attempts, method.isIdempotent, let code = (error as? URLError)?.code, passing.contains(code) else { return nil }
            return backoff(attempt)
        }

        private func backoff(_ attempt: Int) -> TimeInterval {
            let doubled = delay * pow(2, Double(attempt - 1))
            return min(doubled * Double.random(in: 0.8...1.2), maxDelay)
        }

        /// The seconds a `Retry-After` value asks for: a number of seconds, or an HTTP date.
        public static func retryAfter(_ value: String, now: Date = Date()) -> TimeInterval? {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            if let seconds = TimeInterval(trimmed) { return seconds }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            return formatter.date(from: trimmed).map { $0.timeIntervalSince(now) }
        }

        /// Waits `seconds`; a cancelled task stops waiting and throws.
        static func wait(_ seconds: TimeInterval) async throws {
            guard seconds > 0 else { return }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    }

    """#
}
