//  WHAT: The generated package's `Request/` folder, the same for every API: the method, the request, its body, the
//        values a URL carries, multipart forms and files, and the answer of an endpoint that answers nothing.
//  PIN:  A TEMPLATE IS FINISHED CODE. Each is the file as it lands, `__STEM__` and `__MODULE__` aside; it builds in
//        Swift 6 language mode for iOS 17 and macOS 14 with nothing but Foundation.

enum RequestTemplates {
    static let httpMethod = #"""
    import Foundation

    /// What a request asks the server to do.
    public enum HTTPMethod: String, Sendable, Hashable, CaseIterable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
        case patch = "PATCH"
        case delete = "DELETE"
        case head = "HEAD"

        /// Whether sending it twice does what sending it once does, so a request that failed may be sent again.
        public var isIdempotent: Bool { self != .post && self != .patch }
    }

    """#

    static let request = #"""
    import Foundation

    /// One call of the API, typed by what it answers: the method, the path after the base URL (its `{name}` parameters
    /// filled), the query, the headers and the body, and how the answer's body is read.
    ///
    /// ```swift
    /// let request = Request<Account>(.get, "/v1/accounts/{id}", parameters: ["id": "42"], query: ["full": true])
    /// let account = try await client.send(request)
    /// ```
    public struct Request<Response: Sendable>: Sendable {
        public var method: HTTPMethod
        /// The path after the base URL's, its parameters filled and encoded.
        public var path: String
        /// An absolute URL to send to instead of the base URL and `path`: a feed on another site.
        public var url: URL?
        /// The query, in order. The client adds the token when the auth is a query parameter.
        public var query: [URLQueryItem]
        /// Headers this request sets over the client's.
        public var headers: [String: String]
        public var body: RequestBody?
        /// Seconds to wait for an answer; nil keeps the transport's.
        public var timeout: TimeInterval?
        /// Reads the answer's body, with the client's decoder.
        public var decode: @Sendable (Data, JSONDecoder) throws -> Response

        /// A request whose answer is read by `decode`.
        public init(_ method: HTTPMethod, _ path: String, parameters: KeyValuePairs<String, any QueryValue> = [:],
                    query: KeyValuePairs<String, (any QueryValue)?> = [:], headers: [String: String] = [:],
                    body: RequestBody? = nil, decode: @escaping @Sendable (Data, JSONDecoder) throws -> Response) {
            self.method = method
            self.path = Self.fill(path, with: parameters)
            self.query = Self.items(query)
            self.headers = headers
            self.body = body
            self.decode = decode
        }

        /// `path` with each `{name}` replaced by its value, encoded as one path segment (`a/b` stays one segment).
        public static func fill(_ path: String, with parameters: KeyValuePairs<String, any QueryValue>) -> String {
            var filled = path
            for (name, value) in parameters {
                let text = value.queryValues.joined(separator: ",")
                let encoded = text.addingPercentEncoding(withAllowedCharacters: .pathSegmentAllowed) ?? text
                filled = filled.replacingOccurrences(of: "{\(name)}", with: encoded)
            }
            return filled
        }

        /// Query items for `parameters`, in order: an array gives one item a value, and a nil value none.
        public static func items(_ parameters: KeyValuePairs<String, (any QueryValue)?>) -> [URLQueryItem] {
            parameters.flatMap { name, value in (value?.queryValues ?? []).map { URLQueryItem(name: name, value: $0) } }
        }
    }

    extension Request where Response: Decodable {
        /// A request whose answer is JSON, read as `Response`.
        public init(_ method: HTTPMethod, _ path: String, parameters: KeyValuePairs<String, any QueryValue> = [:],
                    query: KeyValuePairs<String, (any QueryValue)?> = [:], headers: [String: String] = [:],
                    body: RequestBody? = nil) {
            self.init(method, path, parameters: parameters, query: query, headers: headers, body: body) { data, decoder in
                try decoder.decode(Response.self, from: data)
            }
        }
    }

    extension Request where Response == NoContent {
        /// A request whose answer's body, if any, is not read.
        public init(_ method: HTTPMethod, _ path: String, parameters: KeyValuePairs<String, any QueryValue> = [:],
                    query: KeyValuePairs<String, (any QueryValue)?> = [:], headers: [String: String] = [:],
                    body: RequestBody? = nil) {
            self.init(method, path, parameters: parameters, query: query, headers: headers, body: body) { _, _ in NoContent() }
        }
    }

    extension CharacterSet {
        /// What one path segment may hold as it is: a path's characters but `/`.
        static let pathSegmentAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    }

    """#

    static let requestBody = #"""
    import Foundation

    /// What a request sends.
    public enum RequestBody: Sendable {
        /// A value, written as JSON by the client's encoder.
        case json(any Encodable & Sendable)
        /// A `multipart/form-data` form: text fields and files.
        case multipart(Multipart)
        /// A URL-encoded form (`a=1&b=2`), as OAuth token endpoints take.
        case form([URLQueryItem])
        /// Bytes as they are, with their content type.
        case data(Data, contentType: String)
    }

    """#

    static let queryValue = #"""
    import Foundation

    /// A value a URL carries in its path or query, written as text: one item for a value, one an element for an array.
    /// Strings, numbers, Bools, dates (ISO 8601), URLs, UUIDs and the API's enums are query values.
    public protocol QueryValue: Sendable {
        /// The text of each item the value is sent as.
        var queryValues: [String] { get }
    }

    extension QueryValue where Self: LosslessStringConvertible {
        public var queryValues: [String] { [description] }
    }

    extension QueryValue where Self: RawRepresentable, RawValue: QueryValue {
        public var queryValues: [String] { rawValue.queryValues }
    }

    extension String: QueryValue {}
    extension Bool: QueryValue {}
    extension Int: QueryValue {}
    extension Int64: QueryValue {}
    extension Int32: QueryValue {}
    extension Int16: QueryValue {}
    extension Int8: QueryValue {}
    extension UInt: QueryValue {}
    extension UInt64: QueryValue {}
    extension UInt32: QueryValue {}
    extension UInt16: QueryValue {}
    extension UInt8: QueryValue {}
    extension Double: QueryValue {}
    extension Float: QueryValue {}

    extension Decimal: QueryValue {
        public var queryValues: [String] { [description] }
    }

    extension UUID: QueryValue {
        public var queryValues: [String] { [uuidString.lowercased()] }
    }

    extension URL: QueryValue {
        public var queryValues: [String] { [absoluteString] }
    }

    extension Date: QueryValue {
        public var queryValues: [String] { [formatted(.iso8601)] }
    }

    extension Array: QueryValue where Element: QueryValue {
        public var queryValues: [String] { flatMap(\.queryValues) }
    }

    """#

    static let multipart = #"""
    import Foundation

    /// A `multipart/form-data` body: text fields and files, each a part between boundaries, as uploads are sent.
    ///
    /// ```swift
    /// var form = Multipart()
    /// form.add("caption", "A bowl of soup")
    /// form.add("photo", MultipartFile(data: jpeg, filename: "soup.jpg"))
    /// ```
    public struct Multipart: Sendable, Hashable {
        /// One part: a field's text, or a file's bytes with its name and type.
        public struct Part: Sendable, Hashable {
            public var name: String
            public var filename: String?
            public var mimeType: String?
            public var data: Data
        }

        /// The line between parts: random, so no file's bytes hold it.
        public let boundary: String
        public private(set) var parts: [Part] = []

        public init(boundary: String = "Boundary-\(UUID().uuidString)") {
            self.boundary = boundary
        }

        /// Adds a text field: one part, or one an element of an array.
        public mutating func add(_ name: String, _ value: some QueryValue) {
            for text in value.queryValues {
                parts.append(Part(name: name, filename: nil, mimeType: nil, data: Data(text.utf8)))
            }
        }

        /// Adds a file.
        public mutating func add(_ name: String, _ file: MultipartFile) {
            parts.append(Part(name: name, filename: file.filename, mimeType: file.mimeType, data: file.data))
        }

        /// `multipart/form-data; boundary=…`: the request's `Content-Type`.
        public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

        /// The body: each part's headers and bytes between boundaries, then the closing boundary.
        public var data: Data {
            var body = Data()
            for part in parts {
                body.append(Data("--\(boundary)\r\n".utf8))
                var disposition = "Content-Disposition: form-data; name=\"\(Self.escaped(part.name))\""
                if let filename = part.filename { disposition += "; filename=\"\(Self.escaped(filename))\"" }
                body.append(Data("\(disposition)\r\n".utf8))
                if let mimeType = part.mimeType { body.append(Data("Content-Type: \(mimeType)\r\n".utf8)) }
                body.append(Data("\r\n".utf8))
                body.append(part.data)
                body.append(Data("\r\n".utf8))
            }
            body.append(Data("--\(boundary)--\r\n".utf8))
            return body
        }

        /// A name or filename as a quoted header value holds it: quotes and line breaks encoded.
        static func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "\"", with: "%22")
                .replacingOccurrences(of: "\r", with: "%0D")
                .replacingOccurrences(of: "\n", with: "%0A")
        }
    }

    """#

    static let multipartFile = #"""
    import Foundation
    import UniformTypeIdentifiers

    /// A file to upload: its bytes, its name, and what kind of file it is.
    public struct MultipartFile: Sendable, Hashable {
        public var data: Data
        public var filename: String
        /// `image/jpeg`: read off the filename's extension when not given, `application/octet-stream` when that says
        /// nothing.
        public var mimeType: String

        public init(data: Data, filename: String, mimeType: String? = nil) {
            self.data = data
            self.filename = filename
            self.mimeType = mimeType ?? Self.mimeType(of: filename)
        }

        /// The file at `url`, read whole.
        public init(contentsOf url: URL, mimeType: String? = nil) throws {
            self.init(data: try Data(contentsOf: url), filename: url.lastPathComponent, mimeType: mimeType)
        }

        /// `soup.jpg` → `image/jpeg`.
        public static func mimeType(of filename: String) -> String {
            let pathExtension = (filename as NSString).pathExtension
            return UTType(filenameExtension: pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
    }

    """#

    static let noContent = #"""
    import Foundation

    /// The answer of an endpoint that answers nothing (`204 No Content`): its body, if any, is not read.
    public struct NoContent: Sendable, Hashable {
        public init() {}
    }

    """#
}
