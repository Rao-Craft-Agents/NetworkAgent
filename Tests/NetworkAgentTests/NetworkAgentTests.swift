import Foundation
import GraniteAgents
import XCTest
@testable import NetworkAgent

/// The package as an app finds it: by its record, with the schema a model is shown and the guide a host prompts with.
final class NetworkAgentTests: XCTestCase {
    func testTheRecordIsFoundWithNothingListed() throws {
        let network = try XCTUnwrap(GraniteRoster.discovered().package("network"), "the record is in this test binary")
        XCTAssertEqual(network.module, "NetworkAgent")
        XCTAssertEqual(network.summary, NetworkAgent.summary)
    }

    func testTheSchemaIsWhatAModelIsShown() {
        let network = AnyAgentPackage(NetworkAgent.self)
        XCTAssertEqual(network.schema, .object([
            .init(name: "name", schema: .string, required: false),
            .init(name: "baseURL", schema: .string, required: false),
            .init(name: "auth", schema: .choice(["none", "bearer", "basic", "header", "query"]), required: false),
            .init(name: "authName", schema: .string, required: false),
            .init(name: "endpoints", schema: .array(.string), required: false),
            .init(name: "entities", schema: .array(.string), required: false),
            .init(name: "paging", schema: .choice(["none", "page", "cursor"]), required: false),
            .init(name: "feeds", schema: .boolean, required: false),
            .init(name: "coding", schema: .choice(["exact", "snake"]), required: false),
            .init(name: "dates", schema: .array(.string), required: false),
            .init(name: "into", schema: .string, required: false),
            .init(name: "link", schema: .boolean, required: false),
            .init(name: "directory", schema: .string, required: false),
        ]))
        XCTAssertTrue(network.takesDirectory)
        XCTAssertEqual(Set(network.fields.keys), ["name", "baseURL", "auth", "authName", "endpoints", "entities", "paging", "feeds",
                                                  "coding", "dates", "into", "link"], "a note beside every field the model sees")
        XCTAssertEqual(network.lanes, 2)
        XCTAssertNotNil(network.word.range(of: #"^[a-z][a-z0-9]{1,31}$"#, options: .regularExpression), "a store-safe word")
    }

    func testTheGuideTeachesTheLineWithAnExampleCallPerMode() throws {
        let guide = AnyAgentPackage(NetworkAgent.self).guide
        for word in ["endpoints", "entities", "body(", "multipart(", "as name", "paged", "stores token", "{id:Int}", "!", "@json_key",
                     "paging: page", "paging: cursor", "Link header", "feeds", "feed(at:)", "dates", "milliseconds", "link: false",
                     "A later call adds", "refused"] {
            XCTAssertTrue(guide.contains(word), "the guide says \(word)")
        }
        XCTAssertFalse(guide.lowercased().contains("lemmy") || guide.lowercased().contains("mastodon") || guide.contains("Loom"),
                       "its examples are of another app")
        // Each example call in the guide is a call the agent honours.
        let folder = try Fixture.folder()
        for json in Self.calls(in: guide) {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any], json)
            object["directory"] = folder.path
            let input = try JSONDecoder().decode(NetworkAgent.Input.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNoThrow(try NetworkAgent.write(input, note: { _ in }, yield: { _ in }), json)
        }
        XCTAssertEqual(Self.calls(in: guide).count, 2, "a REST call and a feeds call")
    }

    /// The JSON objects a guide writes out, `{"name": …}`.
    static func calls(in guide: String) -> [String] {
        var calls: [String] = [], depth = 0, current = "", quoted = false, escaped = false
        for character in guide {
            if depth == 0 { if character == "{" { depth = 1; current = "{" }; continue }
            current.append(character)
            if quoted {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false }
                continue
            }
            if character == "\"" { quoted = true } else if character == "{" { depth += 1 } else if character == "}" {
                depth -= 1
                if depth == 0, current.hasPrefix("{\"name\"") { calls.append(current) }
            }
        }
        return calls
    }

