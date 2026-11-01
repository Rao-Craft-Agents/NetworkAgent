//  WHAT: A local package added to a Swift package's manifest: `.package(path:)` in the package's dependencies, the
//        product in the dependencies of every regular and executable target, and the platforms raised to the
//        package's (iOS 17, macOS 14) where they are lower.
//  PIN:  ONCE, AND ONLY WHERE THE MANIFEST SAYS IT PLAINLY. A dependency already there is not added again; a manifest
//        whose dependencies or targets are not written as lists in `Package(…)` is left alone, with a note saying
//        what to add by hand.

import Foundation

enum ManifestLink {
    static func link(manifest: URL, package: URL, product: String) throws -> (text: String?, notes: [String]) {
        let original = try String(contentsOf: manifest, encoding: .utf8)
        var source = SwiftSource(original)
        let path = XcodeLink.relativePath(from: manifest.deletingLastPathComponent(), to: package)
        let identity = package.lastPathComponent
        let addByHand = "add `.package(path: \"\(path)\")` and `.product(name: \"\(product)\", package: \"\(identity)\")` to Package.swift by hand"
        guard let call = source.find("Package("), let open = source.find("(", from: call), let close = source.matching(open) else {
            return (nil, ["Package.swift has no `Package(…)` to add \(product) to: \(addByHand)"])
        }
        let arguments = source.items(open, close)
        var edits: [(start: Int, end: Int, text: String)] = []
        var notes: [String] = []
        let indent = arguments.first.map { source.indentation(at: $0.start) } ?? "    "

        // The package's dependency.
        let dependency = ".package(path: \(Sample.quoted(path)))"
        if source.find("path: \(Sample.quoted(path))") == nil {
            if let dependencies = arguments.first(where: { $0.label == "dependencies" }) {
                guard source.bytes[dependencies.value] == 0x5B, let end = source.matching(dependencies.value) else {
                    return (nil, ["Package.swift's dependencies are not a list in `Package(…)`: \(addByHand)"])
                }
                edits.append(insertion(dependency, intoListAt: dependencies.value, closing: end, in: source))
            } else if let targets = arguments.first(where: { $0.label == "targets" }) {
                edits.append((targets.start, targets.start, "dependencies: [\n\(indent)    \(dependency),\n\(indent)],\n\(indent)"))
            } else {
                return (nil, ["Package.swift has no targets to add \(product) to"])
            }
        }

        // The product, in every regular and executable target.
        var added: [String] = []
        if let targets = arguments.first(where: { $0.label == "targets" }) {
            guard source.bytes[targets.value] == 0x5B, let end = source.matching(targets.value) else {
                return (nil, ["Package.swift's targets are not a list in `Package(…)`: \(addByHand)"])
            }
            let productText = ".product(name: \(Sample.quoted(product)), package: \(Sample.quoted(identity)))"
            for target in source.items(targets.value, end) {
                let head = source.slice(target.start, min(target.end, target.start + 20))
                guard head.hasPrefix(".target(") || head.hasPrefix(".executableTarget("),
                      let targetOpen = source.find("(", from: target.start), let targetClose = source.matching(targetOpen) else { continue }
                let targetArguments = source.items(targetOpen, targetClose)
                let name = targetArguments.first { $0.label == "name" }.map { source.slice($0.value, $0.end) } ?? "a target"
                if let dependencies = targetArguments.first(where: { $0.label == "dependencies" }) {
                    guard source.bytes[dependencies.value] == 0x5B, let listEnd = source.matching(dependencies.value) else {
                        notes.append("the target \(name) lists its dependencies some other way: add \(productText) to it by hand")
                        continue
                    }
                    if source.slice(dependencies.value, listEnd).contains("name: \(Sample.quoted(product))") { continue }
                    edits.append(insertion(productText, intoListAt: dependencies.value, closing: listEnd, in: source))
                } else if let nameArgument = targetArguments.first(where: { $0.label == "name" }) {
                    edits.append((nameArgument.end, nameArgument.end, ", dependencies: [\(productText)]"))
                } else {
                    continue
                }
                added.append(name.trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            }
        }

        // The platforms, raised where they are lower than the package's.
        let minimums = [("iOS", 17), ("macOS", 14)]
        if let platforms = arguments.first(where: { $0.label == "platforms" }) {
            if source.bytes[platforms.value] == 0x5B, let end = source.matching(platforms.value) {
                for platform in source.items(platforms.value, end) {
                    let text = source.slice(platform.start, platform.end)
                    for (name, minimum) in minimums where text.hasPrefix(".\(name)(") {
                        if let major = majorVersion(text), major < minimum {
                            edits.append((platform.start, platform.end, ".\(name)(.v\(minimum))"))
                            notes.append("raised Package.swift's \(name) platform to \(minimum), which \(product) needs")
                        }
                    }
                }
            }
        } else if let name = arguments.first(where: { $0.label == "name" }) {
            let after = arguments.first(where: { $0.label == "defaultLocalization" }) ?? name
            edits.append((after.end, after.end, ",\n\(indent)platforms: [.iOS(.v17), .macOS(.v14)]"))
            notes.append("gave Package.swift the platforms iOS 17 and macOS 14, which \(product) needs")
        }

        source.apply(edits)
        if !added.isEmpty { notes.insert("added \(product) to Package.swift's \(added.joined(separator: ", "))", at: 0) }
        let edited = source.text
        return (edited == original ? nil : edited, notes)
    }

    /// `text` added as the last element of the list between `open` and `close`, in the list's own layout.
    private static func insertion(_ text: String, intoListAt open: Int, closing close: Int, in source: SwiftSource) -> (start: Int, end: Int, text: String) {
        let items = source.items(open, close)
        guard let last = items.last else { return (open + 1, open + 1, text) }
        let inside = source.slice(open, close)
        if inside.contains("\n") {
            let indent = source.indentation(at: last.start)
            // After the last element (and its comma, if it has one), on a line of its own.
            var end = last.end
            let hasComma = source.skip(end) < source.bytes.count && source.bytes[source.skip(end)] == 0x2C
            if hasComma { end = source.skip(end) + 1 }
            return (end, end, (hasComma ? "" : ",") + "\n\(indent)\(text)" + (hasComma ? "," : ""))
        }
        return (last.end, last.end, ", \(text)")
    }

    /// `.macOS(.v13)` → 13, `.iOS(.v16_4)` → 16, `.macOS("13.0")` → 13.
    static func majorVersion(_ text: String) -> Int? {
        guard let range = text.range(of: #"(?:\.v|")(\d+)"#, options: .regularExpression) else { return nil }
        let digits = text[range].drop { !$0.isNumber }
        return Int(digits)
    }
}
