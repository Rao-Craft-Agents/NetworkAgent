//  WHAT: The endpoint line, the one form a model writes an endpoint in:
//
//            GET /api/v3/post/list?page:Int,limit:Int,sort:SortType -> GetPostsResponse as posts paged
//            POST /api/v3/user/login body(Login) -> LoginResponse as login stores token "signs a person in"
//            GET /api/v1/accounts/{id}/statuses?limit:Int,max_id -> [Status] as Accounts.statuses paged
//            POST /api/v0/add?pin:Bool multipart(file) -> AddResult as add
//            DELETE /api/v1/statuses/{id}
//
//        A method, a path with `{name}` or `{name:Type}` parameters and a `?` query of `name` or `name:Type`
//        (String when the type is left out; optional unless it ends in `!`), then, in any order: `body(Type)` or
//        `multipart(part, …)`, `-> Type`, `as name` or `as Group.name`, `paged` or `paged(field)`, `stores token` or
//        `stores token(field)`, and a quoted doc last.
//  PIN:  A LINE THAT IS NOT UNDERSTOOD IS REFUSED WITH THE REASON, as an entity line is: a guess would send a request
//        the API does not take, and the turn would build it.

import Foundation

enum EndpointLine {
    static let methods: Set<String> = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD"]

    static func parse(_ line: String) throws -> Endpoint {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NetworkError.line(line, "it is empty") }
        var doc: String?
        if text.hasSuffix("\""), let open = lastQuotedStart(text) {
            doc = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            text = text[..<open].trimmingCharacters(in: .whitespaces)
        }
        var tokens = joinedTokens(LineSplit.top(text, on: " "))
        guard tokens.count >= 2 else {
            throw NetworkError.line(line, "an endpoint is `METHOD /path -> Type`, and this names no path")
        }
        let method = tokens.removeFirst().uppercased()
        guard methods.contains(method) else {
            throw NetworkError.line(line, "`\(method)` is not a method: GET, POST, PUT, PATCH, DELETE or HEAD")
        }
        let target = tokens.removeFirst()
        guard target.hasPrefix("/") else { throw NetworkError.line(line, "the path `\(target)` does not start with `/`") }
        let split = target.firstIndex(of: "?")
        let (path, pathParameters) = try parsePath(split.map { String(target[..<$0]) } ?? target, in: line)
        let query = try split.map { try parseQuery(String(target[target.index(after: $0)...]), in: line) } ?? []

