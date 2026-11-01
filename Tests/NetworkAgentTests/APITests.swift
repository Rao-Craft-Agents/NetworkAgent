import XCTest
@testable import NetworkAgent

/// A call resolved into a package: the names, the groups, the paging and the tokens, and every problem refused at once.
final class APITests: XCTestCase {
    private func resolve(_ endpoints: [String], _ entities: [String] = [], name: String? = "RecipeKit", auth: NetworkAuth? = nil,
                         authName: String? = nil, paging: NetworkPaging? = nil, feeds: Bool? = nil) throws -> API {
        try API.resolve(.init(name: name, baseURL: nil, auth: auth, authName: authName, paging: paging, feeds: feeds, coding: .snake,
                              dates: nil, endpoints: endpoints, entities: entities))
    }

    func testNamesAreSaidInSwift() {
        XCTAssertEqual(API.stem(of: "RecipeKit"), "Recipe")
        XCTAssertEqual(API.stem(of: "MastodonAPI"), "Mastodon")
        XCTAssertEqual(API.stem(of: "Lemmy"), "Lemmy")
        XCTAssertEqual(API.stem(of: "API"), "API")
        XCTAssertEqual(["community_id", "cid-version", "type_", "ids[]", "Hash", "pageToken", "max_id", "avatar_url", "2fa"].map(SwiftName.camel),
                       ["communityID", "cidVersion", "type", "ids", "hash", "pageToken", "maxID", "avatarURL", "_2fa"])
        XCTAssertEqual(["post", "community", "search", "statuses", "day"].map(SwiftName.plural), ["posts", "communities", "searches", "statuses", "days"])
    }

    func testGroupsMethodNamesAndFiles() throws {
        let api = try resolve(["GET /api/v3/post/list -> [Post]", "POST /api/v3/post body(Post) -> Post", "POST /oauth/token -> String",
                               "GET /v1/recipes/{id}/steps -> [Post] as Cooking.steps", "GET / -> String as root"],
                              ["Post: id Int"])
        XCTAssertEqual(api.methods.map(\.name), ["postList", "postPost", "postOauthToken", "steps", "root"])
        XCTAssertEqual(api.methods.map(\.group), ["Post", "Post", "Oauth", "Cooking", "General"])
        XCTAssertEqual(api.groupFiles["Post"], "Posts", "the type Post has the file Post.swift")
        XCTAssertEqual(api.groupFiles["Oauth"], "Oauth")
        XCTAssertEqual(api.client, "RecipeClient")
        XCTAssertEqual(api.error, "RecipeError")
    }

    func testArgumentsTakeTheirSwiftNamesAndCountsAreInts() throws {
        let api = try resolve(["GET /v1/recipes?page,per_page,community_id,sort:Sort,tags:[String],q! -> [Recipe]"], ["Recipe: id Int", "Sort: new | top"])
        let query = try XCTUnwrap(api.methods.first).query
        XCTAssertEqual(query.map(\.name), ["page", "perPage", "communityID", "sort", "tags", "q"])
        XCTAssertEqual(query.map(\.type.description), ["Int", "Int", "String", "Sort", "[String]", "String"])
        XCTAssertEqual(query.map(\.required), [false, false, false, false, false, true])
    }

    func testPagingIsReadFromTheLines() throws {
        let byPage = try resolve(["GET /v1/recipes?page,limit -> RecipePage paged"], ["RecipePage: recipes [Recipe], total Int = 0", "Recipe: id Int"])
        XCTAssertEqual(byPage.paging, .page)
        let pagePlan = try XCTUnwrap(byPage.methods.first?.paging)
        XCTAssertEqual(pagePlan.itemsField, "recipes")
        XCTAssertEqual(pagePlan.next, .number)
        XCTAssertEqual(pagePlan.limit?.wire, "limit")

        let byField = try resolve(["GET /v1/recipes?cursor -> RecipePage paged"], ["RecipePage: recipes [Recipe], nextCursor String?", "Recipe: id Int"])
        XCTAssertEqual(byField.paging, .cursor)
        XCTAssertEqual(byField.methods.first?.paging?.next, .field("nextCursor", .optional(.named("String"))))

        let byLink = try resolve(["GET /v1/timeline?max_id,limit -> [Recipe] paged"], ["Recipe: id Int"])
        XCTAssertEqual(byLink.methods.first?.paging?.next, .link)
        XCTAssertEqual(byLink.methods.first?.paging?.marker.wire, "max_id")
        XCTAssertNil(byLink.methods.first?.paging?.itemsField, "the answer is the list")
    }

