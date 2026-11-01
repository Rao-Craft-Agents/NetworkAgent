//  WHAT: The generated package's tests: for each endpoint, a call through a mock that asserts the request it makes
//        (method, path, query, headers, body) and reads a sample answer (the JSON the preview is made of, so the
//        answer must equal the preview); a page sequence for each paged endpoint; and the client's own tests (the base
//        URL, the token's host, retries, errors, dates, multipart, the preview client).
//  PIN:  THE SAMPLE IS THE PREVIEW IN JSON. One tree says both, so a test that decodes the sample and compares it with
//        `Type.preview` checks every key and every date of the type against what the server sends.

import Foundation

struct TestEmitter {
    let api: API
    let models: ModelEmitter
    let endpoints: EndpointEmitter

    /// The test target's sample answers, one a type: name → JSON.
    private(set) var samples: [(name: String, json: String)] = []
    private var sampleNames: [String: String] = [:]

    init(api: API, models: ModelEmitter) {
        self.api = api
        self.models = models
        self.endpoints = EndpointEmitter(api: api, models: models)
    }

    // MARK: - A group's tests

    mutating func emit(group: String, file: String) -> String {
        let methods = api.methods.filter { $0.group == group }
        var lines = ["import Foundation", "import XCTest", "@testable import \(api.module)", "",
                     "/// The \(file) endpoints, each sent through a mock: the request it makes and the answer it reads.",
                     "final class \(file)Tests: XCTestCase {"]
        for (index, method) in methods.enumerated() {
            if index > 0 { lines.append("") }
            lines += test(method)
            if method.paging != nil {
                lines.append("")
                lines += pagesTest(method)
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The arguments a test calls `method` with, and what each sends.
    func arguments(_ method: APIMethod, leaving marker: String? = nil, limit: Int? = nil) -> (call: [String], path: String, query: [(String, String)]) {
        var call: [String] = [], query: [(String, String)] = []
        var path = method.endpoint.path
        if let body = method.body, let sample = models.sample(body, field: "body", owner: "") { call.append(sample.swift) }
        for item in method.path {
            let sample = models.sample(item.type, field: item.name, owner: method.name) ?? .string("x")
            call.append("\(SwiftName.member(item.name)): \(sample.swift)")
            path = path.replacingOccurrences(of: "{\(item.wire)}", with: wireText(sample, item.type))
        }
        for part in method.parts {
            let name = SwiftName.member(part.name)
            switch part.part.kind {
            case .file: call.append("\(name): MultipartFile(data: Data(\"Sample file\".utf8), filename: \"sample.txt\")")
            case .files: call.append("\(name): [MultipartFile(data: Data(\"Sample file\".utf8), filename: \"sample.txt\")]")
            case .value(let type):
                let sample = models.sample(type, field: part.name, owner: method.name) ?? .string("x")
                call.append("\(name): \(sample.swift)")
            }
        }
        for item in method.query where item.wire != marker {
            var sample = models.sample(item.type, field: item.name, owner: method.name) ?? .string("x")
            if let limit, item.wire == method.paging?.limit?.wire { sample = .integer(limit) }
            call.append("\(SwiftName.member(item.name)): \(sample.swift)")
            query.append((item.wire, wireText(sample, item.type)))
        }
        return (call, path, query)
    }

    /// What a sample is sent as in a URL: an enum's raw value, a date in ISO 8601, an array's values joined.
    func wireText(_ sample: Sample, _ type: TypeRef) -> String {
        switch sample {
        case .preview(let name):
            guard let entity = models.entities[name], let first = entity.cases.first else { return "" }
            return models.isIntegerEnum(entity) ? (first.raw ?? "0") : models.rawValue(of: first, in: entity)
        case .array(let items):
            if case .array(let element) = type { return items.map { wireText($0, element) }.joined(separator: ",") }
            return sample.text
        default:
            return sample.text
        }
    }

    private mutating func test(_ method: APIMethod) -> [String] {
        let (call, path, query) = arguments(method)
        var lines = ["    func test\(upper(method.name))() async throws {", "        let (client, transport) = Fixture.client()"]
        lines += enqueue(method)
        let invocation = "client.\(SwiftName.member(method.name))(\(call.joined(separator: ", ")))"
        lines += endpoints.wrapped(method.answer == .nothing ? "try await \(invocation)" : "let response = try await \(invocation)", indent: 8)
        lines.append("        let request = try XCTUnwrap(transport.lastRequest)")
        lines.append("        XCTAssertEqual(request.httpMethod, \(Sample.quoted(method.endpoint.method)))")
        lines.append("        XCTAssertEqual(request.url?.path, \(Sample.quoted(path)))")
        var expected = query
        if case .query(let name) = authScheme { expected.append((name, "test-token")) }
        lines += endpoints.wrapped("XCTAssertEqual(request.queryItems, \(dictionary(expected)))", indent: 8)
        lines.append("        XCTAssertEqual(request.value(forHTTPHeaderField: \"Accept\"), \"application/json\")")
        if let header = authHeader { lines.append("        XCTAssertEqual(request.value(forHTTPHeaderField: \(Sample.quoted(header.name))), \(Sample.quoted(header.value)))") }
        if let body = method.body {
            lines.append("        XCTAssertEqual(request.value(forHTTPHeaderField: \"Content-Type\"), \"application/json\")")
            if case .named(let name) = body, let entity = models.entities[name], !entity.isEnum {
                lines += endpoints.wrapped("XCTAssertEqual(request.jsonKeys, [\(models.encodedKeys(entity).map(Sample.quoted).joined(separator: ", "))])", indent: 8)
            }
            if let sample = models.sample(body, field: "body", owner: "") {
                lines += endpoints.wrapped("XCTAssertEqual(try client.decoder.decode(\(body).self, from: XCTUnwrap(request.httpBody)), \(sample.swift))", indent: 8)
            }
        }
        if !method.parts.isEmpty {
            lines.append("        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: \"Content-Type\"))")
            lines.append("        XCTAssertTrue(contentType.hasPrefix(\"multipart/form-data; boundary=\"), contentType)")
            for part in method.parts {
                switch part.part.kind {
                case .file, .files:
                    lines.append("        XCTAssertTrue(request.bodyText.contains(#\"name=\"\(part.part.wire)\"; filename=\"sample.txt\"\"#), request.bodyText)")
                    lines.append("        XCTAssertTrue(request.bodyText.contains(\"Content-Type: text/plain\"), request.bodyText)")
                case .value:
                    lines.append("        XCTAssertTrue(request.bodyText.contains(#\"name=\"\(part.part.wire)\"\"#), request.bodyText)")
                }
            }
            lines.append("        XCTAssertTrue(request.bodyText.contains(\"Sample file\"), request.bodyText)")
        }
        switch method.answer {
        case .nothing: break
        case .data: lines.append("        XCTAssertEqual(response, Data(\"Sample bytes\".utf8))")
        case .text: lines.append("        XCTAssertEqual(response, \(Sample.quoted(endpoints.textSample(method))))")
        case .json(let type):
            if let sample = models.sample(type, field: "response", owner: "") {
                lines += endpoints.wrapped("XCTAssertEqual(response, \(sample.swift))", indent: 8)
            }
        }
        switch method.token {
        case .field(let field, _)?:
            if case .json(let type) = method.answer, case .named(let name) = type, let entity = models.entities[name],
               let tokenField = entity.fields.first(where: { $0.name == field }),
               case .string(let token)? = models.sample(tokenField.type.unwrapped, field: field, owner: name) {
                lines.append("        XCTAssertEqual(client.token, \(Sample.quoted(token)), \"the token it answered is kept for example.com\")")
            }
        case .whole?:
            lines.append("        XCTAssertEqual(client.token, \"Sample token\", \"the token it answered is kept for example.com\")")
        case nil:
            break
        }
        lines.append("    }")
        return lines
    }

    /// What the mock answers `method` with.
    private mutating func enqueue(_ method: APIMethod, headers: String? = nil) -> [String] {
        let extra = headers.map { ", headers: \($0)" } ?? ""
        switch method.answer {
        case .nothing: return ["        transport.enqueue(HTTPResponse(status: 204))"]
        case .data: return ["        transport.enqueue(HTTPResponse(body: Data(\"Sample bytes\".utf8)))"]
        case .text: return ["        transport.enqueue(HTTPResponse(body: Data(\(Sample.quoted(endpoints.textSample(method))).utf8)))"]
        case .json(let type):
            guard let name = sample(for: type) else { return ["        transport.enqueue(json: \"null\"\(extra))"] }
            return ["        transport.enqueue(json: Samples.\(name)\(extra))"]
        }
    }

    private mutating func pagesTest(_ method: APIMethod) -> [String] {
        guard let paging = method.paging, case .json(let type) = method.answer else { return [] }
        // A page as long as the limit is not the last: the sequence asks for the next, which comes back empty.
        let (call, _, _) = arguments(method, leaving: paging.marker.wire, limit: 1)
        let item = paging.item.description
        var lines = ["    func test\(upper(method.pagesName))() async throws {", "        let (client, transport) = Fixture.client()"]
        let marker = Sample.quoted(paging.marker.wire)
        switch paging.next {
        case .number:
            lines += enqueue(method)
            lines.append("        transport.enqueue(json: \(lastPage(type, paging)))")
        case .field:
            lines += enqueue(method)
            lines.append("        transport.enqueue(json: \(lastPage(type, paging)))")
        case .link:
            let link = "https://example.com\(method.endpoint.path)?\(paging.marker.wire)=7"
            lines += enqueue(method, headers: "[\"Link\": \(Sample.quoted("<\(link)>; rel=\"next\""))]")
            lines.append("        transport.enqueue(json: \(lastPage(type, paging)))")
        }
        lines.append("        var pages: [Page<\(item)>] = []")
        lines += endpoints.wrapped("for try await page in client.\(method.pagesName)(\(call.joined(separator: ", "))) { pages.append(page) }", indent: 8)
        if let sample = models.sample(paging.item, field: "item", owner: "") {
            lines += endpoints.wrapped("XCTAssertEqual(pages.map(\\.items), [[\(sample.swift)]])", indent: 8)
        }
        switch paging.next {
        case .number:
            lines.append("        XCTAssertEqual(pages.map(\\.number), [1])")
            lines.append("        XCTAssertEqual(transport.requests.map { $0.queryItems[\(marker)] }, [\"1\", \"2\"])")
        case .field(let field, let fieldType):
            let next = nextSample(type, field: field, fieldType: fieldType)
            lines.append("        XCTAssertEqual(pages.map(\\.next), [\(Sample.quoted(next))])")
            lines.append("        XCTAssertEqual(transport.requests.map { $0.queryItems[\(marker)] }, [nil, \(Sample.quoted(next))])")
        case .link:
            lines.append("        XCTAssertEqual(pages.map(\\.next), [\"7\"])")
            lines.append("        XCTAssertEqual(transport.requests.map { $0.queryItems[\(marker)] }, [nil, \"7\"])")
        }
        lines.append("    }")
        return lines
    }

    /// The next cursor a sample answer names.
    private func nextSample(_ type: TypeRef, field: String, fieldType: TypeRef) -> String {
        guard case .named(let name) = type, let sample = models.sample(fieldType.unwrapped, field: field, owner: name) else { return "" }
        return sample.text
    }

    /// The last page's JSON: the sample with its items emptied and its next cursor null.
    private mutating func lastPage(_ type: TypeRef, _ paging: APIMethod.Paging) -> String {
        guard let field = paging.itemsField, case .named(let name) = type, let entity = models.entities[name] else { return "\"[]\"" }
        var nulled: String?
        if case .field(let next, let nextType) = paging.next, nextType.isOptional { nulled = next }
        let json = models.json(entity, emptying: field, nulling: nulled)
        let key = lowerFirst(name) + "LastPage"
        if sampleNames[key] == nil {
            sampleNames[key] = key
            samples.append((key, json))
        }
        return "Samples.\(key)"
    }

    /// The name of `type`'s sample in `Samples`, made once.
    private mutating func sample(for type: TypeRef) -> String? {
        guard let value = models.sample(type, field: "response", owner: "") else { return nil }
        let key = sampleName(type)
        if sampleNames[key] == nil {
            sampleNames[key] = key
            samples.append((key, models.json(value)))
        }
        return key
    }

    private func sampleName(_ type: TypeRef) -> String {
        switch type {
        case .named(let name): return lowerFirst(name)
        case .array(let element): return sampleName(element) + "List"
        case .dictionary(let key, let value): return sampleName(key) + upper(sampleName(value)) + "Map"
        case .optional(let wrapped): return sampleName(wrapped)
        }
    }

    // MARK: - The samples' file

    func samplesFile() -> String {
        var lines = ["import Foundation", "", "/// The answers the tests read, as the server sends them: each the JSON of its type's preview.", "enum Samples {"]
        for (index, sample) in samples.enumerated() {
            if index > 0 { lines.append("") }
            let hashes = String(repeating: "#", count: delimiterCount(sample.json))
            lines.append("    static let \(sample.name) = \(hashes)\"\"\"")
            lines += sample.json.split(separator: "\n", omittingEmptySubsequences: false).map { "    " + $0 }
            lines.append("    \"\"\"\(hashes)")
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// How many `#` a raw string of `text` needs.
    private func delimiterCount(_ text: String) -> Int {
        var count = 1
        while text.contains("\"" + String(repeating: "#", count: count)) || text.contains("\\" + String(repeating: "#", count: count)) { count += 1 }
        return count
    }

    // MARK: - The client's tests

    func clientTests() -> String {
        var lines = ["import Foundation", "import XCTest", "@testable import \(api.module)", "",
                     "/// What every request goes through: the base URL, the token's host, retries, errors, dates and forms.",
                     "final class \(api.client)Tests: XCTestCase {",
                     "    private struct Echo: Codable, Hashable {",
                     "        var value: String",
                     "    }",
                     ""]
        lines += """
            func testTheBaseURLChangesWhileTheAppRuns() async throws {
                let (client, transport) = Fixture.client()
                transport.enqueue(json: #"{"value": "one"}"#)
                transport.enqueue(json: #"{"value": "two"}"#)
                _ = try await client.send(Request<Echo>(.get, "/echo"))
                client.baseURL = URL(string: "https://another.example/v2")!
                let echo = try await client.send(Request<Echo>(.get, "/echo", query: ["q": "soup & bread+salt", "empty": nil]))
                XCTAssertEqual(echo.value, "two")
                XCTAssertEqual(transport.requests.map { $0.url?.host }, ["example.com", "another.example"])
                XCTAssertEqual(transport.lastRequest?.url?.path, "/v2/echo")
                XCTAssertEqual(transport.lastRequest?.queryItems, ["q": "soup & bread+salt"], "a + stays a + and & stays in the value")
                XCTAssertEqual(\(api.client).url(from: "kitchen.example/"), URL(string: "https://kitchen.example"))
            }

        """.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines += tokenTest()
        lines += """
            func testAThrottledRequestIsSentAgain() async throws {
                let (client, transport) = Fixture.client(retry: RetryPolicy(attempts: 3, delay: 0, maxDelay: 0))
                transport.enqueue(HTTPResponse(status: 429, headers: ["Retry-After": "0"]))
                transport.enqueue(HTTPResponse(status: 503))
                transport.enqueue(json: #"{"value": "at last"}"#)
                let echo = try await client.send(Request<Echo>(.get, "/echo"))
                XCTAssertEqual(echo.value, "at last")
                XCTAssertEqual(transport.requests.count, 3)
            }

            func testAPostIsNotSentAgainAfterAServerError() async throws {
                let (client, transport) = Fixture.client(retry: RetryPolicy(attempts: 3, delay: 0, maxDelay: 0))
                transport.enqueue(HTTPResponse(status: 500, body: Data(#"{"error": "the kitchen is closed"}"#.utf8)))
                do {
                    _ = try await client.send(Request<Echo>(.post, "/echo", body: .json(Echo(value: "soup"))))
                    XCTFail("a 500 is thrown")
                } catch \(api.error).status(let code, let message, _) {
                    XCTAssertEqual(code, 500)
                    XCTAssertEqual(message, "the kitchen is closed")
                }
                XCTAssertEqual(transport.requests.count, 1, "sending a POST twice could make two of it")
            }

            func testAnUnauthorizedAnswerSaysSo() async throws {
                let (client, transport) = Fixture.client()
                transport.enqueue(HTTPResponse(status: 401, body: Data(#"{"message": "the token expired"}"#.utf8)))
                do {
                    _ = try await client.send(Request<Echo>(.get, "/echo"))
                    XCTFail("a 401 is thrown")
                } catch \(api.error).unauthorized(let message) {
                    XCTAssertEqual(message, "the token expired")
                }
            }

            func testADecodingFailureSaysWhere() async throws {
                struct Listing: Decodable, Sendable {
                    struct Entry: Decodable, Sendable { var id: Int }
                    var entries: [Entry]
                }
                let (client, transport) = Fixture.client()
                transport.enqueue(json: #"{"entries": [{"id": 1}, {"id": "two"}]}"#)
                do {
                    _ = try await client.send(Request<Listing>(.get, "/listing"))
                    XCTFail("a value of the wrong type is thrown")
                } catch \(api.error).decoding(let type, let path, _) {
                    XCTAssertEqual(type, "Listing")
                    XCTAssertEqual(path, "entries[1].id")
                }
            }

        """.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines += datesTest()
        lines += """
            func testAFormHasAPartForEachField() throws {
                var form = Multipart(boundary: "B")
                form.add("title", "Soup")
                form.add("tags", ["hot", "quick"])
                form.add("photo", MultipartFile(data: Data("jpeg".utf8), filename: "soup.jpg"))
                let body = String(decoding: form.data, as: UTF8.self)
                XCTAssertEqual(form.contentType, "multipart/form-data; boundary=B")
                XCTAssertEqual(body.components(separatedBy: "--B\\r\\n").count - 1, 4)
                XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\\"photo\\"; filename=\\"soup.jpg\\"\\r\\nContent-Type: image/jpeg"))
                XCTAssertTrue(body.hasSuffix("--B--\\r\\n"))
            }

        """.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines += previewTest()
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    private var authScheme: AuthScheme {
        switch api.auth {
        case .none: return .none
        case .bearer: return .bearer
        case .basic: return .basic
        case .header: return .header(api.authName ?? "")
        case .query: return .query(api.authName ?? "")
        }
    }

    /// A stand-in of the generated `AuthScheme`, to say what a test expects.
    enum AuthScheme { case none, bearer, basic, header(String), query(String) }

    /// The header a signed-in request carries, and its value, for the fixture's token.
    private var authHeader: (name: String, value: String)? {
        switch authScheme {
        case .bearer: return ("Authorization", "Bearer test-token")
        case .basic: return ("Authorization", "Basic " + Data("test-token".utf8).base64EncodedString())
        case .header(let name): return (name, "test-token")
        case .none, .query: return nil
        }
    }

    private func tokenTest() -> [String] {
        var lines = ["    func testATokenGoesOnlyToTheHostItWasKeptFor() async throws {",
                     "        let (client, transport) = Fixture.client()",
                     "        transport.enqueue(json: #\"{\"value\": \"one\"}\"#)",
                     "        transport.enqueue(json: #\"{\"value\": \"two\"}\"#)",
                     "        _ = try await client.send(Request<Echo>(.get, \"/echo\"))"]
        switch authScheme {
        case .none:
            lines.append("        XCTAssertNil(transport.lastRequest?.value(forHTTPHeaderField: \"Authorization\"), \"a public API sends no token\")")
            lines.append("        XCTAssertFalse(client.isSignedIn)")
            lines += ["        _ = try await client.send(Request<Echo>(.get, \"/echo\"))", "        XCTAssertEqual(transport.requests.count, 2)"]
        case .query(let name):
            lines.append("        XCTAssertEqual(transport.lastRequest?.queryItems[\(Sample.quoted(name))], \"test-token\")")
            lines.append("        client.baseURL = URL(string: \"https://another.example\")!")
            lines.append("        _ = try await client.send(Request<Echo>(.get, \"/echo\"))")
            lines.append("        XCTAssertNil(transport.lastRequest?.queryItems[\(Sample.quoted(name))], \"another host's token stays home\")")
        default:
            let header = authHeader!
            lines.append("        XCTAssertEqual(transport.lastRequest?.value(forHTTPHeaderField: \(Sample.quoted(header.name))), \(Sample.quoted(header.value)))")
            lines.append("        client.baseURL = URL(string: \"https://another.example\")!")
            lines.append("        _ = try await client.send(Request<Echo>(.get, \"/echo\"))")
            lines.append("        XCTAssertNil(transport.lastRequest?.value(forHTTPHeaderField: \(Sample.quoted(header.name))), \"another host's token stays home\")")
        }
        if authScheme.isSigned {
            lines += ["        XCTAssertFalse(client.isSignedIn)",
                      "        try client.signIn(token: \"another-token\")",
                      "        XCTAssertEqual(client.token, \"another-token\")",
                      "        try client.signOut()",
                      "        XCTAssertNil(client.token)",
                      "        client.baseURL = Fixture.baseURL",
                      "        XCTAssertEqual(client.token, Fixture.token, \"the first host's token is still kept\")"]
        }
        lines += ["    }", ""]
        return lines
    }

    private func datesTest() -> [String] {
        var lines = ["    func testDatesReadInEveryFormTheAPIWrites() throws {",
                     "        struct Stamp: Decodable { var at: Date }",
                     "        let decoder = \(api.codingType).decoder()",
                     "        func read(_ json: String) throws -> Date { try decoder.decode(Stamp.self, from: Data(json.utf8)).at }",
                     "        let midnight = Date(timeIntervalSince1970: 1_767_225_600)",
                     "        XCTAssertEqual(try read(#\"{\"at\": \"2026-01-01T00:00:00Z\"}\"#), midnight)",
                     "        XCTAssertEqual(try read(#\"{\"at\": \"2026-01-01T02:00:00.000+02:00\"}\"#), midnight)",
                     "        XCTAssertEqual(try read(#\"{\"at\": \"2026-01-01T00:00:00\"}\"#), midnight, \"no zone is UTC\")",
                     "        XCTAssertEqual(try read(#\"{\"at\": \"2026-01-01T00:00:00.123456Z\"}\"#).timeIntervalSince1970, 1_767_225_600.123456, accuracy: 0.000_001)"]
        let numbers = DateFormats(api.dates)
        lines.append("        XCTAssertEqual(try read(#\"{\"at\": \(numbers.milliseconds ? "1767225600000" : "1767225600")}\"#), midnight)")
        for format in numbers.patterns {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            let text = formatter.string(from: Date(timeIntervalSince1970: 1_767_225_600))
            lines.append("        XCTAssertEqual(try read(#\"{\"at\": \(Sample.json(text))}\"#), midnight, \(Sample.quoted("written \(format)")))")
        }
        lines.append("        XCTAssertThrowsError(try read(#\"{\"at\": \"soon\"}\"#))")
        lines += ["    }", ""]
        return lines
    }

    private func previewTest() -> [String] {
        guard !api.methods.isEmpty || api.feeds else { return [] }
        var lines = ["    func testThePreviewAnswersEveryEndpoint() async throws {", "        let client = \(api.client).preview"]
        if api.feeds {
            lines.append("        let feed = try await client.feed(at: URL(string: \"https://example.com/feed.xml\")!)")
            lines.append("        XCTAssertEqual(feed.items.map(\\.title), [\"Sample title\"])")
        }
        for method in api.methods {
            let (call, _, _) = arguments(method)
            let invocation = "client.\(SwiftName.member(method.name))(\(call.joined(separator: ", ")))"
            lines += endpoints.wrapped(method.answer == .nothing ? "try await \(invocation)" : "_ = try await \(invocation)", indent: 8)
        }
        lines += ["    }", ""]
        return lines
    }

    // MARK: - Words

    /// `["a": "1", "b": "2"]`, or `[:]`.
    private func dictionary(_ pairs: [(String, String)]) -> String {
        pairs.isEmpty ? "[:]" : "[" + pairs.map { "\(Sample.quoted($0.0)): \(Sample.quoted($0.1))" }.joined(separator: ", ") + "]"
    }

    private func upper(_ name: String) -> String { name.prefix(1).uppercased() + name.dropFirst() }
    private func lowerFirst(_ name: String) -> String { name.prefix(1).lowercased() + name.dropFirst() }
}

extension TestEmitter.AuthScheme {
    /// Whether a request carries a token.
    var isSigned: Bool { if case .none = self { return false } else { return true } }
}