    /// A host on the wire may give its folder only beside the call: the files land in it, not in the process's folder.
    func testTheHostsFolderIsUsedWhenTheCallNamesNone() async throws {
        let folder = try Fixture.folder()
        let input = try JSONEncoder().encode(NetworkAgent.Input(name: "PantryKit", endpoints: ["GET /v1/shelves -> [Shelf] as shelves"],
                                                                entities: ["Shelf: id String, label String"]))
        XCTAssertFalse(String(decoding: input, as: UTF8.self).contains("directory"), "the JSON names no folder")
        let answer = try await AnyAgentPackage(NetworkAgent.self).perform(input, host: AgentHost(directory: folder.path))
        let result = try JSONDecoder().decode(NetworkResult.self, from: answer)
        XCTAssertEqual(result.package, folder.appendingPathComponent("Packages/PantryKit").path)
        XCTAssertFalse(result.paths.isEmpty)
        for path in result.paths {
            XCTAssertTrue(path.hasPrefix(folder.path + "/"), "\(path) is under the host's folder")
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: FileManager.default.currentDirectoryPath + "/Packages/PantryKit"),
                       "nothing lands in the process's folder")
    }

    /// The call as a host makes it: JSON in, the host's folder filled, JSON out naming the files.
    func testACallThroughTheRosterWritesTheFilesItNames() async throws {
        let folder = try Fixture.folder()
        let input = try JSONEncoder().encode(Fixture.recipes)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: input) as? [String: Any])
        object["directory"] = folder.path
        let answer = try await AnyAgentPackage(NetworkAgent.self).perform(JSONSerialization.data(withJSONObject: object),
                                                                         host: AgentHost(directory: folder.path, ask: "the recipe API"))
        let result = try JSONDecoder().decode(NetworkResult.self, from: answer)
        let package = folder.appendingPathComponent("Packages/RecipeKit")
        XCTAssertEqual(result.package, package.path)
        XCTAssertEqual(result.client, "RecipeClient")
        XCTAssertEqual(result.path, package.appendingPathComponent("Sources/RecipeKit/RecipeClient.swift").path)
        XCTAssertEqual(result.endpoints, ["signIn", "recipes", "recipe", "createRecipe", "deleteRecipe", "uploadPhoto"])
        XCTAssertEqual(result.types, ["Credentials", "Session", "RecipePage", "Recipe", "Course", "NewRecipe", "Photo"])
        XCTAssertEqual(result.linked, [], "the folder holds no project")
        for path in result.paths {
            XCTAssertTrue(path.hasPrefix(package.path + "/"), path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), path)
        }
        let written = Set(result.paths.map { String($0.dropFirst(package.path.count + 1)) })
        for file in ["Package.swift", "api.json", "Sources/RecipeKit/Endpoints/Sessions.swift", "Sources/RecipeKit/Endpoints/Recipes.swift",
                     "Sources/RecipeKit/Endpoints/Photos.swift", "Sources/RecipeKit/Models/Recipe.swift", "Sources/RecipeKit/Paging/Pages.swift",
                     "Sources/RecipeKit/Transport/MockTransport.swift", "Sources/RecipeKit/Auth/KeychainTokenStore.swift",
                     "Sources/RecipeKit/Errors/RecipeError.swift", "Sources/RecipeKit/Coding/RecipeCoding.swift",
                     "Tests/RecipeKitTests/RecipesTests.swift", "Tests/RecipeKitTests/Support/Samples.swift"] {
            XCTAssertTrue(written.contains(file), "\(file) is written and named")
        }
        let onDisk = try FileManager.default.subpathsOfDirectory(atPath: package.path).filter {
            var folder: ObjCBool = false
            return FileManager.default.fileExists(atPath: package.appendingPathComponent($0).path, isDirectory: &folder) && !folder.boolValue
        }
        XCTAssertEqual(Set(onDisk), written, "every file written is named, and nothing else is written")
        XCTAssertTrue(result.notes.isEmpty, "\(result.notes)")
    }
}