    func testATokenIsFoundInTheAnswer() throws {
        let api = try resolve(["POST /v1/session body(Credentials) -> Session as signIn stores token",
                               "POST /v1/oauth -> Grant stores token(secret)", "POST /v1/key -> String as key stores token"],
                              ["Credentials: email String", "Session: jwt String?", "Grant: secret String"])
        XCTAssertEqual(api.auth, .bearer, "a token stored means bearer when the call says no other")
        XCTAssertEqual(api.methods.map(\.token), [.field("jwt", optional: true), .field("secret", optional: false), .whole])
    }

    func testEveryProblemIsRefusedAtOnce() {
        let call: [String] = [
            "GET /v1/recipes?page -> RecipePage paged",
            "GET /v1/recipe/{id:Recipe} -> Recipe",
            "POST /v1/session -> Session stores token",
            "GET /v1/recipes?page -> RecipePage as again",
            "GET /v1/token -> Recipe as token",
            "GET /v1/cook -> Cook",
        ]
        XCTAssertThrowsError(try resolve(call, ["RecipePage: recipes [Recipe], drafts [Recipe]", "Recipe: id Int", "Session: user String"],
                                         auth: NetworkAuth.none, paging: NetworkPaging.none)) { error in
            guard case .refused(let reasons) = error as? NetworkError else { return XCTFail("\(error)") }
            let text = reasons.joined(separator: "\n")
            for part in ["is paged, and the call has no paging", "which a path cannot carry", "stores a token, and `auth` is none",
                         "is written twice", "which the client keeps for itself", "`Cook`, which no entity line declares"] {
                XCTAssertTrue(text.contains(part), "\(part) in:\n\(text)")
            }
        }
    }

    func testListsTokensAndNamesThatCannotBeRead() {
        let cases: [([String], [String], NetworkAuth?, String)] = [
            (["GET /v1/recipes?page -> RecipePage paged"], ["RecipePage: recipes [Recipe], drafts [Recipe]", "Recipe: id Int"], nil, "say which holds the items"),
            (["GET /v1/recipes?cursor -> [Recipe] paged"], ["Recipe: id Int"], nil, ""),
            (["POST /v1/session -> Session stores token"], ["Session: user String"], nil, "has no field named like one"),
            (["GET /v1/x -> X"], ["X: id Int", "Error: id Int"], nil, "a name the package keeps"),
            (["GET /v1/x -> A"], ["A: b B", "B: a A"], nil, "each need the other"),
            (["GET /v1/x -> A"], ["A: id Int"], .header, "needs `authName`"),
        ]
        for (endpoints, entities, auth, reason) in cases {
            if reason.isEmpty {
                XCTAssertNoThrow(try resolve(endpoints, entities, auth: auth))
                continue
            }
            XCTAssertThrowsError(try resolve(endpoints, entities, auth: auth), reason) { error in
                XCTAssertTrue("\(error)".contains(reason), "\(reason) → \(error)")
            }
        }
        XCTAssertThrowsError(try resolve([], [], feeds: false)) { XCTAssertEqual($0 as? NetworkError, .nothing) }
        XCTAssertThrowsError(try resolve(["GET /x -> String"], name: "LemmyClient")) { error in
            XCTAssertTrue("\(error)".contains("share its name with its client type"), "\(error)")
        }
    }
}
