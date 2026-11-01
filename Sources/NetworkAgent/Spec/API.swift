//  WHAT: The package a call describes, resolved from its lines: the names it is written under, the auth, the paging,
//        the coding, the types, and every endpoint as a method with Swift names and types.
//  PIN:  EVERY PROBLEM AT ONCE. A call the agent cannot honour is refused with one sentence a problem, all of them,
//        so a model fixes the call in one go; nothing is written until there are none.
//  PIN:  THE PACKAGE BUILDS ON ITS OWN. Every type a line names is a primitive or a type an entity line declares; a
//        name the package would not know is refused here, not left for the turn's build to find.

import Foundation

struct API: Sendable {
    /// The call's fields, merged with what an earlier call kept (`APIRecord`).
    struct Call: Sendable {
        var name: String?
        var baseURL: String?
        var auth: NetworkAuth?
        var authName: String?
        var paging: NetworkPaging?
        var feeds: Bool?
        var coding: NetworkCoding?
        var dates: [String]?
        var endpoints: [String]
        var entities: [String]
    }

    /// The package, the library and the module: `RecipeKit`.
    var module: String
    /// What the package's types are named by: `Recipe` (`RecipeClient`, `RecipeError`).
    var stem: String
    var baseURL: String?
    var auth: NetworkAuth
    var authName: String?
    var paging: NetworkPaging
    var feeds: Bool
    var coding: NetworkCoding
    var dates: [String]
    var entities: [Entity]
    var methods: [APIMethod]
    /// Each group's file name (`Posts` → `Posts`, or `PostEndpoints` when a type has the name).
    var groupFiles: [String: String]

    var client: String { stem + "Client" }
    var error: String { stem + "Error" }
    var codingType: String { stem + "Coding" }

    func entity(_ name: String) -> Entity? { entities.first { $0.name == name } }

    /// The groups, in the order their first endpoint was given.
    var groups: [String] {
        var seen: Set<String> = []
        return methods.map(\.group).filter { seen.insert($0).inserted }
    }

    // MARK: - Words the package keeps for itself

    static let primitives: Set<String> = ["String", "Int", "Int64", "Int32", "Int16", "Int8", "UInt", "UInt64", "UInt32",
                                          "UInt16", "UInt8", "Double", "Float", "Bool", "Date", "URL", "UUID", "Decimal", "Data"]
    /// What a URL can carry: a query or path value, a form field.
    static let urlValues: Set<String> = primitives.subtracting(["Data"])
    /// Names Swift and Foundation already give a meaning that the package's code relies on.
    static let foundationNames: Set<String> = Set(["Error", "Result", "Task", "Never", "Void", "Optional", "Array", "Dictionary",
                                               "Set", "Sendable", "Codable", "Decodable", "Encodable", "Hashable", "Identifiable",
                                               "Equatable", "Comparable", "Character", "Substring", "Any", "AnyObject", "Self",
                                               "Type", "Protocol", "JSONDecoder", "JSONEncoder", "URLRequest", "URLSession",
                                               "URLQueryItem", "URLComponents", "URLError", "URLResponse", "HTTPURLResponse",
                                               "Locale", "TimeZone", "Calendar", "DateFormatter", "CharacterSet", "TimeInterval",
                                               "Bundle", "Foundation", "CodingKey", "Decoder", "Encoder", "AsyncSequence",
                                               "AsyncIteratorProtocol", "KeyValuePairs", "CancellationError", "DecodingError",
                                               "EncodingError", "LocalizedError", "OSAllocatedUnfairLock", "UTType"])
            .union(primitives)

