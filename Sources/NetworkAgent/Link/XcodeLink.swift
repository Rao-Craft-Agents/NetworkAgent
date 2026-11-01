//  WHAT: A local package linked into an Xcode project: an `XCLocalSwiftPackageReference` in the project's package
//        references, and on every application target an `XCSwiftPackageProductDependency` and a `PBXBuildFile` in its
//        Frameworks phase; a deployment target below the package's raised to it.
//  PIN:  ONCE. A second link adds nothing: the reference is found by its path, a target that has the product is left
//        alone, and fresh ids are ones the file does not hold.
//  PIN:  THE STRUCTURE IS READ BY FOUNDATION, THE TEXT EDITED BY HAND. `PropertyListSerialization` reads the project
//        (targets, phases, settings); `PBXText` adds lines where Xcode would, and changes nothing else.

import Foundation

enum XcodeLink {
    /// The deployment targets the package needs, by build setting.
    static let minimums: [(setting: String, version: String, platform: String)] = [
        ("IPHONEOS_DEPLOYMENT_TARGET", "17.0", "iOS"), ("MACOSX_DEPLOYMENT_TARGET", "14.0", "macOS"),
    ]

    /// The project file of `project` (an `.xcodeproj`) with the package at `package` linked, its product `product` on
    /// every application target; nil text when nothing needed to change. Notes say what else was done.
    static func link(project: URL, package: URL, product: String) throws -> (text: String?, notes: [String]) {
        let file = project.appendingPathComponent("project.pbxproj")
        let original = try String(contentsOf: file, encoding: .utf8)
        guard let plist = try? PropertyListSerialization.propertyList(from: Data(original.utf8), format: nil) as? [String: Any],
              let objects = plist["objects"] as? [String: [String: Any]], let rootID = plist["rootObject"] as? String,
              let root = objects[rootID] else {
            return (nil, ["\(project.lastPathComponent) could not be read as an Xcode project, so the package was not linked into it"])
        }
        let name = project.lastPathComponent
        let targets = (root["targets"] as? [String] ?? []).filter {
            objects[$0]?["isa"] as? String == "PBXNativeTarget"
                && objects[$0]?["productType"] as? String == "com.apple.product-type.application"
        }
        guard !targets.isEmpty else { return (nil, ["\(name) has no application target, so the package was not linked into it"]) }

        var text = PBXText(original)
        var notes: [String] = []
        let path = relativePath(from: project.deletingLastPathComponent(), to: package)

        // The package's reference, once.
        let referenceID: String
        if let found = objects.first(where: { $0.value["isa"] as? String == "XCLocalSwiftPackageReference" && $0.value["relativePath"] as? String == path }) {
            referenceID = found.key
        } else {
            referenceID = text.freshID()
            let comment = "XCLocalSwiftPackageReference \"\(path)\""
            text.add("\t\t\(referenceID) /* \(comment) */ = {\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = \(PBXText.quoted(path));\n\t\t};\n",
                     toSection: "XCLocalSwiftPackageReference")
            text.append("\(referenceID) /* \(comment) */", to: "packageReferences", of: rootID)
        }

        // The product on every application target that does not have it.
        var linked: [String] = []
        for target in targets {
            let object = objects[target] ?? [:]
            let dependencies = object["packageProductDependencies"] as? [String] ?? []
            if dependencies.contains(where: { objects[$0]?["productName"] as? String == product }) { continue }
            let productID = text.freshID()
            text.add("\t\t\(productID) /* \(product) */ = {\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = \(PBXText.quoted(product));\n\t\t};\n",
                     toSection: "XCSwiftPackageProductDependency")
            let buildFileID = text.freshID()
            text.add("\t\t\(buildFileID) /* \(product) in Frameworks */ = {isa = PBXBuildFile; productRef = \(productID) /* \(product) */; };\n",
                     toSection: "PBXBuildFile")
            text.append("\(productID) /* \(product) */", to: "packageProductDependencies", of: target)
            let phases = object["buildPhases"] as? [String] ?? []
            if let frameworks = phases.first(where: { objects[$0]?["isa"] as? String == "PBXFrameworksBuildPhase" }) {
                text.append("\(buildFileID) /* \(product) in Frameworks */", to: "files", of: frameworks)
            } else {
                let phaseID = text.freshID()
                text.add("\t\t\(phaseID) /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t\(buildFileID) /* \(product) in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n",
                         toSection: "PBXFrameworksBuildPhase")
                text.append("\(phaseID) /* Frameworks */", to: "buildPhases", of: target)
            }
            linked.append(object["name"] as? String ?? target)
        }
        if !linked.isEmpty {
            notes.append("linked \(product) into \(name)'s \(linked.joined(separator: " and "))")
        }

        // A deployment target below the package's, raised: the project's and the application targets' configurations.
        let lists = [root["buildConfigurationList"] as? String] + targets.map { objects[$0]?["buildConfigurationList"] as? String }
        let configurations = lists.compactMap { $0 }.flatMap { objects[$0]?["buildConfigurations"] as? [String] ?? [] }
        for minimum in minimums {
            var raised: Set<String> = []
            for configuration in configurations {
                guard let settings = objects[configuration]?["buildSettings"] as? [String: Any],
                      let current = settings[minimum.setting] as? String,
                      version(current).lexicographicallyPrecedes(version(minimum.version)),
                      let object = text.object(configuration),
                      let block = text.value(of: "buildSettings", in: object), text.bytes[block.start] == 0x7B,
                      let value = text.value(of: minimum.setting, in: (block.start, block.end - 1)) else { continue }
                text.replace(value.start, value.end, with: minimum.version)
                raised.insert(current)
            }
            if !raised.isEmpty {
                notes.append("raised \(name)'s \(minimum.platform) deployment target from \(raised.sorted().joined(separator: " and ")) to \(minimum.version), which the package needs")
            }
        }
        let edited = text.text
        return (edited == original ? nil : edited, notes)
    }

    /// `14.0` → [14, 0], for comparing versions.
    static func version(_ text: String) -> [Int] {
        var parts = text.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return parts
    }

    /// The path from the folder `base` to `target`, with `..` where it climbs: `Packages/RecipeKit`, `../Shared/Kit`.
    static func relativePath(from base: URL, to target: URL) -> String {
        let from = base.path.split(separator: "/").map(String.init)
        let to = target.path.split(separator: "/").map(String.init)
        var common = 0
        while common < from.count, common < to.count, from[common] == to[common] { common += 1 }
        let parts = Array(repeating: "..", count: from.count - common) + to[common...]
        return parts.isEmpty ? "." : parts.joined(separator: "/")
    }
}
