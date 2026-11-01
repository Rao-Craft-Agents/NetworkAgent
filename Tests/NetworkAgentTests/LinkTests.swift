import Foundation
import XCTest
@testable import NetworkAgent

/// The package linked into a project: an Xcode project's application targets, or a package's manifest, once.
final class LinkTests: XCTestCase {
    private func project(_ edit: (String) -> String = { $0 }) throws -> (project: URL, package: URL) {
        let folder = try Fixture.folder()
        try XcodeFixture.write(at: folder, name: "Pantry")
        let project = folder.appendingPathComponent("Pantry.xcodeproj")
        let file = project.appendingPathComponent("project.pbxproj")
        try edit(try String(contentsOf: file, encoding: .utf8)).write(to: file, atomically: true, encoding: .utf8)
        return (project, folder.appendingPathComponent("Packages/RecipeKit"))
    }

    /// The project file read as Xcode reads it.
    private func objects(_ text: String) throws -> (root: [String: Any], objects: [String: [String: Any]]) {
        let plist = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil) as? [String: Any])
        let objects = try XCTUnwrap(plist["objects"] as? [String: [String: Any]])
        let root = try XCTUnwrap(objects[try XCTUnwrap(plist["rootObject"] as? String)])
        return (root, objects)
    }

    /// Checks every application target has `product` in its dependencies and in its Frameworks phase.
    private func assertLinked(_ text: String, product: String, path: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let (root, objects) = try objects(text)
        let references = (root["packageReferences"] as? [String] ?? []).compactMap { objects[$0] }
        XCTAssertEqual(references.filter { $0["relativePath"] as? String == path }.count, 1, "one reference to \(path)", file: file, line: line)
        let targets = (root["targets"] as? [String] ?? []).compactMap { objects[$0] }
        XCTAssertEqual(targets.count, 2, file: file, line: line)
        for target in targets {
            let products = (target["packageProductDependencies"] as? [String] ?? []).filter { objects[$0]?["productName"] as? String == product }
            XCTAssertEqual(products.count, 1, "\(target["name"] ?? "") depends on \(product) once", file: file, line: line)
            let phases = (target["buildPhases"] as? [String] ?? []).compactMap { objects[$0] }.filter { $0["isa"] as? String == "PBXFrameworksBuildPhase" }
            let built = phases.flatMap { $0["files"] as? [String] ?? [] }.filter { objects[$0]?["productRef"] as? String == products.first }
            XCTAssertEqual(built.count, 1, "\(target["name"] ?? "") builds with \(product)", file: file, line: line)
        }
    }

    func testEveryApplicationTargetGetsTheProductOnce() throws {
        let (project, package) = try project()
        let original = try String(contentsOf: project.appendingPathComponent("project.pbxproj"), encoding: .utf8)
        let (text, notes) = try XcodeLink.link(project: project, package: package, product: "RecipeKit")
        let linked = try XCTUnwrap(text)
        try assertLinked(linked, product: "RecipeKit", path: "Packages/RecipeKit")
        try assertLinked(linked, product: "Kit", path: "Packages/Kit")
        XCTAssertTrue(linked.contains("\t\t\t\t110000000000000000000001 /* Kit in Frameworks */,\n\t\t\t\t"), "added after what the list held")
        XCTAssertTrue(linked.contains("MACOSX_DEPLOYMENT_TARGET = 14.0;") && !linked.contains("MACOSX_DEPLOYMENT_TARGET = 13.0;"))
        XCTAssertEqual(notes, ["linked RecipeKit into Pantry.xcodeproj's Pantry-iOS and Pantry-macOS",
                               "raised Pantry.xcodeproj's macOS deployment target from 13.0 to 14.0, which the package needs"])
        // Only lines were added, and the one setting changed.
        let removed = Set(original.split(separator: "\n")).subtracting(linked.split(separator: "\n"))
        XCTAssertEqual(removed.map { $0.trimmingCharacters(in: .whitespaces) }.sorted(), ["MACOSX_DEPLOYMENT_TARGET = 13.0;"])

        try linked.write(to: project.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        let (again, quiet) = try XcodeLink.link(project: project, package: package, product: "RecipeKit")
        XCTAssertNil(again, "a second link changes nothing")
        XCTAssertEqual(quiet, [])
    }

    func testAProjectWithNoPackagesOrFrameworksPhaseGetsThem() throws {
        // The fixture with Kit taken out: no package references, no product dependencies, no Frameworks phases.
        let (project, package) = try project { text in
            var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            lines.removeAll { $0.contains("Kit") || $0.contains("150000000000000000000001 /* Frameworks */,") || $0.contains("150000000000000000000002 /* Frameworks */,") }
            var out = lines.joined(separator: "\n")
            for section in ["PBXBuildFile", "PBXFrameworksBuildPhase", "XCLocalSwiftPackageReference", "XCSwiftPackageProductDependency"] {
                let begin = out.range(of: "/* Begin \(section) section */")!, end = out.range(of: "/* End \(section) section */\n")!
                out.removeSubrange(begin.lowerBound..<end.upperBound)
            }
            out = out.replacingOccurrences(of: "\t\t\tpackageReferences = (\n\t\t\t);\n", with: "")
            out = out.replacingOccurrences(of: "\t\t\tpackageProductDependencies = (\n\t\t\t);\n", with: "")
            return out
        }
        let stripped = try String(contentsOf: project.appendingPathComponent("project.pbxproj"), encoding: .utf8)
        XCTAssertFalse(stripped.contains("packageReferences") || stripped.contains("PBXFrameworksBuildPhase"), "the fixture has none")
        XCTAssertNoThrow(try objects(stripped))
        let (text, _) = try XcodeLink.link(project: project, package: package, product: "RecipeKit")
        let linked = try XCTUnwrap(text)
        try assertLinked(linked, product: "RecipeKit", path: "Packages/RecipeKit")
        for section in ["PBXBuildFile", "PBXFrameworksBuildPhase", "XCLocalSwiftPackageReference", "XCSwiftPackageProductDependency"] {
            XCTAssertTrue(linked.contains("/* Begin \(section) section */"), section)
        }
        let order = ["PBXBuildFile", "PBXFileReference", "PBXFrameworksBuildPhase", "PBXGroup", "XCConfigurationList", "XCLocalSwiftPackageReference",
                     "XCSwiftPackageProductDependency"].map { linked.range(of: "/* Begin \($0) section */")!.lowerBound }
        XCTAssertEqual(order, order.sorted(), "sections in Xcode's order")
    }

    func testAPathClimbsWhenThePackageIsElsewhere() {
        XCTAssertEqual(XcodeLink.relativePath(from: URL(fileURLWithPath: "/a/App"), to: URL(fileURLWithPath: "/a/App/Packages/Kit")), "Packages/Kit")
        XCTAssertEqual(XcodeLink.relativePath(from: URL(fileURLWithPath: "/a/App"), to: URL(fileURLWithPath: "/a/Shared/Kit")), "../Shared/Kit")
        XCTAssertEqual(PBXText.quoted("Packages/Kit"), "Packages/Kit")
        XCTAssertEqual(PBXText.quoted("../My Kits/Kit"), "\"../My Kits/Kit\"")
    }

    func testAManifestGetsTheDependencyOnce() throws {
        let folder = try Fixture.folder()
        let manifest = folder.appendingPathComponent("Package.swift")
        try """
        // swift-tools-version:6.0
        import PackageDescription

        let package = Package(
            name: "Pantry",
            platforms: [.macOS(.v13), .iOS(.v17)],
            dependencies: [
                .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
            ],
            targets: [
                .executableTarget(name: "Pantry", dependencies: [.product(name: "Collections", package: "swift-collections")]),
                .target(name: "PantryCore"),
                .testTarget(name: "PantryTests", dependencies: ["PantryCore"]),
            ]
        )
        """.write(to: manifest, atomically: true, encoding: .utf8)
        let package = folder.appendingPathComponent("Packages/RecipeKit")
        let (text, notes) = try ManifestLink.link(manifest: manifest, package: package, product: "RecipeKit")
        let linked = try XCTUnwrap(text)
        XCTAssertTrue(linked.contains("""
                .package(url: "https://github.com/apple/swift-collections", from: "1.1.0"),
                .package(path: "Packages/RecipeKit"),
            ],
        """), linked)
        XCTAssertTrue(linked.contains(#".executableTarget(name: "Pantry", dependencies: [.product(name: "Collections", package: "swift-collections"), .product(name: "RecipeKit", package: "RecipeKit")]),"#), linked)
        XCTAssertTrue(linked.contains(#".target(name: "PantryCore", dependencies: [.product(name: "RecipeKit", package: "RecipeKit")]),"#), linked)
        XCTAssertTrue(linked.contains(#".testTarget(name: "PantryTests", dependencies: ["PantryCore"]),"#), "a test target is left alone")
        XCTAssertTrue(linked.contains("platforms: [.macOS(.v14), .iOS(.v17)]"), linked)
        XCTAssertEqual(notes, ["added RecipeKit to Package.swift's Pantry, PantryCore", "raised Package.swift's macOS platform to 14, which RecipeKit needs"])
        XCTAssertNil(try SwiftParse.check([{ let url = folder.appendingPathComponent("Check.swift"); try? linked.write(to: url, atomically: true, encoding: .utf8); return url }()]))

        try linked.write(to: manifest, atomically: true, encoding: .utf8)
        let (again, _) = try ManifestLink.link(manifest: manifest, package: package, product: "RecipeKit")
        XCTAssertNil(again, "a second link changes nothing")
    }

    func testAManifestWithNoDependenciesOrPlatformsGetsThem() throws {
        let folder = try Fixture.folder()
        let manifest = folder.appendingPathComponent("Package.swift")
        try """
        // swift-tools-version:6.0
        import PackageDescription

        let package = Package(
            name: "Pantry",
            targets: [
                .executableTarget(name: "Pantry"),
            ]
        )
        """.write(to: manifest, atomically: true, encoding: .utf8)
        let (text, _) = try ManifestLink.link(manifest: manifest, package: folder.appendingPathComponent("Packages/RecipeKit"), product: "RecipeKit")
        XCTAssertEqual(text, """
        // swift-tools-version:6.0
        import PackageDescription

        let package = Package(
            name: "Pantry",
            platforms: [.iOS(.v17), .macOS(.v14)],
            dependencies: [
                .package(path: "Packages/RecipeKit"),
            ],
            targets: [
                .executableTarget(name: "Pantry", dependencies: [.product(name: "RecipeKit", package: "RecipeKit")]),
            ]
        )
        """)
    }

    func testAManifestThatIsNotPlainIsLeftAloneWithANote() throws {
        let folder = try Fixture.folder()
        let manifest = folder.appendingPathComponent("Package.swift")
        try """
        // swift-tools-version:6.0
        import PackageDescription

        let dependencies: [Package.Dependency] = []
        let package = Package(name: "Pantry", dependencies: dependencies, targets: [.target(name: "Pantry")])
        """.write(to: manifest, atomically: true, encoding: .utf8)
        let (text, notes) = try ManifestLink.link(manifest: manifest, package: folder.appendingPathComponent("Packages/RecipeKit"), product: "RecipeKit")
        XCTAssertNil(text)
        XCTAssertEqual(notes.count, 1)
        XCTAssertTrue(notes[0].contains("by hand"), notes[0])
    }
}
