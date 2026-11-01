import Foundation
import XCTest
@testable import NetworkAgent

/// The packages compiled and run as an app would: each generated package built with `swift build` and its own tests
/// run with `swift test`, built for the iOS simulator with `xcodebuild`, and one linked into an Xcode project that is
/// built for macOS and iOS. Gated (`NETWORK_BUILD=1`): the builds take minutes. `NETWORK_BUILD_KEEP=<folder>` keeps
/// what was written there.
final class NetworkBuildTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["NETWORK_BUILD"] == "1", "set NETWORK_BUILD=1 to build the output")
        if let keep = ProcessInfo.processInfo.environment["NETWORK_BUILD_KEEP"] {
            root = URL(fileURLWithPath: keep, isDirectory: true).appendingPathComponent(name.filter { $0.isLetter }, isDirectory: true)
            try? FileManager.default.removeItem(at: root)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        } else {
            root = try Fixture.folder()
        }
    }

    func testALemmyLikeClientBuildsAndPassesItsTests() throws {
        try buildAndTest(Fixture.lemmy)
    }

    func testAMastodonLikeClientBuildsAndPassesItsTests() throws {
        try buildAndTest(Fixture.mastodon)
    }

    func testAFeedsClientBuildsAndPassesItsTests() throws {
        try buildAndTest(Fixture.news)
    }

    func testAnIPFSLikeClientBuildsAndPassesItsTests() throws {
        try buildAndTest(Fixture.ipfs)
    }

    func testTheGuidesExampleBuildsAndPassesItsTests() throws {
        try buildAndTest(Fixture.recipes)
    }

    func testAPackageLinkedIntoAProjectBuildsForMacAndIPhone() throws {
        let project = root.appendingPathComponent("Pantry", isDirectory: true)
        try XcodeFixture.write(at: project, name: "Pantry")
        var input = Fixture.recipes
        input.directory = project.path
        let result = try NetworkAgent.write(input, note: { _ in }, yield: { _ in })
        XCTAssertEqual(result.linked, [project.appendingPathComponent("Pantry.xcodeproj/project.pbxproj").path])
        // Linking twice adds nothing.
        let again = try NetworkAgent.write(input, note: { _ in }, yield: { _ in })
        XCTAssertFalse(again.paths.contains { $0.hasSuffix("project.pbxproj") }, "a second link leaves the project as it is")

        let derived = root.appendingPathComponent("dd-app").path
        for (scheme, destination) in [("Pantry-macOS", "platform=macOS"), ("Pantry-iOS", "generic/platform=iOS Simulator")] {
            let (status, log) = try run("/usr/bin/xcodebuild", ["-project", project.appendingPathComponent("Pantry.xcodeproj").path,
                                                                 "-scheme", scheme, "-destination", destination, "-derivedDataPath", derived,
                                                                 "CODE_SIGNING_ALLOWED=NO", "build"], in: project)
            XCTAssertEqual(status, 0, "\(scheme): " + tail(log))
        }
    }

    /// Writes `input`'s package, builds it and runs its tests, then builds it for the iOS simulator.
    private func buildAndTest(_ input: NetworkAgent.Input) throws {
        var input = input
        input.directory = root.path
        let result = try NetworkAgent.write(input, note: { _ in }, yield: { _ in })
        let package = URL(fileURLWithPath: result.package)
        let (built, buildLog) = try run("/usr/bin/env", ["swift", "build", "--package-path", package.path], in: package)
        XCTAssertEqual(built, 0, tail(buildLog))
        XCTAssertFalse(buildLog.contains("warning:"), "the package builds without warnings: " + warnings(buildLog))
        let (tested, testLog) = try run("/usr/bin/env", ["swift", "test", "--package-path", package.path], in: package)
        XCTAssertEqual(tested, 0, tail(testLog))
        XCTAssertTrue(testLog.contains("0 failures"), tail(testLog))
        let derived = root.appendingPathComponent("dd-\(result.client)").path
        let (ios, iosLog) = try run("/usr/bin/xcodebuild", ["-scheme", URL(fileURLWithPath: result.package).lastPathComponent,
                                                             "-destination", "generic/platform=iOS Simulator", "-derivedDataPath", derived,
                                                             "-skipPackagePluginValidation", "-skipMacroValidation", "build"], in: package)
        XCTAssertEqual(ios, 0, tail(iosLog))
    }

    private func run(_ executable: String, _ arguments: [String], in folder: URL) throws -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = folder
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private func tail(_ log: String) -> String {
        let errors = log.split(separator: "\n").filter { $0.contains("error:") || $0.contains("failed") || $0.contains("XCTAssert") }
        return errors.isEmpty ? String(log.suffix(4_000)) : errors.prefix(40).joined(separator: "\n")
    }

    private func warnings(_ log: String) -> String {
        log.split(separator: "\n").filter { $0.contains("warning:") }.prefix(20).joined(separator: "\n")
    }
}
