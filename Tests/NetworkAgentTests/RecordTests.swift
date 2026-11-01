import Foundation
import XCTest
@testable import NetworkAgent

/// A package across calls: a later call adds to it, a line replaces its own, a file no longer made goes, and a call
/// that is refused writes nothing.
final class RecordTests: XCTestCase {
    private func write(_ input: NetworkAgent.Input, in folder: URL) throws -> NetworkResult {
        var input = input
        input.directory = folder.path
        return try NetworkAgent.write(input, note: { _ in }, yield: { _ in })
    }

    func testALaterCallAddsToThePackage() throws {
        let folder = try Fixture.folder()
        let first = try write(Fixture.recipes, in: folder)
        XCTAssertEqual(first.endpoints.count, 6)
        let second = try write(.init(name: "RecipeKit", endpoints: [
            "GET /v1/cooks/{id} -> Cook as cook",
            "GET /v1/recipes/{id:Int} -> Recipe as recipeDetail \"a recipe, with its steps\"",
        ], entities: ["Cook: id String, name String", "Recipe: id Int, title String, steps [String] = []"]), in: folder)
        XCTAssertEqual(second.endpoints, ["signIn", "recipes", "recipeDetail", "createRecipe", "deleteRecipe", "uploadPhoto", "cook"],
                       "the line for the same method and path replaced the earlier one in its place")
        XCTAssertEqual(second.types, ["Credentials", "Session", "RecipePage", "Recipe", "Course", "NewRecipe", "Photo", "Cook"])
        let record = try XCTUnwrap(APIRecord.read(in: folder.appendingPathComponent("Packages/RecipeKit")))
        XCTAssertEqual(record.auth, .bearer, "what the second call left out is the first call's")
        XCTAssertEqual(record.coding, .snake)
        XCTAssertEqual(record.baseURL, "https://api.recipes.example")
        XCTAssertTrue(record.entities.contains("Recipe: id Int, title String, steps [String] = []"))
        let recipe = try String(contentsOf: folder.appendingPathComponent("Packages/RecipeKit/Sources/RecipeKit/Models/Recipe.swift"), encoding: .utf8)
        XCTAssertTrue(recipe.contains("public var steps: [String]"))
    }

    func testAFileThePackageNoLongerHasGoes() throws {
        let folder = try Fixture.folder()
        _ = try write(Fixture.recipes, in: folder)
        let package = folder.appendingPathComponent("Packages/RecipeKit")
        let photos = package.appendingPathComponent("Sources/RecipeKit/Endpoints/Photos.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: photos.path))
        let result = try write(.init(name: "RecipeKit", endpoints: ["POST /v1/photos multipart(photo) -> Photo as Media.uploadPhoto"]), in: folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photos.path), "the group moved to Media")
        XCTAssertFalse(FileManager.default.fileExists(atPath: package.appendingPathComponent("Tests/RecipeKitTests/PhotosTests.swift").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: package.appendingPathComponent("Sources/RecipeKit/Endpoints/Media.swift").path))
        XCTAssertTrue(result.notes.contains("removed Sources/RecipeKit/Endpoints/Photos.swift, which the package no longer has"), "\(result.notes)")
    }

    func testARefusedCallWritesNothing() throws {
        let folder = try Fixture.folder()
        var input = Fixture.recipes
        input.endpoints = (input.endpoints ?? []) + ["GET /v1/broken -> Missing"]
        XCTAssertThrowsError(try write(input, in: folder)) { error in
            XCTAssertTrue("\(error)".contains("`Missing`, which no entity line declares"), "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Packages").path))
    }

    func testAPackageThisAgentDidNotWriteIsLeftAlone() throws {
        let folder = try Fixture.folder()
        let package = folder.appendingPathComponent("Packages/RecipeKit")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try "// swift-tools-version:6.0\n".write(to: package.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try write(Fixture.recipes, in: folder)) { error in
            XCTAssertTrue("\(error)".contains("already holds a package this agent did not write"), "\(error)")
        }
    }

    func testLinkFalseLeavesTheProjectAlone() throws {
        let folder = try Fixture.folder()
        try XcodeFixture.write(at: folder, name: "Pantry")
        let before = try String(contentsOf: folder.appendingPathComponent("Pantry.xcodeproj/project.pbxproj"), encoding: .utf8)
        var input = Fixture.recipes
        input.link = false
        let result = try write(input, in: folder)
        XCTAssertEqual(result.linked, [])
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("Pantry.xcodeproj/project.pbxproj"), encoding: .utf8), before)
        input.link = nil
        let linked = try write(input, in: folder)
        XCTAssertTrue(linked.paths.contains(folder.appendingPathComponent("Pantry.xcodeproj/project.pbxproj").path), "the project file is named")
    }
}
