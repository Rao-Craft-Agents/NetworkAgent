//  WHAT: The app's own types, read off its Swift: each declared struct, class, enum or actor, its stored fields and
//        their types, and the module it is in when a local package declares it (`Packages/<Kit>/Sources/<Module>/`).
//        A refusal reads it to offer the entity line of a type the app declares and the package cannot see.
//  PIN:  READ, NOT COMPILED. Declarations are found by their shape on a line; a type it does not find (a remote
//        package's, Foundation's) is taken as the line wrote it, never refused.

import Foundation

struct AppTypes {
    struct Declared {
        let name: String
        /// Stored fields in order, with their types as written: `created_at: Date`, `author: User`.
        var fields: [(name: String, type: String)] = []
        /// The local package's module that declares it; nil for the app's own.
        var module: String?

        func field(_ name: String) -> String? { fields.first { $0.name == name }?.type }
    }

    var types: [String: Declared] = [:]

    init() {}

    /// Every Swift file under `root`, skipping build products, tests and project bundles.
    init(root: URL) {
        let skipped: Set<String> = [".build", ".git", ".swiftpm", "DerivedData", "node_modules", "Tests", "UITests"]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if skipped.contains(name) || name.hasPrefix(".") || name.hasSuffix(".xcodeproj") || name.hasSuffix(".xcassets") || name.hasSuffix("Tests") {
                walker.skipDescendants(); continue
            }
            guard url.pathExtension == "swift", let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            read(text, module: Self.module(of: url))
        }
    }

    /// The declarations of one file: a type at the start of a line, its stored `let`/`var` fields one level in.
    mutating func read(_ text: String, module: String?) {
        let lines = text.components(separatedBy: "\n")
        let declaration = #"^(?:(?:public|internal|fileprivate|private|open|final|@\w+)\s+)*(struct|class|enum|actor)\s+([A-Z][A-Za-z0-9_]*)"#
        let field = #"^\s+(?:(?:public|internal|fileprivate|private|open|@\w+(?:\([^)]*\))?)\s+)*(?:let|var)\s+([a-z_][A-Za-z0-9_]*)\s*:\s*([^={]+?)\s*(?:=.*)?$"#
        var current: Declared?
        var depth = 0
        func close() { if let done = current, types[done.name] == nil || types[done.name]?.fields.isEmpty == true { types[done.name] = done }; current = nil }
        for line in lines {
            if depth == 0, let match = line.range(of: declaration, options: .regularExpression) {
                close()
                let words = line[match].split(separator: " ")
                if let name = words.last.map(String.init) { current = Declared(name: name, module: module) }
            } else if depth == 1, current != nil, !line.contains("static "), !line.contains("{"),
                      let match = line.range(of: field, options: .regularExpression) {
                let text = String(line[match])
                if let colon = text.firstIndex(of: ":") {
                    let left = text[..<colon].split(separator: " ").last.map(String.init) ?? ""
                    var type = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if let equals = type.firstIndex(of: "=") { type = type[..<equals].trimmingCharacters(in: .whitespaces) }
                    if !left.isEmpty, !type.isEmpty { current?.fields.append((left, type)) }
                }
            }
            depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            if depth <= 0 { depth = 0; if !line.contains("{") { continue } }
        }
        close()
    }

    /// The module a file of a local package compiles into: the folder under `Sources/`, when a Package.swift is above.
    static func module(of url: URL) -> String? {
        let parts = url.pathComponents
        guard let sources = parts.lastIndex(of: "Sources"), sources + 1 < parts.count - 1,
              FileManager.default.fileExists(atPath: NSString.path(withComponents: Array(parts[..<sources])) + "/Package.swift") else { return nil }
        return parts[sources + 1]
    }

    /// The type a field's type names: `User` in `User?`, `[User]` and `Array<User>`.
    static func named(_ type: String) -> String {
        var text = type.replacingOccurrences(of: " ", with: "")
        while text.hasSuffix("?") || text.hasSuffix("!") { text.removeLast() }
        if text.hasPrefix("["), text.hasSuffix("]"), !text.contains(":") { text = String(text.dropFirst().dropLast()) }
        if let open = text.firstIndex(of: "<"), text.hasSuffix(">") { text = String(text[text.index(after: open)..<text.index(before: text.endIndex)]) }
        return text.split(separator: ".").last.map(String.init) ?? text
    }

    /// `name`'s entity line as this agent reads one, from the app's declaration: `User: id String, avatar URL?`.
    func entityLine(_ name: String) -> String? {
        guard let declared = types[name], !declared.fields.isEmpty else { return nil }
        return "\(name): " + declared.fields.map { "\($0.name) \($0.type.replacingOccurrences(of: " ", with: ""))" }.joined(separator: ", ")
    }
}
