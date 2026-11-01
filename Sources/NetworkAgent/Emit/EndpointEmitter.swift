//  WHAT: The client's endpoints: one `extension <Stem>Client` a group, a typed `async throws` method a line,
//        doc-commented from the line; a `…Pages` helper for each paged endpoint; and the preview client that answers
//        every endpoint with its sample.
//  PIN:  A METHOD READS AS A CALL. The body comes first and unlabeled (`createPost(draft)`), then the path's
//        parameters, the form's fields and the query, each named in Swift (`communityID`) and sent under its wire name
//        (`community_id`); a query value left nil is left out of the URL.

import Foundation

struct EndpointEmitter {
    let api: API
    let models: ModelEmitter

    // MARK: - A group's file

    func emit(group: String) -> String {
        let methods = api.methods.filter { $0.group == group }
        var lines = ["import Foundation", "", "extension \(api.client) {"]
        for (index, method) in methods.enumerated() {
            if index > 0 { lines.append("") }
            lines += self.method(method)
            if method.paging != nil {
                lines.append("")
                lines += pages(method)
            }
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// One endpoint's method.
    func method(_ method: APIMethod) -> [String] {
        var lines = docs(method)
        let returns = returnType(method)
        if method.endpoint.method != "GET", returns != nil { lines.append("    @discardableResult") }
        lines += signature("public func \(SwiftName.member(method.name))", parameters(method),
                           suffix: "async throws" + (returns.map { " -> \($0)" } ?? ""))
        var body: [String] = []
        if !method.parts.isEmpty {
            body.append("var form = Multipart()")
            for part in method.parts {
                let name = SwiftName.member(part.name)
                switch (part.part.kind, part.part.required) {
                case (.files, _): body.append("for file in \(name) { form.add(\(Sample.quoted(part.part.wire)), file) }")
                case (_, true): body.append("form.add(\(Sample.quoted(part.part.wire)), \(name))")
                case (_, false): body.append("if let \(name) { form.add(\(Sample.quoted(part.part.wire)), \(name)) }")
                }
            }
        }
        let send = "send(\(request(method)))"
        switch (method.answer, method.token) {
        case (.nothing, _):
            body.append("_ = try await \(send)")
        case (_, .field(let field, let optional)?):
            body.append("let response = try await \(send)")
            body.append(optional ? "if let token = response.\(SwiftName.member(field)) { try signIn(token: token) }"
                                 : "try signIn(token: response.\(SwiftName.member(field)))")
            body.append("return response")
        case (_, .whole?):
            body.append("let response = try await \(send)")
            body.append("try signIn(token: response)")
            body.append("return response")
        default:
            body.append((body.isEmpty ? "" : "return ") + "try await \(send)")
        }
        lines += body.flatMap { wrapped($0, indent: 8) }
        lines.append("    }")
        return lines
    }

    /// The doc comment: the line's doc, then the endpoint as it is on the wire and what the method does beside it.
    private func docs(_ method: APIMethod) -> [String] {
        var lines: [String] = []
        if let doc = method.endpoint.doc, !doc.isEmpty {
            lines += Self.doc(sentence(doc)) + ["    ///"]
        }
        var wire = "`\(method.endpoint.signature)`"
        if method.token != nil { wire += ": keeps the token it answers for the client's host" }
        if method.paging != nil { wire += "; every page: `\(method.pagesName)(…)`" }
        return lines + Self.doc(wire + (method.token != nil || method.paging != nil ? "." : ""))
    }

    /// `text` as doc comment lines at four spaces, none past 120 columns.
    static func doc(_ text: String, indent: String = "    ") -> [String] {
        var lines: [String] = [], line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty, indent.count + 4 + line.count + 1 + word.count > 120 {
                lines.append("\(indent)/// \(line)")
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + word
        }
        lines.append("\(indent)/// \(line)")
        return lines
    }

    /// The Swift type the method answers; nil for nothing.
    func returnType(_ method: APIMethod) -> String? {
        switch method.answer {
        case .nothing: return nil
        case .json(let type): return type.description
        case .data: return "Data"
        case .text: return "String"
        }
    }

    /// `_ body: CreatePost`, `id: String`, `file: MultipartFile`, `page: Int? = nil`: the body, the path, the form,
    /// then the query.
    func parameters(_ method: APIMethod) -> [String] {
        var list: [String] = []
        if let body = method.body { list.append("_ body: \(body)") }
        for item in method.path { list.append("\(SwiftName.member(item.name)): \(item.type)") }
        for part in method.parts {
            let name = SwiftName.member(part.name)
            switch (part.part.kind, part.part.required) {
            case (.file, true): list.append("\(name): MultipartFile")
            case (.file, false): list.append("\(name): MultipartFile? = nil")
            case (.files, true): list.append("\(name): [MultipartFile]")
            case (.files, false): list.append("\(name): [MultipartFile] = []")
            case (.value(let type), true): list.append("\(name): \(type)")
            case (.value(let type), false): list.append("\(name): \(TypeRef.optional(type)) = nil")
            }
        }
        for item in method.query {
            list.append(item.required ? "\(SwiftName.member(item.name)): \(item.type)" : "\(SwiftName.member(item.name)): \(TypeRef.optional(item.type)) = nil")
        }
        return list
    }

    /// `Request<T>(.get, "/path", parameters: […], query: […], body: …)`, with how its answer is read when it is not JSON.
    /// `marker` replaces the value of the paged query argument (a closure's page or cursor).
    func request(_ method: APIMethod, marker: (wire: String, value: String)? = nil) -> String {
        let response: String
        var decode = ""
        switch method.answer {
        case .nothing: response = "NoContent"
        case .json(let type): response = type.description
        case .data: response = "Data"; decode = " { data, _ in data }"
        case .text: response = "String"; decode = " { data, _ in String(decoding: data, as: UTF8.self) }"
        }
        var arguments = [".\(method.endpoint.method.lowercased())", Sample.quoted(method.endpoint.path)]
        if !method.path.isEmpty {
            arguments.append("parameters: [" + method.path.map { "\(Sample.quoted($0.wire)): \(SwiftName.member($0.name))" }.joined(separator: ", ") + "]")
        }
        if !method.query.isEmpty {
            let entries = method.query.map { item -> String in
                let value = marker?.wire == item.wire ? marker!.value : SwiftName.member(item.name)
                return "\(Sample.quoted(item.wire)): \(value)"
            }
            arguments.append("query: [" + entries.joined(separator: ", ") + "]")
        }
        if method.body != nil { arguments.append("body: .json(body)") }
        if !method.parts.isEmpty { arguments.append("body: .multipart(form)") }
        return "Request<\(response)>(" + arguments.joined(separator: ", ") + ")" + decode
    }

    // MARK: - Every page

    /// `postsPages(from:…)`: the endpoint's pages, as an `AsyncSequence`.
    func pages(_ method: APIMethod) -> [String] {
        guard let paging = method.paging else { return [] }
        let item = paging.item.description
        let others = parameters(method).filter { !$0.hasPrefix(SwiftName.member(paging.marker.name) + ":") }
        let taken = Set(method.path.map(\.name) + method.query.filter { $0.wire != paging.marker.wire }.map(\.name)
                        + method.parts.map(\.name) + ["body"])
        let byNumber = paging.next == .number
        let start = [byNumber ? "page" : "cursor", "start", "first"].first { !taken.contains($0) } ?? "start"
        let startParameter = byNumber ? "from \(start): Int = 1" : "from \(start): String? = nil"
        let closureArgument = byNumber ? "number" : "cursor"

        let limit = paging.limit.map { "`\(SwiftName.member($0.name))`" }
        var lines = Self.doc(byNumber
            ? "Every page of `\(method.name)(…)`, from page `\(start)` on, one request a page: an empty page\(limit.map { ", or one shorter than \($0)," } ?? "") ends it."
            : "Every page of `\(method.name)(…)`, one request a page: the next cursor comes from \(nextSource(paging)); an empty page ends it.")
        lines += signature("public func \(method.pagesName)", [startParameter] + others, suffix: "-> Pages<\(item)>")
        lines.append("        Pages(from: \(start)) { [self] \(closureArgument) in")

        // The call of one page.
        let call: String
        var arguments: [String] = []
        if method.body != nil { arguments.append("body") }
        for argument in method.path { arguments.append("\(SwiftName.member(argument.name)): \(SwiftName.member(argument.name))") }
        for part in method.parts { arguments.append("\(SwiftName.member(part.name)): \(SwiftName.member(part.name))") }
        for argument in method.query {
            let value = argument.wire == paging.marker.wire ? closureArgument : SwiftName.member(argument.name)
            arguments.append("\(SwiftName.member(argument.name)): \(value)")
        }
        let itemsOf: (String) -> String = { value in
            guard let field = paging.itemsField else { return value }
            return "\(value).\(SwiftName.member(field))" + (paging.itemsOptional ? " ?? []" : "")
        }
        var body: [String] = []
        switch paging.next {
        case .number:
            call = "try await \(SwiftName.member(method.name))(\(arguments.joined(separator: ", ")))"
            if paging.itemsField == nil {
                body.append("let items = \(call)")
            } else {
                body.append("let response = \(call)")
                body.append("let items = \(itemsOf("response"))")
            }
            var last = "items.isEmpty"
            if let limit = paging.limit {
                let name = SwiftName.member(limit.name)
                last += limit.required ? " || items.count < \(name)" : " || \(name).map { items.count < $0 } == true"
            }
            body.append("let last = \(last)")
            body.append("return Page(items: items, number: number, next: last ? nil : number + 1)")
        case .field(let field, let type):
            call = "try await \(SwiftName.member(method.name))(\(arguments.joined(separator: ", ")))"
            body.append("let response = \(call)")
            let value = "response.\(SwiftName.member(field))"
            let next: String
            switch (type.unwrapped == .named("Int"), type.isOptional) {
            case (true, true): next = "\(value).map(String.init)"
            case (true, false): next = "String(\(value))"
            default: next = value
            }
            body.append("return Page(items: \(itemsOf("response")), cursor: cursor, next: \(next))")
        case .link:
            call = "try await exchange(request)"
            if !method.parts.isEmpty {
                body.append("var form = Multipart()")
                for part in method.parts {
                    let name = SwiftName.member(part.name)
                    switch (part.part.kind, part.part.required) {
                    case (.files, _): body.append("for file in \(name) { form.add(\(Sample.quoted(part.part.wire)), file) }")
                    case (_, true): body.append("form.add(\(Sample.quoted(part.part.wire)), \(name))")
                    case (_, false): body.append("if let \(name) { form.add(\(Sample.quoted(part.part.wire)), \(name)) }")
                    }
                }
            }
            body.append("let request = \(request(method, marker: (paging.marker.wire, "cursor")))")
            body.append("let (value, response) = \(call)")
            body.append("let next = LinkHeader.value(response.header(\"Link\"), parameter: \(Sample.quoted(paging.marker.wire)))")
            body.append("return Page(items: \(itemsOf("value")), cursor: cursor, next: next)")
        }
        lines += body.flatMap { wrapped($0, indent: 12) }
        lines += ["        }", "    }"]
        return lines
    }

    private func nextSource(_ paging: APIMethod.Paging) -> String {
        switch paging.next {
        case .number: return "the page number"
        case .field(let field, _): return "the response's `\(field)`"
        case .link: return "the `Link` header's `rel=\"next\"`"
        }
    }

    // MARK: - The preview client

    func preview() -> String {
        var lines = ["import Foundation", "", "extension \(api.client) {",
                     "    /// A client that answers every endpoint with its sample and sends nothing: for SwiftUI previews. A paged",
                     "    /// endpoint answers every page with the same sample.",
                     "    ///",
                     "    /// ```swift",
                     "    /// #Preview { RecipeList(client: .preview) }",
                     "    /// ```",
                     "    public static var preview: \(api.client) {",
                     "        let transport = MockTransport()"]
        if api.feeds {
            // First, so an endpoint's own route, added after, answers before it.
            lines.append("        transport.route(.get, \"*\", HTTPResponse(headers: [\"Content-Type\": \"application/rss+xml\"], body: Data(previewFeed.utf8)))")
        }
        for method in api.methods {
            let verb = ".\(method.endpoint.method.lowercased())", path = Sample.quoted(method.endpoint.path)
            switch method.answer {
            case .nothing:
                lines.append("        transport.route(\(verb), \(path), HTTPResponse(status: 204))")
            case .data:
                lines.append("        transport.route(\(verb), \(path), HTTPResponse(body: Data(\"Sample bytes\".utf8)))")
            case .text:
                lines.append("        transport.route(\(verb), \(path), HTTPResponse(body: Data(\(Sample.quoted(textSample(method))).utf8)))")
            case .json(let type):
                guard let sample = models.sample(type, field: "response", owner: "") else { continue }
                lines += wrapped("try? transport.route(\(verb), \(path), value: \(sample.swift))", indent: 8)
            }
        }
        let tokens = api.auth == .none ? "MemoryTokenStore()" : "MemoryTokenStore([\"example.com\": \"preview-token\"])"
        lines += wrapped("return \(api.client)(baseURL: URL(string: \"https://example.com\")!, tokens: \(tokens), transport: transport, retry: .never)", indent: 8)
        lines.append("    }")
        if api.feeds {
            lines += ["", "    /// The feed the preview client answers `feed(at:)` with.", "    static let previewFeed = \"\"\"",
                      "        <?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                      "        <rss version=\"2.0\">",
                      "          <channel>",
                      "            <title>Sample feed</title>",
                      "            <link>https://example.com</link>",
                      "            <description>Sample summary</description>",
                      "            <item>",
                      "              <title>Sample title</title>",
                      "              <link>https://example.com/1</link>",
                      "              <description>Sample summary</description>",
                      "              <pubDate>Thu, 01 Jan 2026 00:00:00 GMT</pubDate>",
                      "            </item>",
                      "          </channel>",
                      "        </rss>",
                      "        \"\"\""]
        }
        lines.append("}")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The text a text endpoint's sample answers: a token when it stores one.
    func textSample(_ method: APIMethod) -> String {
        method.token == nil ? "Sample text" : "Sample token"
    }

    // MARK: - Lines

    /// `head(p1, p2) suffix {` on one line, or one parameter a line when that is too long.
    private func signature(_ head: String, _ parameters: [String], suffix: String) -> [String] {
        let line = "    \(head)(\(parameters.joined(separator: ", "))) \(suffix) {"
        guard line.count > 120, !parameters.isEmpty else { return [line] }
        return ["    \(head)("] + parameters.enumerated().map { index, parameter in
            "        \(parameter)" + (index < parameters.count - 1 ? "," : "")
        } + ["    ) \(suffix) {"]
    }

    /// A statement at `indent`, its dictionary literals broken one entry a line when it is too long.
    func wrapped(_ statement: String, indent: Int) -> [String] {
        let pad = String(repeating: " ", count: indent)
        guard pad.count + statement.count > 120, let open = statement.range(of: "query: [") ?? statement.range(of: "parameters: [") else {
            return [pad + statement]
        }
        // The dictionary that opens at `open`, to its matching bracket.
        var depth = 1, index = open.upperBound, quoted = false
        while index < statement.endIndex, depth > 0 {
            let character = statement[index]
            if character == "\"" { quoted.toggle() }
            if !quoted { if character == "[" { depth += 1 } else if character == "]" { depth -= 1 } }
            if depth > 0 { index = statement.index(after: index) }
        }
        guard index < statement.endIndex else { return [pad + statement] }
        let inside = String(statement[open.upperBound..<index])
        let entries = LineSplit.top(inside, on: ",")
        guard entries.count > 1 else { return [pad + statement] }
        return [pad + statement[..<open.upperBound]] + entries.map { "\(pad)    \($0)," } + [pad + statement[index...]]
    }

    private func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        let capped = first.uppercased() + text.dropFirst()
        return capped.hasSuffix(".") ? capped : capped + "."
    }
}
