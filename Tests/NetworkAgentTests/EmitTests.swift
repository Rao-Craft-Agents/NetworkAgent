import Foundation
import XCTest
@testable import NetworkAgent

/// What the files say: the shapes the guide promises, read off a call's output.
final class EmitTests: XCTestCase {
    private func write(_ input: NetworkAgent.Input) throws -> (NetworkResult, URL) {
        let folder = try Fixture.folder()
        var input = input
        input.directory = folder.path
        return (try NetworkAgent.write(input, note: { _ in }, yield: { _ in }), folder)
    }

    private func text(_ result: NetworkResult, _ suffix: String) throws -> String {
        let path = try XCTUnwrap(result.paths.first { $0.hasSuffix("/" + suffix) }, suffix)
        return try String(contentsOfFile: path, encoding: .utf8)
    }

    func testEndpointsAreTypedMethods() throws {
        let (result, _) = try write(Fixture.lemmy)
        let posts = try text(result, "Endpoints/Posts.swift")
        XCTAssertTrue(posts.contains("extension LemmyClient {"))
        XCTAssertTrue(posts.contains("    /// The posts of a community, or of the instance.\n    ///\n    /// `GET /api/v3/post/list`; every page: `postsPages(…)`."), posts)
        XCTAssertTrue(posts.contains("communityID: Int? = nil\n    ) async throws -> GetPostsResponse {"), posts)
        XCTAssertTrue(posts.contains(#""type_": type,"#) && posts.contains(#""community_id": communityID,"#), "sent under their wire names")
        XCTAssertTrue(posts.contains("public func post(id: Int, commentID: Int? = nil) async throws -> PostResponse {"), "`!` makes it required")
        XCTAssertTrue(posts.contains("@discardableResult\n    public func createPost(_ body: CreatePost) async throws -> PostResponse {"))
        XCTAssertTrue(posts.contains("try await send(Request<PostResponse>(.post, \"/api/v3/post\", body: .json(body)))"))

        let user = try text(result, "Endpoints/User.swift")
        XCTAssertTrue(user.contains("if let token = response.jwt { try signIn(token: token) }"), user)
        XCTAssertTrue(user.contains("public func personPosts(username: String, page: Int? = nil, limit: Int? = nil) async throws -> GetPostsResponse"))
        let comment = try text(result, "Endpoints/Comment.swift")
        XCTAssertTrue(comment.contains("public func deleteComment(id: Int) async throws {\n        _ = try await send(Request<NoContent>(.delete, \"/api/v3/comment/{id}\", parameters: [\"id\": id]))"), comment)
        let upload = try text(result, "Endpoints/Pictrs.swift")
        XCTAssertTrue(upload.contains("var form = Multipart()\n        form.add(\"images[]\", images)"), upload)
    }

    func testEveryPagedEndpointHasItsPages() throws {
        let (lemmy, _) = try write(Fixture.lemmy)
        let posts = try text(lemmy, "Endpoints/Posts.swift")
        XCTAssertTrue(posts.contains("public func postsPages(\n        from page: Int = 1,"), posts)
        XCTAssertTrue(posts.contains("let last = items.isEmpty || limit.map { items.count < $0 } == true"))
        XCTAssertTrue(posts.contains("return Page(items: items, number: number, next: last ? nil : number + 1)"))

        let (mastodon, _) = try write(Fixture.mastodon)
        let timeline = try text(mastodon, "Endpoints/Timelines.swift")
        XCTAssertTrue(timeline.contains("public func homeTimelinePages(from cursor: String? = nil, limit: Int? = nil) -> Pages<Status> {"), timeline)
        XCTAssertTrue(timeline.contains("""
                    let request = Request<[Status]>(.get, "/api/v1/timelines/home", query: ["max_id": cursor, "limit": limit])
                    let (value, response) = try await exchange(request)
        """), timeline)
        XCTAssertTrue(timeline.contains(#"let next = LinkHeader.value(response.header("Link"), parameter: "max_id")"#))
        XCTAssertTrue(try text(mastodon, "Paging/LinkHeader.swift").contains("public enum LinkHeader"))

        let byField = NetworkAgent.Input(name: "BookKit", endpoints: ["GET /v1/books?cursor,limit -> BookPage paged"],
                                         entities: ["BookPage: books [Book], nextCursor String?", "Book: id String"])
        let (books, _) = try write(byField)
        XCTAssertTrue(try text(books, "Endpoints/Books.swift").contains("return Page(items: response.books, cursor: cursor, next: response.nextCursor)"))
    }

    func testModelsKeepTheirKeysAndReadWhatTheyDoNotKnow() throws {
        let (result, _) = try write(Fixture.lemmy)
        let login = try text(result, "Models/Login.swift")
        XCTAssertTrue(login.contains("public struct Login: Codable, Hashable, Sendable {"))
        XCTAssertTrue(login.contains(#"case usernameOrEmail = "username_or_email""#), "snake keys written, not converted")
        XCTAssertTrue(login.contains(#"case totp2faToken = "totp_2fa_token""#), "an @key as given")
        let post = try text(result, "Models/Post.swift")
        XCTAssertTrue(post.contains(#"case creatorID = "creator_id""#), "an acronym's key")
        XCTAssertTrue(post.contains("nsfw = try container.decodeIfPresent(Bool.self, forKey: .nsfw) ?? false"), "a default is a default in JSON")
        let community = try text(result, "Models/Community.swift")
        XCTAssertTrue(community.contains("visibility = (try? container.decodeIfPresent(CommunityVisibility.self, forKey: .visibility)) ?? .public"),
                      "a case the server added reads as the default")
        let sort = try text(result, "Models/SortType.swift")
        XCTAssertTrue(sort.contains("public enum SortType: String, Codable, CaseIterable, Hashable, Identifiable, Sendable, QueryValue {"))
        XCTAssertTrue(sort.contains(#"case topDay = "TopDay""#))
        let postView = try text(result, "Models/PostView.swift")
        XCTAssertTrue(postView.contains("public static let preview: PostView = PostView(\n        post: Post.preview,"), "a long preview, one argument a line")
        let (mastodon, _) = try write(Fixture.mastodon)
        let visibility = try text(mastodon, "Models/Visibility.swift")
        XCTAssertTrue(visibility.contains("case `public`") && visibility.contains("case `private`"), "keywords escaped")
    }

    func testATypeThatHoldsItselfKeepsItBehindAReference() throws {
        let (result, _) = try write(Fixture.mastodon)
        let status = try text(result, "Models/Status.swift")
        XCTAssertTrue(status.contains("    @Indirect public var reblog: Status?"), status)
        XCTAssertFalse(status.contains("@Indirect public var account"), "an Account does not hold a Status")
        XCTAssertTrue(try text(result, "Coding/Indirect.swift").contains("public struct Indirect<Value: Sendable>: Sendable {"))
        let (lemmy, _) = try write(Fixture.lemmy)
        XCTAssertFalse(lemmy.paths.contains { $0.hasSuffix("Indirect.swift") }, "written only when a type needs it")
        let tree = ModelEmitter(entities: try ["Node: leaf(Int) | pair(Node, Node) | list([Node])"].map(EntityLine.parse), coding: .exact)
        let node = tree.emit(try XCTUnwrap(tree.entities["Node"]))
        XCTAssertTrue(node.contains("    indirect case pair(Node, Node)") && node.contains("    case list([Node])"), node)
    }

    func testTheCodingReadsTheDatesTheCallNames() throws {
        let (lemmy, _) = try write(Fixture.lemmy)
        let coding = try text(lemmy, "Coding/LemmyCoding.swift")
        XCTAssertTrue(coding.contains(#"public static let dateFormats: [String] = ["yyyy-MM-dd HH:mm:ss"]"#))
        XCTAssertTrue(coding.contains(#"encoder.dateEncodingStrategy = .formatted(formatter("yyyy-MM-dd HH:mm:ss"))"#))
        XCTAssertTrue(coding.contains("return Date(timeIntervalSince1970: number)"))
        let (stamps, _) = try write(.init(name: "ClockKit", endpoints: ["GET /v1/now -> String"], dates: ["milliseconds"]))
        let clock = try text(stamps, "Coding/ClockCoding.swift")
        XCTAssertTrue(clock.contains("return Date(timeIntervalSince1970: number / 1000)"))
        XCTAssertTrue(clock.contains("encoder.dateEncodingStrategy = .millisecondsSince1970"))
        let (plain, _) = try write(Fixture.recipes)
        XCTAssertTrue(try text(plain, "Coding/RecipeCoding.swift").contains("encoder.dateEncodingStrategy = .iso8601"))
    }

    func testTheClientSaysItsBaseURLAndAuth() throws {
        let (lemmy, _) = try write(Fixture.lemmy)
        let client = try text(lemmy, "Sources/LemmyKit/LemmyClient.swift")
        XCTAssertTrue(client.contains(#"public static let defaultBaseURL = URL(string: "https://lemmy.example")!"#))
        XCTAssertTrue(client.contains("public init(baseURL: URL = LemmyClient.defaultBaseURL, auth: AuthScheme = .bearer,"))
        XCTAssertTrue(client.contains("public var baseURL: URL {\n        get { state.withLock { $0.baseURL } }\n        set { state.withLock { $0.baseURL = newValue } }"))
        XCTAssertFalse(client.contains("__"), "every blank filled")
        let (keyed, _) = try write(.init(name: "WeatherKit", auth: .query, authName: "api_key", endpoints: ["GET /v1/today -> String"]))
        let weather = try text(keyed, "Sources/WeatherKit/WeatherClient.swift")
        XCTAssertTrue(weather.contains(#"auth: AuthScheme = .query("api_key")"#))
        XCTAssertTrue(weather.contains("public init(baseURL: URL, auth:"), "no base URL given: the app gives one")
        let package = try text(keyed, "Package.swift")
        XCTAssertTrue(package.contains("platforms: [.iOS(.v17), .macOS(.v14)]"))
        XCTAssertTrue(package.contains(".swiftLanguageMode(.v6)"))
        XCTAssertFalse(package.contains(".package("), "no dependencies")
        for path in keyed.paths where path.hasSuffix(".swift") {
            let source = try String(contentsOfFile: path, encoding: .utf8)
            for word in ["TODO", "FIXME", "fatalError(", "print("] {
                XCTAssertFalse(source.contains(word), "\(word) in \(path)")
            }
        }
    }

    func testTheTestsSendThroughAMockAndReadTheSample() throws {
        let (result, _) = try write(Fixture.ipfs)
        let tests = try text(result, "Tests/IPFSKitTests/AddTests.swift")
        XCTAssertTrue(tests.contains("let response = try await client.add(file: MultipartFile(data: Data(\"Sample file\".utf8), filename: \"sample.txt\"), pin: false, cidVersion: 42)"), tests)
        XCTAssertTrue(tests.contains(#"XCTAssertEqual(request.queryItems, ["pin": "false", "cid-version": "42"])"#), tests)
        XCTAssertTrue(tests.contains(#"XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic dGVzdC10b2tlbg==")"#), tests)
        XCTAssertTrue(tests.contains("XCTAssertEqual(response, AddResult.preview)"))
        let samples = try text(result, "Tests/IPFSKitTests/Support/Samples.swift")
        XCTAssertTrue(samples.contains(#""Hash": "Sample hash""#), "a sample says the API's own keys")
        let cat = try text(result, "Tests/IPFSKitTests/CatTests.swift")
        XCTAssertTrue(cat.contains(#"XCTAssertEqual(response, Data("Sample bytes".utf8))"#))
    }

    func testFeedsAreAskedFor() throws {
        let (news, _) = try write(Fixture.news)
        let names = Set(news.paths.map { URL(fileURLWithPath: $0).lastPathComponent })
        XCTAssertTrue(names.isSuperset(of: ["Feed.swift", "FeedItem.swift", "FeedParser.swift", "FeedXMLReader.swift", "JSONFeedDocument.swift",
                                            "NewsClient+Feed.swift", "FeedTests.swift"]))
        XCTAssertFalse(names.contains("Page.swift"), "no paging asked for")
        let (recipes, _) = try write(Fixture.recipes)
        XCTAssertFalse(recipes.paths.contains { $0.hasSuffix("FeedParser.swift") }, "no feeds asked for")
    }

    func testTheSampleIsThePreviewInJSON() throws {
        let entities = try ["Recipe: id Int, title String, minutes Int = 30, course Course?, cook Cook, added Date, tags [String] @labels",
                            "Cook: name String, avatar URL?", "Course: starter | main", "Media: photo(URL) | none"].map(EntityLine.parse)
        let models = ModelEmitter(entities: entities, coding: .snake)
        let recipe = try XCTUnwrap(models.entities["Recipe"])
        XCTAssertEqual(models.previewSwift(recipe), #"Recipe(id: 1, title: "Sample title", minutes: 42, course: Course.preview, cook: Cook.preview, added: Date(timeIntervalSince1970: 1_767_225_600), labels: ["Sample tag"])"#.replacingOccurrences(of: "labels:", with: "tags:"))
        let json = models.json(recipe)
        for line in [#""id": 1"#, #""title": "Sample title""#, #""minutes": 42"#, #""course": "starter""#, #""name": "Sample name""#,
                     #""added": "2026-01-01T00:00:00Z""#, #""labels": ["#] {
            XCTAssertTrue(json.contains(line), "\(line) in \(json)")
        }
        XCTAssertEqual(models.json(try XCTUnwrap(models.entities["Media"])), "{\n  \"photo\": {\n    \"_0\": \"https://example.com/value0\"\n  }\n}")
        XCTAssertEqual(models.encodedKeys(recipe), ["id", "title", "minutes", "course", "cook", "added", "labels"])
    }
}

/// The host's folder, kept as the host wrote it.
final class AgentFilesTests: XCTestCase {
    func testPathsKeepTheHostsFormAndResolveParents() {
        let files = AgentFiles(directory: "/private/tmp/app")
        XCTAssertEqual(files.resolve("Packages/RecipeKit").path, "/private/tmp/app/Packages/RecipeKit", "/private is not dropped")
        XCTAssertEqual(files.resolve("Packages/../Shared/./X.swift").path, "/private/tmp/app/Shared/X.swift")
        XCTAssertEqual(files.resolve("/abs/a/../b").path, "/abs/b")
        XCTAssertEqual(files.relative(files.resolve("Packages/RecipeKit/Package.swift")), "Packages/RecipeKit/Package.swift")
        XCTAssertEqual(files.relative(URL(fileURLWithPath: "/elsewhere/x")), "/elsewhere/x")
    }
}