    /// The support types every package declares, by file name, besides the client's own.
    static let supportTypes = ["HTTPMethod", "Request", "RequestBody", "QueryValue", "Multipart", "MultipartFile", "NoContent",
                               "HTTPTransport", "HTTPResponse", "URLSessionTransport", "MockTransport", "AuthScheme",
                               "TokenStore", "KeychainTokenStore", "MemoryTokenStore", "RetryPolicy", "DateParsing", "Indirect"]
    static let pagingTypes = ["Page", "Pages", "LinkHeader"]
    static let feedTypes = ["Feed", "FeedItem", "FeedParser", "FeedXMLReader", "JSONFeedDocument"]

    /// The client's own methods, by their full names: an endpoint may share a base name (`signIn(_:)` beside
    /// `signIn(token:)`), never a full one.
    static let clientMethods: Set<String> = ["send(_:)", "exchange(_:)", "urlRequest(for:)", "withBaseURL(_:)", "signIn(token:)",
                                             "signIn(user:password:)", "signOut()", "url(from:)", "hostKey(_:)", "encoded(_:)",
                                             "init()"]
    /// The client's properties: a method that takes nothing may not share their names.
    static let clientProperties: Set<String> = ["baseURL", "headers", "auth", "tokens", "transport", "retry", "decoder", "encoder",
                                                "token", "isSignedIn", "defaultBaseURL", "preview", "state"]

    /// The names of support types this package writes.
    var supportTypes: [String] {
        Self.supportTypes + (paging == .none ? [] : Self.pagingTypes) + (feeds ? Self.feedTypes : [])
            + [client, error, codingType]
    }

    // MARK: - Resolving

    static func resolve(_ call: Call) throws -> API {
        var reasons: [String] = []

        let module = call.name?.trimmingCharacters(in: .whitespaces) ?? "API"
        if !SwiftName.isTypeName(module) || foundationNames.contains(module) {
            reasons.append("`\(module)` is not a package name: one UpperCamelCase word, like `RecipeKit`")
        }
        let stem = Self.stem(of: module)
        if stem + "Client" == module {
            reasons.append("the package `\(module)` would share its name with its client type; name it `\(stem)` or `\(stem)Kit`")
        }

        var baseURL: String?
        if let text = call.baseURL?.trimmingCharacters(in: .whitespaces), !text.isEmpty {
            if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), url.host != nil,
               url.query == nil, url.fragment == nil {
                baseURL = text.hasSuffix("/") ? String(text.dropLast()) : text
            } else {
                reasons.append("`\(text)` is not a base URL: a scheme and a host, like `https://api.example.com`")
            }
        }

