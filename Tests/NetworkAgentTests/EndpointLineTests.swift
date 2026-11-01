import XCTest
@testable import NetworkAgent

/// The endpoint line a model writes, read: every form the guide promises, and a reason for every line refused.
final class EndpointLineTests: XCTestCase {
    func testAFullLine() throws {
        let endpoint = try EndpointLine.parse(#"GET /api/v1/accounts/{id}/statuses?limit:Int,max_id,only_media:Bool,q! -> [Status] as Accounts.statuses paged "an account's posts""#)
        XCTAssertEqual(endpoint.method, "GET")
        XCTAssertEqual(endpoint.path, "/api/v1/accounts/{id}/statuses")
        XCTAssertEqual(endpoint.pathParameters.map(\.wire), ["id"])
        XCTAssertEqual(endpoint.pathParameters[0].type, .named("String"))
        XCTAssertEqual(endpoint.query.map(\.wire), ["limit", "max_id", "only_media", "q"])
        XCTAssertEqual(endpoint.query.map(\.type.description), ["Int", "String", "Bool", "String"])
        XCTAssertEqual(endpoint.query.map(\.required), [false, false, false, true])
        XCTAssertEqual(endpoint.query.map(\.typed), [true, false, true, false])
        XCTAssertEqual(endpoint.response, .array(.named("Status")))
        XCTAssertEqual(endpoint.group, "Accounts")
        XCTAssertEqual(endpoint.name, "statuses")
        XCTAssertTrue(endpoint.paged)
        XCTAssertEqual(endpoint.doc, "an account's posts")
    }

    func testBodiesTokensAndTypedPaths() throws {
        let login = try EndpointLine.parse("POST /api/v3/user/login body(Login) -> LoginResponse as login stores token(jwt)")
        XCTAssertEqual(login.body, .json(.named("Login")))
        XCTAssertTrue(login.storesToken)
        XCTAssertEqual(login.tokenField, "jwt")
        let upload = try EndpointLine.parse("POST /api/v0/add?pin:Bool,cid-version:Int multipart(file, photos:[File], caption:String?) -> AddResult")
        guard case .multipart(let parts)? = upload.body else { return XCTFail("a multipart body") }
        XCTAssertEqual(parts.map(\.wire), ["file", "photos", "caption"])
        XCTAssertEqual(parts.map(\.kind), [.file, .files, .value(.named("String"))])
        XCTAssertEqual(parts.map(\.required), [true, true, false])
        XCTAssertEqual(upload.query.map(\.wire), ["pin", "cid-version"])
        let delete = try EndpointLine.parse("delete /v1/recipes/{id:Int}")
        XCTAssertEqual(delete.method, "DELETE")
        XCTAssertEqual(delete.path, "/v1/recipes/{id}")
        XCTAssertEqual(delete.pathParameters[0].type, .named("Int"))
        XCTAssertNil(delete.response)
        let paged = try EndpointLine.parse("GET /v1/feed?page -> Feed paged(entries)")
        XCTAssertEqual(paged.itemsField, "entries")
    }

    func testWhatAModelSpacesIsReadAsOne() throws {
        let endpoint = try EndpointLine.parse("GET /v1/recipes?page: Int, per_page: Int -> RecipePage as recipes")
        XCTAssertEqual(endpoint.query.map(\.wire), ["page", "per_page"])
        XCTAssertEqual(endpoint.query.map(\.type.description), ["Int", "Int"])
        let body = try EndpointLine.parse("POST /v1/recipes body (NewRecipe) ->Recipe")
        XCTAssertEqual(body.body, .json(.named("NewRecipe")))
        XCTAssertEqual(body.response, .named("Recipe"))
    }

    func testLinesThatAreRefusedSayWhy() {
        let refused: [(String, String)] = [
            ("", "it is empty"),
            ("FETCH /v1/recipes -> Recipe", "is not a method"),
            ("GET v1/recipes -> Recipe", "does not start with `/`"),
            ("GET /v1/recipes/{id -> Recipe", "never closed"),
            ("GET /v1/recipes/{} -> Recipe", "is not `{name}`"),
            ("GET /v1/recipes body(Recipe) -> Recipe", "sends no body"),
            ("POST /v1/recipes body(A) multipart(file) -> Recipe", "two bodies"),
            ("GET /v1/recipes -> Recipe as Recipes.All", "is not a method name"),
            ("GET /v1/recipes -> Recipe soon", "is not part of an endpoint line"),
            ("GET /v1/recipes?a,a -> Recipe", "named twice"),
            ("GET /v1/recipes -> recipe", "is not a type"),
            ("POST /v1/session -> Session stores", "stores token"),
        ]
        for (line, reason) in refused {
            XCTAssertThrowsError(try EndpointLine.parse(line), line) { error in
                XCTAssertTrue("\(error)".contains(reason), "\(line) → \(error)")
            }
        }
    }

    func testTheEntityLineIsModelsAgents() throws {
        // The same line, the same reading, as ModelsAgent's (its parser, copied).
        let entity = try EntityLine.parse(#"Recipe "a dish": id String, minutes Int = 30, author Cook?, tags [String], title String @name "the dish's name""#)
        XCTAssertEqual(entity.fields.map(\.type.description), ["String", "Int", "Cook?", "[String]", "String"])
        XCTAssertEqual(entity.fields[1].defaultValue, "30")
        XCTAssertEqual(entity.fields[4].key, "name")
        let course = try EntityLine.parse(#"Course: starter | main | dessert = "pudding""#)
        XCTAssertEqual(course.cases.map(\.name), ["starter", "main", "dessert"])
    }
}

/// The required mark after the name or after the type, and an API's capitalized enum.
final class LenientLineTests: XCTestCase {
    func testTheRequiredMarkMayFollowTheNameOrTheType() throws {
        let before = try EndpointLine.parseQuery("id!:Int", in: "GET /x?id!:Int")
        let after = try EndpointLine.parseQuery("id:Int!", in: "GET /x?id:Int!")
        XCTAssertEqual(before.map(\.required), [true])
        XCTAssertEqual(after.map(\.required), [true])
        XCTAssertEqual(before.map(\.wire), ["id"])
    }

    func testCapitalizedCasesKeepTheirSpellingAsTheRawValue() throws {
        let sort = try EntityLine.parse("SortType: Active | Hot | TopDay")
        XCTAssertEqual(sort.cases.map(\.name), ["active", "hot", "topDay"])
        XCTAssertEqual(sort.cases.map(\.raw), ["\"Active\"", "\"Hot\"", "\"TopDay\""])
    }
}

/// snake_case fields said in Swift's spelling, keyed as written.
final class SnakeCaseFieldTests: XCTestCase {
    func testSnakeCaseFieldsAreCamelCasedAndKeyedAsWritten() throws {
        let entity = try EntityLine.parse("Comment: id Int, post_id Int, parent_id Int?, created_at Date")
        XCTAssertEqual(entity.fields.map(\.name), ["id", "postID", "parentID", "createdAt"])
        XCTAssertEqual(entity.fields.map(\.key), [nil, "post_id", "parent_id", "created_at"])
    }
}
