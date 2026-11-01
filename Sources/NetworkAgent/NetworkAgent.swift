//  WHAT: An app's backend API layer, as a Granite agent package. A call gives one line an endpoint
//        (`GET /v1/recipes/{id:Int} -> Recipe as recipe`) and one line a type (ModelsAgent's line); the run writes a
//        local Swift package, the typed client of that API (transport, auth, requests, endpoints, models, paging,
//        errors and retries, feeds, tests), links it into the project, and answers where.
//  IN:   Input: the package's name, base URL and auth, the endpoint and entity lines, the paging, feeds, JSON keys and
//        date formats, the folder, and whether to link.
//  OUT:  NetworkResult: the files written, the client and its endpoints, the types, what it was linked into.
//  PIN:  NO MODEL. The whole layer is made from the lines, the same way every time; a call the agent cannot honour is
//        refused with every reason at once, and nothing is written until every file parses.
//  PIN:  A LATER CALL ADDS. The package keeps its lines in `api.json`, so two more endpoints are two more lines.

import Foundation
import GraniteAgents

public struct NetworkAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// The package, its library and its module: `RecipeKit`. `API` when left out.
        public var name: String?
        /// Where the client sends unless told otherwise: `https://api.recipes.example`.
        public var baseURL: String?
        /// How requests are signed; bearer when a line stores a token, else none, when left out.
        public var auth: NetworkAuth?
        /// The header or query parameter the token goes in, for `header` and `query` auth.
        public var authName: String?
        /// One line an endpoint: `GET /v1/recipes/{id:Int}?full:Bool -> Recipe as recipe`.
        public var endpoints: [String]?
        /// One line a type the endpoints send or answer, in ModelsAgent's line.
        public var entities: [String]?
        /// How paged endpoints ask for the next page; read from the lines when left out.
        public var paging: NetworkPaging?
        /// Whether the client reads RSS, Atom and JSON Feed; false when left out.
        public var feeds: Bool?
        /// `snake` for snake_case JSON keys; `exact` when left out.
        public var coding: NetworkCoding?
        /// Date formats the API writes beside ISO 8601.
        public var dates: [String]?
        /// The package's folder, relative to the project; `Packages/<name>` when left out.
        public var into: String?
        /// Whether the package is linked into the project; true when left out.
        public var link: Bool?
        /// The host's folder.
        public var directory: String?

        public init(name: String? = nil, baseURL: String? = nil, auth: NetworkAuth? = nil, authName: String? = nil,
                    endpoints: [String]? = nil, entities: [String]? = nil, paging: NetworkPaging? = nil, feeds: Bool? = nil,
                    coding: NetworkCoding? = nil, dates: [String]? = nil, into: String? = nil, link: Bool? = nil,
                    directory: String? = nil) {
            self.name = name; self.baseURL = baseURL; self.auth = auth; self.authName = authName; self.endpoints = endpoints
            self.entities = entities; self.paging = paging; self.feeds = feeds; self.coding = coding; self.dates = dates
            self.into = into; self.link = link; self.directory = directory
        }
    }

    public typealias Event = NetworkFrame
    public typealias Output = NetworkResult
    public typealias Compute = Void

    public static let word = "network"
    public static let summary = "writes an app's backend API layer — a typed Swift client package with auth, paging, retries, uploads, feeds, models and tests — from one compact line an endpoint, and links it into the project."
    public static let fields = [
        "name": "the package, its library and module: `RecipeKit` (its types drop Kit: `RecipeClient`); API when left out",
        "baseURL": "where the client sends unless told otherwise, `https://api.recipes.example`; the app may change it while it runs",
        "auth": "how requests are signed: bearer (OAuth, JWT), basic, header or query (both named in authName), none; bearer when a line stores a token",
        "authName": "the header (`X-API-Key`) or query parameter (`api_key`) the token goes in, for auth header or query",
        "endpoints": "one line an endpoint: `GET /v1/recipes/{id:Int}?full:Bool -> Recipe as recipe`, then `body(Type)` or `multipart(photo, caption:String?)`, `paged`, `stores token`, a quoted doc",
        "entities": "the types the endpoints send and answer, one line each: `Recipe \"a dish\": id Int, title String, minutes Int = 30, course Course?`; an enum is `Course: starter | main | dessert`",
        "paging": "page (a `page` number in the query) or cursor (a `cursor`, `page_cursor`, `max_id`, `after` or `page_token` query; the next one from the response or its Link header); read from the lines when left out",
        "feeds": "whether the client reads RSS, Atom and JSON Feed with `feed(at:)`; false when left out",
        "coding": "snake for snake_case JSON keys; exact when left out",
        "dates": "date formats the API writes beside ISO 8601, as patterns (`yyyy-MM-dd HH:mm:ss`), or `seconds` or `milliseconds` for numbers",
        "into": "the package's folder, relative to the project; Packages/<name> when left out",
        "link": "whether the package is linked into the project's app targets (an .xcodeproj) or its Package.swift; true when left out",
    ]
    public static let guide = """
        Tag network for an app's backend: a local package, the typed client of one HTTP API, that the app links. Give \
        `name`, `baseURL`, `auth` and one line an endpoint: `METHOD /path -> Response`, then any of `body(Type)` or \
        `multipart(field, …)`, `as name` (or `as Group.name`), `paged`, `stores token`, and a quoted doc. A path \
        parameter is `{id}` (a String) or `{id:Int}`; the query is `?name,name:Type`, each an optional argument, a \
        String unless typed (`page`, `limit`, `per_page` are Int), required with a trailing `!`. Every type a line \
        names is a primitive or has an `entities` line, the models line: `Recipe "a dish": id Int, title String, \
        minutes Int = 30, photo URL?` (`@json_key` names a key, `= value` is what a missing key reads as) and \
        `Course: starter | main | dessert`. Example: {"name": "RecipeKit", "baseURL": "https://api.recipes.example", \
        "auth": "bearer", "coding": "snake", "endpoints": ["POST /v1/session body(Credentials) -> Session as signIn \
        stores token", "GET /v1/recipes?page,per_page,course:Course -> RecipePage as recipes paged \\"newest first\\"", \
        "GET /v1/recipes/{id:Int} -> Recipe as recipe", "POST /v1/recipes body(NewRecipe) -> Recipe as \
        createRecipe", "DELETE /v1/recipes/{id:Int} as deleteRecipe", "POST /v1/photos multipart(photo, \
        caption:String?) -> Photo as uploadPhoto"], "entities": ["Credentials: email String, password String", \
        "Session: token String", "RecipePage: recipes [Recipe], total Int = 0", "Recipe: id Int, title String, \
        minutes Int = 30, course Course?, added Date", "Course: starter | main | dessert", "NewRecipe: title String, \
        minutes Int", "Photo: id String, url URL"]}. `stores token` keeps the answer's token field for the host, and \
        every request after carries it. `paged` (with `paging: page`, a `page` query, or `paging: cursor`, a `cursor`, \
        `page_cursor`, `max_id`, `after` or `page_token` query, the next read off a `nextCursor`-like field or the \
        Link header) adds `recipesPages(…)`, an AsyncSequence of pages; `paged(field)` names the list. Feeds: \
        {"name": "PantryKit", "feeds": true} gives `feed(at:)` for RSS, Atom and JSON Feed. `dates` adds formats \
        beside ISO 8601 (`yyyy-MM-dd HH:mm:ss`, or `milliseconds`). A later call adds to the package: a line \
        replaces the one with its method and path, its name or its type, and the rest stays, so give only what is \
        new. The package is linked into the project's app targets (`link: false` skips it). A call it cannot honour \
        is refused with every reason and nothing is written: fix the lines and call again. Not for the app's own \
        types (models) or for views.
        """

    public static func output(from events: [NetworkFrame]) -> NetworkResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<NetworkFrame, Error> {
        // The host's folder when the call's JSON names none: a host on the wire may give it only there, and the
        // process's own folder is wherever the runner was started.
        var input = input
        if input.directory == nil { input.directory = context.host.directory }
        return AsyncThrowingStream { [input] continuation in
            let task = Task {
                do {
                    let result = try Self.write(input, note: context.host.note) { continuation.yield($0) }
                    continuation.yield(.written(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole call: the lines read and merged with the package's, the package made, linked, staged, checked and
    /// written.
    static func write(_ input: Input, note: @Sendable (String) -> Void, yield: (NetworkFrame) -> Void) throws -> NetworkResult {
        let files = AgentFiles(directory: input.directory)
        let named = input.name?.trimmingCharacters(in: .whitespaces)
        let folder = files.resolve(input.into ?? "Packages/\((named?.isEmpty ?? true) ? "API" : named!)")
        let record = APIRecord.read(in: folder)
        if record == nil, FileManager.default.fileExists(atPath: folder.appendingPathComponent("Package.swift").path) {
            throw NetworkError.refused(["`\(files.relative(folder))` already holds a package this agent did not write: give another `into`"])
        }
        let call = APIRecord.call(input, over: record)
        let api = try API.resolve(call)
        yield(.read(endpoints: api.methods.count, types: api.entities.count))
        note("writing \(api.module) into \(files.relative(folder)): \(api.methods.count) endpoint\(api.methods.count == 1 ? "" : "s"), \(api.entities.count) type\(api.entities.count == 1 ? "" : "s")")

        let made = PackageEmitter(api: api).files()
        let kept = made.map(\.path) + [APIRecord.fileName]
        var planned = made.map { (url: folder.appendingPathComponent($0.path), text: $0.text) }
        planned.append((folder.appendingPathComponent(APIRecord.fileName), APIRecord(api: api, call: call, files: kept).text))

        // The project the package is linked into: its Xcode projects and its manifest.
        var linked: [String] = [], notes: [String] = []
        if input.link ?? true, folder.path != files.root.path {
            let manager = FileManager.default
            let projects = ((try? manager.contentsOfDirectory(atPath: files.root.path)) ?? []).filter { $0.hasSuffix(".xcodeproj") }.sorted()
            for name in projects {
                let project = files.root.appendingPathComponent(name)
                let (text, said) = try XcodeLink.link(project: project, package: folder, product: api.module)
                notes += said
                if let text { planned.append((project.appendingPathComponent("project.pbxproj"), text)) }
                linked.append(project.appendingPathComponent("project.pbxproj").path)
            }
            let manifest = files.root.appendingPathComponent("Package.swift")
            if manager.fileExists(atPath: manifest.path) {
                let (text, said) = try ManifestLink.link(manifest: manifest, package: folder, product: api.module)
                notes += said
                if let text { planned.append((manifest, text)) }
                linked.append(manifest.path)
            }
        }

        let written = try files.write(planned)
        // What an earlier call wrote and the package no longer has.
        for old in record?.files ?? [] where !kept.contains(old) {
            let url = folder.appendingPathComponent(old)
            guard url.path.hasPrefix(folder.path + "/"), (try? FileManager.default.removeItem(at: url)) != nil else { continue }
            notes.append("removed \(old), which the package no longer has")
            var parent = url.deletingLastPathComponent()
            while parent.path.hasPrefix(folder.path + "/"),
                  (try? FileManager.default.contentsOfDirectory(atPath: parent.path))?.isEmpty == true {
                try? FileManager.default.removeItem(at: parent)
                parent = parent.deletingLastPathComponent()
            }
        }
        note("wrote \(written.count) file\(written.count == 1 ? "" : "s")\(linked.isEmpty ? "" : ", linked into \(linked.map { files.relative(URL(fileURLWithPath: $0)) }.joined(separator: " and "))")")
        let client = folder.appendingPathComponent("Sources/\(api.module)/\(api.client).swift").path
        return NetworkResult(path: written.first { $0 == client } ?? written.first, paths: written, package: folder.path,
                             client: api.client, endpoints: api.methods.map(\.name), types: api.entities.map(\.name),
                             linked: linked, notes: notes)
    }
}