        var entities: [Entity] = []
        for line in call.entities where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do { entities.append(try EntityLine.parse(line)) } catch { reasons.append("\(error)") }
        }
        var endpoints: [Endpoint] = []
        for line in call.endpoints where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do { endpoints.append(try EndpointLine.parse(line)) } catch { reasons.append("\(error)") }
        }

        let feeds = call.feeds ?? false
        let coding = call.coding ?? .exact
        let dates = (call.dates ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        // The auth: a login that stores a token means a bearer token unless the call says otherwise.
        let auth = call.auth ?? (endpoints.contains(where: \.storesToken) ? .bearer : .none)
        var authName = call.authName?.trimmingCharacters(in: .whitespaces)
        if authName?.isEmpty == true { authName = nil }
        switch auth {
        case .header, .query:
            if let name = authName {
                if !EndpointLine.isWireName(name) { reasons.append("`\(name)` is not a \(auth == .header ? "header" : "query") name for `authName`") }
            } else {
                reasons.append("`auth: \(auth.rawValue)` needs `authName`, the \(auth == .header ? "header's name (`X-API-Key`)" : "query parameter's name (`api_key`)")")
            }
        case .none:
            for endpoint in endpoints where endpoint.storesToken {
                reasons.append("`\(endpoint.signature)` stores a token, and `auth` is none: say `auth: bearer` (or how the token is sent)")
            }
        case .bearer, .basic:
            break
        }

        // The paging: what the paged endpoints take, when the call does not say.
        let paged = endpoints.filter(\.paged)
        let paging: NetworkPaging = call.paging ?? {
            if paged.isEmpty { return .none }
            if paged.contains(where: { $0.query.contains { isPageName($0.wire) } }) { return .page }
            if paged.contains(where: { $0.query.contains { isCursorName($0.wire) } }) { return .cursor }
            return .none
        }()
        if paging == .none {
            for endpoint in paged {
                reasons.append("`\(endpoint.signature)` is paged, and the call has no paging: say `paging: page` (a `page` number in the query) or `paging: cursor`")
            }
        }

        // Types: every entity unique, none taking a name the package or Swift keeps.
        var reserved = Set(Self.supportTypes + [stem + "Client", stem + "Error", stem + "Coding", module])
        if paging != .none { reserved.formUnion(Self.pagingTypes) }
        if feeds { reserved.formUnion(Self.feedTypes) }
        var seen: Set<String> = []
        for entity in entities {
            if !seen.insert(entity.name).inserted { reasons.append("`\(entity.name)` is written twice") }
            if reserved.contains(entity.name) || foundationNames.contains(entity.name) {
                reasons.append("`\(entity.name)` is a name the package keeps for its own \(foundationNames.contains(entity.name) ? "use of Swift's type" : "type"); name the entity something else, like `\(stem)\(entity.name)`")
            }
        }
        for cycle in ModelEmitter(entities: entities, coding: coding).requiredCycles() {
            reasons.append("\(cycle.map { "`\($0)`" }.joined(separator: " and ")) each need the other to be made: make one of the fields optional (`?`) or a list")
        }
        let known = Set(entities.map(\.name))
        for entity in entities {
            let mentioned = entity.fields.flatMap(\.type.names) + entity.cases.flatMap { $0.values.flatMap(\.type.names) }
            for name in Set(mentioned) where !known.contains(name) && !primitives.contains(name) {
                reasons.append("`\(entity.name)` names `\(name)`, which no entity line declares: add its line")
            }
        }

        let api = API(module: module, stem: stem, baseURL: baseURL, auth: auth, authName: authName, paging: paging, feeds: feeds,
                      coding: coding, dates: dates, entities: entities, methods: [], groupFiles: [:])
        var methods: [APIMethod] = []
        for endpoint in endpoints {
            let (method, problems) = api.method(for: endpoint)
            reasons += problems
            if let method { methods.append(method) }
        }

        // One endpoint a method and path.
        var signatures: Set<String> = []
        for endpoint in endpoints where !signatures.insert(endpoint.signature).inserted {
            reasons.append("`\(endpoint.signature)` is written twice: one line an endpoint")
        }

        // Names: one method a name, none the full name of the client's own.
        var names: [String: String] = [:]
        var members = clientMethods
        if feeds { members.insert("feed(at:)") }
        for method in methods {
            let fullNames = [method.fullName] + (method.paging == nil ? [] : [method.pagesFullName])
            for (name, fullName) in zip([method.name, method.pagesName], fullNames) {
                if members.contains(fullName) || (fullName.hasSuffix("()") && clientProperties.contains(name)) {
                    reasons.append("`\(method.endpoint.signature)` is `\(fullName)`, which the client keeps for itself: give it another `as name`")
                } else if let other = names[name] {
                    reasons.append("`\(method.endpoint.signature)` and `\(other)` are both named `\(name)`: give one of them `as name`")
                }
                names[name] = method.endpoint.signature
            }
        }
        if endpoints.isEmpty, entities.isEmpty, !feeds, reasons.isEmpty { throw NetworkError.nothing }
        guard reasons.isEmpty else { throw NetworkError.refused(reasons) }

        var resolved = api
        resolved.methods = methods
        resolved.groupFiles = resolved.fileNames(for: resolved.groups)
        return resolved
    }

    /// `RecipeKit` → `Recipe`, `MastodonAPI` → `Mastodon`, `Lemmy` → `Lemmy`.
    static func stem(of module: String) -> String {
        for suffix in ["Kit", "API", "SDK", "Client"] where module.hasSuffix(suffix) && module.count > suffix.count {
            let stem = String(module.dropLast(suffix.count))
            if SwiftName.isTypeName(stem) { return stem }
        }
        return module
    }

    static func isPageName(_ wire: String) -> Bool { ["page", "pagenumber", "pageno"].contains(SwiftName.normalized(wire)) }

    static func isCursorName(_ wire: String) -> Bool {
        ["cursor", "pagecursor", "maxid", "after", "pagetoken", "nextpagetoken", "nexttoken", "continuation",
         "continuationtoken", "nextcursor", "next", "startcursor", "startafter"].contains(SwiftName.normalized(wire))
    }

    /// Untyped query names that count, read as Int.
    static func isCountName(_ wire: String) -> Bool {
        ["page", "pagenumber", "pageno", "limit", "perpage", "pagesize", "offset", "count", "size"].contains(SwiftName.normalized(wire))
    }

    static let nextFieldNames = ["nextpage", "nextcursor", "nextpagecursor", "cursor", "next", "nextpagetoken", "nexttoken",
                                 "pagetoken", "after", "endcursor", "continuation", "continuationtoken"]
    static let tokenFieldNames = ["token", "accesstoken", "jwt", "authtoken", "sessiontoken", "idtoken", "bearertoken",
                                  "apitoken", "apikey", "key"]

    // MARK: - One endpoint

    /// The method `endpoint` is, or the reasons it cannot be.
    func method(for endpoint: Endpoint) -> (APIMethod?, [String]) {
        var reasons: [String] = []
        let where_ = "`\(endpoint.signature)`"
        func check(_ type: TypeRef, _ role: String) {
            for name in type.names where !Self.primitives.contains(name) && entity(name) == nil {
                reasons.append("\(where_) \(role) `\(name)`, which no entity line declares: add its line")
            }
        }
        func urlValue(_ type: TypeRef, array: Bool) -> Bool {
            if case .array(let element) = type { return array && urlValue(element, array: false) }
            guard case .named(let name) = type else { return false }
            if Self.urlValues.contains(name) { return true }
            if let entity = entity(name), entity.isEnum, !entity.cases.contains(where: { !$0.values.isEmpty }) { return true }
            return false
        }
        func argument(_ parameter: Endpoint.Parameter) -> APIMethod.Argument {
            var type = parameter.type
            if !parameter.typed, Self.isCountName(parameter.wire) { type = .named("Int") }
            return .init(wire: parameter.wire, name: SwiftName.camel(parameter.wire), type: type, required: parameter.required)
        }

        let path = endpoint.pathParameters.map(argument)
        let query = endpoint.query.map(argument)
        for item in path where !urlValue(item.type, array: false) {
            reasons.append("\(where_): the path parameter `\(item.wire)` is `\(item.type)`, which a path cannot carry: a String, a number, a UUID or an enum")
        }
        for item in query where !urlValue(item.type, array: true) {
            reasons.append("\(where_): the query parameter `\(item.wire)` is `\(item.type)`, which a URL cannot carry: a String, a number, a Bool, a Date, a UUID, an enum, or an array of one")
        }

        var body: TypeRef?
        var parts: [APIMethod.Part] = []
        switch endpoint.body {
        case .json(let type)?:
            check(type, "sends a body of")
            body = type
        case .multipart(let items)?:
            for item in items {
                if case .value(let type) = item.kind, !urlValue(type, array: true) {
                    reasons.append("\(where_): the form field `\(item.wire)` is `\(type)`, which a form cannot carry as text; a file is `File`")
                }
                parts.append(.init(part: item, name: SwiftName.camel(item.wire)))
            }
        case nil:
            break
        }

        let answer: APIMethod.Answer
        switch endpoint.response {
        case nil: answer = .nothing
        case .named("Data")?: answer = .data
        case .named("String")?: answer = .text
        case let type?:
            check(type, "answers")
            answer = .json(type)
        }

        // Swift names: unique among the method's arguments.
        var argumentNames: [String: String] = [:]
        for name in path.map(\.name) + query.map(\.name) + parts.map(\.name) + (body == nil ? [] : ["body"]) {
            if argumentNames[name] != nil { reasons.append("\(where_) has two parameters that are both `\(name)` in Swift") }
            argumentNames[name] = name
        }

        let name = endpoint.name ?? Self.defaultName(endpoint)
        let group = endpoint.group ?? Self.defaultGroup(endpoint.path)

        // Paging.
        var pagingPlan: APIMethod.Paging?
        if endpoint.paged, paging != .none {
            let items = itemsOf(endpoint, answer: answer, reasons: &reasons)
            let limit = query.first { ["limit", "perpage", "pagesize", "count"].contains(SwiftName.normalized($0.wire)) && $0.type == .named("Int") }
            if paging == .page {
                if let marker = query.first(where: { Self.isPageName($0.wire) }) {
                    if marker.type != .named("Int") {
                        reasons.append("\(where_): the page parameter `\(marker.wire)` is `\(marker.type)`; a page number is an Int")
                    } else if let items {
                        pagingPlan = .init(item: items.item, itemsField: items.field, itemsOptional: items.optional, marker: marker, next: .number, limit: limit)
                    }
                } else {
                    reasons.append("\(where_) is paged by page number, and its query has no `page`: add `page:Int` to it")
                }
            } else if let marker = query.first(where: { Self.isCursorName($0.wire) }) {
                if marker.required {
                    reasons.append("\(where_): the cursor `\(marker.wire)` is left out for the first page, so it cannot end in `!`")
                } else if marker.type != .named("String") {
                    reasons.append("\(where_): the cursor `\(marker.wire)` is `\(marker.type)`; a cursor is a String")
                } else if let items {
                    var next = APIMethod.Next.link
                    if case .json(.named(let type)) = answer, let entity = entity(type),
                       let field = entity.fields.first(where: { Self.nextFieldNames.contains(SwiftName.normalized($0.name)) }) {
                        if [.named("String"), .named("Int")].contains(field.type.unwrapped) {
                            next = .field(field.name, field.type)
                        } else {
                            reasons.append("\(where_): `\(type).\(field.name)` holds the next cursor as `\(field.type)`; a cursor is a String or an Int")
                        }
                    }
                    pagingPlan = .init(item: items.item, itemsField: items.field, itemsOptional: items.optional, marker: marker, next: next, limit: limit)
                }
            } else {
                reasons.append("\(where_) is paged by cursor, and its query has no cursor: add one named `cursor`, `page_cursor`, `max_id`, `after` or `page_token`")
            }
        }

        // The token a login keeps.
        var token: APIMethod.Token?
        if endpoint.storesToken {
            switch answer {
            case .text:
                token = .whole
            case .json(.named(let type)):
                if let entity = entity(type) {
                    let field = endpoint.tokenField.flatMap { name in entity.fields.first { $0.name == name } }
                        ?? (endpoint.tokenField == nil ? entity.fields.first { Self.tokenFieldNames.contains(SwiftName.normalized($0.name)) } : nil)
                    if let field, field.type.unwrapped == .named("String") {
                        token = .field(field.name, optional: field.type.isOptional)
                    } else if let field {
                        reasons.append("\(where_) stores the token in `\(type).\(field.name)`, which is `\(field.type)`; a token is a String")
                    } else if let named = endpoint.tokenField {
                        reasons.append("\(where_) stores the token in `\(named)`, which `\(type)` does not have")
                    } else {
                        reasons.append("\(where_) stores a token, and `\(type)` has no field named like one (`token`, `accessToken`, `jwt`): say which, `stores token(field)`")
                    }
                }
            default:
                reasons.append("\(where_) stores a token, and answers no type to read it from: `-> LoginResponse` or `-> String`")
            }
        }

        guard reasons.isEmpty else { return (nil, reasons) }
        return (APIMethod(endpoint: endpoint, name: name, group: group, path: path, query: query, body: body, parts: parts,
                          answer: answer, paging: pagingPlan, token: token), [])
    }

    /// The type of one item of a paged endpoint and the field that holds them.
    private func itemsOf(_ endpoint: Endpoint, answer: APIMethod.Answer, reasons: inout [String]) -> (item: TypeRef, field: String?, optional: Bool)? {
        let where_ = "`\(endpoint.signature)`"
        guard case .json(let type) = answer else {
            reasons.append("\(where_) is paged, and answers no JSON to read the items from")
            return nil
        }
        if case .array(let element) = type { return (element, nil, false) }
        guard case .named(let name) = type, let entity = entity(name), !entity.isEnum else {
            reasons.append("\(where_) is paged, and `\(type)` holds no list of items")
            return nil
        }
        func element(of field: Field) -> TypeRef? {
            if case .array(let element) = field.type.unwrapped { return element }
            return nil
        }
        if let named = endpoint.itemsField {
            guard let field = entity.fields.first(where: { $0.name == named }), let item = element(of: field) else {
                reasons.append("\(where_) pages `\(named)`, which is not a list `\(name)` has")
                return nil
            }
            return (item, field.name, field.type.isOptional)
        }
        let lists = entity.fields.filter { element(of: $0) != nil }
        guard lists.count == 1, let field = lists.first, let item = element(of: field) else {
            reasons.append(lists.isEmpty
                ? "\(where_) is paged, and `\(name)` has no list of items"
                : "\(where_) is paged, and `\(name)` has \(lists.count) lists (\(lists.map(\.name).joined(separator: ", "))): say which holds the items, `paged(field)`")
            return nil
        }
        return (item, field.name, field.type.isOptional)
    }

    /// The path's segments after an `api` and a version: `/api/v3/post/list` → `post`, `list`.
    static func resourceSegments(_ path: String) -> [String] {
        var segments = path.split(separator: "/").map(String.init).filter { !$0.hasPrefix("{") }
        while let first = segments.first,
              first.lowercased() == "api" || first.range(of: #"^[vV]\d+(\.\d+)?$"#, options: .regularExpression) != nil {
            segments.removeFirst()
        }
        return segments.filter { EndpointLine.isWireName($0) }
    }

    /// `GET /api/v3/post/list` → `postList`; `DELETE /api/v1/statuses/{id}` → `deleteStatuses`.
    static func defaultName(_ endpoint: Endpoint) -> String {
        let words = resourceSegments(endpoint.path)
        let joined = words.map(SwiftName.upperCamel).joined()
        if endpoint.method == "GET" {
            return joined.isEmpty ? "root" : joined.prefix(1).lowercased() + joined.dropFirst()
        }
        return endpoint.method.lowercased() + joined
    }

    /// `/api/v3/post/list` → `Post`; a path with no resource → `General`.
    static func defaultGroup(_ path: String) -> String {
        resourceSegments(path).first.map(SwiftName.upperCamel) ?? "General"
    }

    /// A file name for each group that no other file of the package has: the group's name, else its plural, else
    /// the name and `Endpoints`.
    func fileNames(for groups: [String]) -> [String: String] {
        var taken = Set(supportTypes + entities.map(\.name) + [client + "+Preview", client + "+Feed", "Package"])
        var files: [String: String] = [:]
        for group in groups {
            let plural = SwiftName.plural(group)
            let name = [group, plural, group + "Endpoints"].first { !taken.contains($0) } ?? group + "Endpoints2"
            taken.insert(name)
            files[group] = name
        }
        return files
    }
}