        var endpoint = Endpoint(line: line, method: method, path: path, pathParameters: pathParameters, query: query,
                                body: nil, response: nil, group: nil, name: nil, paged: false, itemsField: nil,
                                storesToken: false, tokenField: nil, doc: doc)
        while !tokens.isEmpty {
            let token = tokens.removeFirst()
            if let inside = argument(of: "body", in: token) {
                guard endpoint.body == nil else { throw NetworkError.line(line, "it has two bodies; an endpoint sends one") }
                endpoint.body = .json(try EntityLine.parseType(inside, in: line))
            } else if let inside = argument(of: "multipart", in: token) {
                guard endpoint.body == nil else { throw NetworkError.line(line, "it has two bodies; an endpoint sends one") }
                endpoint.body = .multipart(try parseParts(inside, in: line))
            } else if token == "->" {
                guard let type = tokens.first else { throw NetworkError.line(line, "`->` names no type") }
                tokens.removeFirst()
                endpoint.response = try EntityLine.parseType(type, in: line)
            } else if token.hasPrefix("->") {
                endpoint.response = try EntityLine.parseType(String(token.dropFirst(2)), in: line)
            } else if token == "as" {
                guard let name = tokens.first else { throw NetworkError.line(line, "`as` names no method") }
                tokens.removeFirst()
                let parts = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
                if parts.count == 2 {
                    guard SwiftName.isTypeName(parts[0]) else {
                        throw NetworkError.line(line, "`\(parts[0])` in `as \(name)` is not a group name (UpperCamelCase)")
                    }
                    endpoint.group = parts[0]
                }
                guard parts.count <= 2, let method = parts.last, SwiftName.isMemberName(method) else {
                    throw NetworkError.line(line, "`as \(name)` is not a method name (lowerCamelCase), or `Group.name`")
                }
                endpoint.name = method
            } else if token == "paged" || argument(of: "paged", in: token) != nil {
                endpoint.paged = true
                if let field = argument(of: "paged", in: token) {
                    guard SwiftName.isMemberName(field) else { throw NetworkError.line(line, "`\(token)` names no field") }
                    endpoint.itemsField = field
                }
            } else if token == "stores" {
                guard let next = tokens.first, next == "token" || argument(of: "token", in: next) != nil else {
                    throw NetworkError.line(line, "`stores` is said `stores token` or `stores token(field)`")
                }
                tokens.removeFirst()
                endpoint.storesToken = true
                if let field = argument(of: "token", in: next) {
                    guard SwiftName.isMemberName(field) else { throw NetworkError.line(line, "`\(next)` names no field") }
                    endpoint.tokenField = field
                }
            } else {
                throw NetworkError.line(line, "`\(token)` is not part of an endpoint line: after the path come `body(Type)` or `multipart(field)`, `-> Type`, `as name`, `paged` and `stores token`")
            }
        }
        if endpoint.body != nil, method == "GET" || method == "HEAD" {
            throw NetworkError.line(line, "a \(method) sends no body; put what it takes in the query")
        }
        let names = endpoint.pathParameters.map(\.wire) + endpoint.query.map(\.wire)
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted {
            throw NetworkError.line(line, "the parameter `\(name)` is named twice")
        }
        return endpoint
    }

    /// `/api/v1/accounts/{id:Int}/statuses` → `/api/v1/accounts/{id}/statuses` and `id` an Int.
    static func parsePath(_ text: String, in line: String) throws -> (String, [Endpoint.Parameter]) {
        var path = "", parameters: [Endpoint.Parameter] = []
        var rest = Substring(text)
        func literal(_ piece: Substring) throws {
            guard !piece.contains("}"), !piece.contains(" ") else { throw NetworkError.line(line, "the path `\(text)` is not a path") }
            path += piece
        }
        while let open = rest.firstIndex(of: "{") {
            try literal(rest[..<open])
            guard let close = rest[open...].firstIndex(of: "}") else {
                throw NetworkError.line(line, "`{` in the path `\(text)` is never closed")
            }
            let inside = rest[rest.index(after: open)..<close]
            let pieces = inside.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard let name = pieces.first, isWireName(name), !name.contains("[") else {
                throw NetworkError.line(line, "`{\(inside)}` in the path is not `{name}` or `{name:Type}`")
            }
            let type = pieces.count == 2 ? try EntityLine.parseType(pieces[1], in: line) : .named("String")
            parameters.append(.init(wire: name, type: type, typed: pieces.count == 2, required: true))
            path += "{\(name)}"
            rest = rest[rest.index(after: close)...]
        }
        try literal(rest)
        return (path, parameters)
    }

    /// `page:Int,sort:SortType,q!,ids:[Int]`.
    static func parseQuery(_ text: String, in line: String) throws -> [Endpoint.Parameter] {
        try LineSplit.top(text, on: ",").map { piece in
            var item = piece
            var required = false
            if item.hasSuffix("!") { required = true; item.removeLast() }
            if item.hasSuffix("?") { item.removeLast() }
            var name: String, type: TypeRef
            let colon = LineSplit.firstTop(item, ":")
            if let colon {
                name = item[..<colon].trimmingCharacters(in: .whitespaces)
                type = try EntityLine.parseType(String(item[item.index(after: colon)...]), in: line)
            } else {
                name = item.trimmingCharacters(in: .whitespaces)
                type = .named("String")
            }
            // `id!:Int` reads as `id:Int!`: the mark may follow the name or the type.
            if name.hasSuffix("!") { required = true; name.removeLast() }
            guard isWireName(name) else { throw NetworkError.line(line, "`\(piece)` in the query is not `name`, `name:Type` or either with `!` (required)") }
            return .init(wire: name, type: type.unwrapped, typed: colon != nil, required: required)
        }
    }

    /// `file`, `photos:[File]`, `caption:String?`.
    static func parseParts(_ text: String, in line: String) throws -> [Endpoint.Part] {
        let parts = try LineSplit.top(text, on: ",").map { piece -> Endpoint.Part in
            var item = piece
            var optional = false
            if item.hasSuffix("?") { optional = true; item.removeLast() }
            guard let colon = LineSplit.firstTop(item, ":") else {
                guard isWireName(item) else { throw NetworkError.line(line, "`\(piece)` in multipart(…) is not a field name") }
                return .init(wire: item, kind: .file, required: !optional)
            }
            let name = item[..<colon].trimmingCharacters(in: .whitespaces)
            let typeText = item[item.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard isWireName(name) else { throw NetworkError.line(line, "`\(piece)` in multipart(…) is not a field name") }
            switch typeText {
            case "File": return .init(wire: name, kind: .file, required: !optional)
            case "[File]": return .init(wire: name, kind: .files, required: !optional)
            default: return .init(wire: name, kind: .value(try EntityLine.parseType(typeText, in: line).unwrapped), required: !optional)
            }
        }
        guard !parts.isEmpty else { throw NetworkError.line(line, "multipart() names no field: `multipart(file)`") }
        return parts
    }

    /// A name a URL or a form may carry: letters, digits, `_`, `-` and `.`, and `[]` at the end (`ids[]`).
    static func isWireName(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z_][A-Za-z0-9_.\-]*(\[\])?$"#, options: .regularExpression) != nil
    }

    /// `inside` when `token` is `word(inside)`.
    private static func argument(of word: String, in token: String) -> String? {
        guard token.hasPrefix(word + "("), token.hasSuffix(")") else { return nil }
        return String(token.dropFirst(word.count + 1).dropLast()).trimmingCharacters(in: .whitespaces)
    }

    /// Tokens put back together where a model spaced what is one: `?page:Int, limit:Int`, `body (Login)`.
    private static func joinedTokens(_ tokens: [String]) -> [String] {
        var joined: [String] = []
        for token in tokens {
            if let last = joined.last, last.hasSuffix(",") || last.hasSuffix(":") || (token.hasPrefix("(") && ["body", "multipart", "paged", "token"].contains(last)) {
                joined[joined.count - 1] = last + token
            } else {
                joined.append(token)
            }
        }
        return joined
    }

    /// Where the last quoted string in `text` begins, when `text` ends with its closing quote.
    private static func lastQuotedStart(_ text: String) -> String.Index? {
        guard text.hasSuffix("\""), text.count >= 2 else { return nil }
        var index = text.index(before: text.index(before: text.endIndex))
        while true {
            if text[index] == "\"" { return index }
            if index == text.startIndex { return nil }
            index = text.index(before: index)
        }
    }
}
