//  WHAT: The package's DTOs, one file a type from its entity line (ModelsAgent's line, read by the same parser): each
//        public, Codable, Hashable and Sendable (Identifiable with an `id`; CaseIterable and a query value when an
//        enum carries nothing), with an explicit initializer and a `preview`; and each type's sample, said in JSON for
//        the tests.
//  PIN:  A DEFAULT IS A DEFAULT IN JSON TOO. A field with `= value` decodes as that value when the JSON leaves it out,
//        and an enum field with a default or a `?` reads a case this version does not know as the default or nil, so
//        a server that adds a key or a case does not break a response the app could read before.
//  PIN:  KEYS ARE WRITTEN, NOT CONVERTED. `snake` writes each field's snake_case key into `CodingKeys`
//        (`avatarURL` reads `avatar_url`); a decoder's `convertFromSnakeCase` would read `avatarUrl` and miss it.
//  PIN:  PREVIEWS NEVER NAME EACH OTHER IN A LOOP (ModelsAgent's rule): a value that may be empty names another
//        type's preview only when that type cannot reach back, or sorts after; two static values that read each other
//        deadlock.

import Foundation

struct ModelEmitter {
    var coding: NetworkCoding = .exact
    /// Every type of the package, by name.
    var entities: [String: Entity] = [:]
    /// The types whose preview can be made: every field sampled (`resolvePreviews`).
    var previewable: Set<String> = []

    init(entities: [Entity], coding: NetworkCoding) {
        self.coding = coding
        self.entities = Dictionary(entities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        resolvePreviews()
    }

    /// Works out which types get a preview: a type whose field has no sample has none, and neither does one whose
    /// required field is such a type; repeated until nothing changes.
    mutating func resolvePreviews() {
        var candidates = Set(entities.keys)
        while true {
            previewable = candidates
            let next = candidates.filter { name in shape(of: entities[name]!) != nil }
            if next == candidates { break }
            candidates = next
        }
    }

    /// Whether `from` mentions `to` in its fields or cases, directly or through other types.
    func reaches(_ from: String, _ to: String) -> Bool {
        var seen: Set<String> = [], stack = [from]
        while let name = stack.popLast() {
            guard seen.insert(name).inserted, let entity = entities[name] else { continue }
            let mentioned = entity.fields.flatMap(\.type.names) + entity.cases.flatMap { $0.values.flatMap(\.type.names) }
            if mentioned.contains(to) { return true }
            stack += mentioned
        }
        return false
    }

    /// Types that require each other through fields that must hold a value: none of them can ever be made.
    func requiredCycles() -> [[String]] {
        func required(_ entity: Entity) -> [String] {
            let types = entity.fields.map(\.type) + (entity.cases.count == 1 ? entity.cases[0].values.map(\.type) : [])
            return types.compactMap { if case .named(let name) = $0, entities[name] != nil { return name } else { return nil } }
        }
        var cycles: [[String]] = [], reported: Set<String> = []
        for name in entities.keys.sorted() where !reported.contains(name) {
            var stack: [(String, [String])] = [(name, [name])]
            var visited: Set<String> = []
            while let (current, trail) = stack.popLast() {
                for next in required(entities[current]!) {
                    if next == name { cycles.append(trail); reported.formUnion(trail); stack.removeAll(); break }
                    if visited.insert(next).inserted { stack.append((next, trail + [next])) }
                }
            }
        }
        return cycles
    }

    /// The types a value of `type` holds in place: a named type, or an optional's; an array or a dictionary holds its
    /// elements elsewhere, so it breaks a loop.
    private func inline(_ type: TypeRef) -> [String] {
        switch type {
        case .named(let name): return [name]
        case .optional(let wrapped): return inline(wrapped)
        case .array, .dictionary: return []
        }
    }

    /// Whether a value of `from` holds, in place, a value of `to`: through fields and cases, not through lists.
    func holds(_ from: String, _ to: String) -> Bool {
        var seen: Set<String> = [], stack = [from]
        while let name = stack.popLast() {
            guard seen.insert(name).inserted, let entity = entities[name] else { continue }
            let held = entity.fields.flatMap { inline($0.type) } + entity.cases.flatMap { $0.values.flatMap { inline($0.type) } }
            if held.contains(to) { return true }
            stack += held
        }
        return false
    }

    /// The fields of `entity` a Swift struct cannot hold in place, since their type holds `entity` again (a `Status`'s
    /// `reblog: Status?`): they are kept `@Indirect`.
    func indirectFields(_ entity: Entity) -> Set<String> {
        Set(entity.fields.filter { field in inline(field.type).contains { $0 == entity.name || holds($0, entity.name) } }.map(\.name))
    }

    /// Whether `item` carries a value that holds its enum again: such a case is `indirect`.
    func isIndirect(_ item: Case, of entity: Entity) -> Bool {
        item.values.contains { value in inline(value.type).contains { $0 == entity.name || holds($0, entity.name) } }
    }

    /// Whether any type of the package needs `Indirect`.
    var needsIndirect: Bool { entities.values.contains { !indirectFields($0).isEmpty } }

    // MARK: - A type's file

    func emit(_ entity: Entity) -> String {
        var lines = ["import Foundation", ""]
        if let doc = entity.doc, !doc.isEmpty { lines.append("/// \(sentence(doc))") }
        switch entity.shape {
        case .record(let fields): lines += record(entity, fields)
        case .choice(let cases): lines += choice(entity, cases)
        }
        if let value = previewSwift(entity) {
            lines += ["", "extension \(entity.name) {", "    /// \(article(entity.name).capitalized) \(entity.name) to preview and test with."]
            lines += previewLines(entity, value)
            lines.append("}")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `public static let preview: T = T(a: 1, b: 2)`, or one argument a line when that is too long.
    private func previewLines(_ entity: Entity, _ value: String) -> [String] {
        let line = "    public static let preview: \(entity.name) = \(value)"
        guard line.count > 120, case .record(let values)? = shape(of: entity), !values.isEmpty else { return [line] }
        let arguments = values.map { "        \(SwiftName.member($0.0.name)): \($0.1.swift)" }
        return ["    public static let preview: \(entity.name) = \(entity.name)("] + arguments.enumerated().map { index, argument in
            argument + (index < arguments.count - 1 ? "," : "")
        } + ["    )"]
    }

    private func record(_ entity: Entity, _ fields: [Field]) -> [String] {
        var conformances = ["Codable", "Hashable"]
        if fields.contains(where: { $0.name == "id" }) { conformances.append("Identifiable") }
        conformances.append("Sendable")
        var lines = ["public struct \(entity.name): \(conformances.joined(separator: ", ")) {"]
        let boxed = indirectFields(entity)
        for field in fields {
            if let doc = field.doc, !doc.isEmpty { lines.append("    /// \(sentence(doc))") }
            let wrapper = boxed.contains(field.name) ? "@Indirect " : ""
            lines.append("    \(wrapper)public var \(SwiftName.member(field.name)): \(field.type)")
        }
        let parameters = fields.map { field -> String in
            var text = "\(SwiftName.member(field.name)): \(field.type)"
            if let value = field.defaultValue { text += " = \(value)" } else if field.type.isOptional { text += " = nil" }
            return text
        }
        let initializer = "    public init(\(parameters.joined(separator: ", "))) {"
        if initializer.count > 120 {
            lines += ["", "    public init("] + parameters.enumerated().map { index, parameter in
                "        \(parameter)" + (index < parameters.count - 1 ? "," : "")
            } + ["    ) {"]
        } else {
            lines += ["", initializer]
        }
        lines += fields.map { "        self.\(SwiftName.member($0.name)) = \(SwiftName.member($0.name))" }
        lines.append("    }")
        let keyed = fields.contains { key(for: $0) != $0.name }
        let lenient = fields.contains { ($0.defaultValue != nil && !$0.type.isOptional) || tolerant($0) }
        if keyed || lenient {
            lines += ["", "    enum CodingKeys: String, CodingKey {"]
            lines += fields.map { field in
                let key = self.key(for: field)
                return key == field.name ? "        case \(SwiftName.member(field.name))" : "        case \(SwiftName.member(field.name)) = \(Sample.quoted(key))"
            }
            lines.append("    }")
        }
        if lenient {
            lines += ["", "    public init(from decoder: Decoder) throws {", "        let container = try decoder.container(keyedBy: CodingKeys.self)"]
            for field in fields {
                let name = SwiftName.member(field.name)
                let read = "container.decodeIfPresent(\(field.type.unwrapped).self, forKey: .\(name))"
                if tolerant(field) {
                    lines.append("        \(name) = (try? \(read)) ?? \(field.defaultValue ?? "nil")")
                } else if field.type.isOptional {
                    lines.append("        \(name) = try \(read)\(field.defaultValue.map { " ?? \($0)" } ?? "")")
                } else if let value = field.defaultValue {
                    lines.append("        \(name) = try \(read) ?? \(value)")
                } else {
                    lines.append("        \(name) = try container.decode(\(field.type).self, forKey: .\(name))")
                }
            }
            lines.append("    }")
        }
        lines.append("}")
        return lines
    }

    /// An enum field that may be left empty (a default or a `?`): an unknown case reads as that, not as a failure.
    func tolerant(_ field: Field) -> Bool {
        guard field.defaultValue != nil || field.type.isOptional, case .named(let name) = field.type.unwrapped,
              let entity = entities[name], entity.isEnum else { return false }
        return true
    }

    private func choice(_ entity: Entity, _ cases: [Case]) -> [String] {
        var lines: [String] = []
        if cases.contains(where: { !$0.values.isEmpty }) {
            lines.append("public enum \(entity.name): Codable, Hashable, Sendable {")
            for item in cases {
                if let doc = item.doc, !doc.isEmpty { lines.append("    /// \(sentence(doc))") }
                if item.values.isEmpty {
                    lines.append("    case \(SwiftName.member(item.name))")
                } else {
                    let values = item.values.map { value in value.label.map { "\($0): \(value.type)" } ?? "\(value.type)" }
                    let keyword = isIndirect(item, of: entity) ? "indirect case" : "case"
                    lines.append("    \(keyword) \(SwiftName.member(item.name))(\(values.joined(separator: ", ")))")
                }
            }
            lines.append("}")
            return lines
        }
        let integers = isIntegerEnum(entity)
        lines.append("public enum \(entity.name): \(integers ? "Int" : "String"), Codable, CaseIterable, Hashable, Identifiable, Sendable, QueryValue {")
        for item in cases {
            if let doc = item.doc, !doc.isEmpty { lines.append("    /// \(sentence(doc))") }
            var line = "    case \(SwiftName.member(item.name))"
            let raw = rawValue(of: item, in: entity)
            if integers {
                if let value = item.raw { line += " = \(value)" }
            } else if raw != item.name {
                line += " = \(Sample.quoted(raw))"
            }
            lines.append(line)
        }
        lines += ["", "    public var id: Self { self }", "}"]
        return lines
    }

    func isIntegerEnum(_ entity: Entity) -> Bool {
        entity.cases.allSatisfy { $0.raw == nil || Int($0.raw!) != nil } && entity.cases.contains { $0.raw != nil }
    }

    /// The text a String enum's case is written as: its raw value, else its name (snake_case under `snake`).
    func rawValue(of item: Case, in entity: Entity) -> String {
        if let raw = item.raw {
            return raw.hasPrefix("\"") && raw.hasSuffix("\"") && raw.count >= 2 ? String(raw.dropFirst().dropLast()) : raw
        }
        return coding == .snake ? SwiftName.snake(item.name) : item.name
    }

    /// The JSON key of `field`: its `@key`, else its name (snake_case under `snake`).
    func key(for field: Field) -> String {
        if let key = field.key { return key }
        return coding == .snake ? SwiftName.snake(field.name) : field.name
    }

    // MARK: - Samples

    /// A type's sample: each field's value, or the first case's.
    enum Shape {
        case record([(Field, Sample)])
        case choice(Case, [(String?, Sample)])
    }

    /// The type's sample, or nil when a field's type has none.
    func shape(of entity: Entity) -> Shape? {
        switch entity.shape {
        case .record(let fields):
            var values: [(Field, Sample)] = []
            for field in fields {
                guard let value = sample(field.type, field: field.name, owner: entity.name) else { return nil }
                values.append((field, value))
            }
            return .record(values)
        case .choice(let cases):
            guard let first = cases.first else { return nil }
            var values: [(String?, Sample)] = []
            for (index, value) in first.values.enumerated() {
                guard let made = sample(value.type, field: value.label ?? "value\(index)", owner: entity.name) else { return nil }
                values.append((value.label, made))
            }
            return .choice(first, values)
        }
    }

    /// `Recipe(id: "recipe-1", …)`, `Course.starter`, `Media.photo(URL(…)!)`: what `preview` is.
    func previewSwift(_ entity: Entity) -> String? {
        guard previewable.contains(entity.name), let shape = shape(of: entity) else { return nil }
        switch shape {
        case .record(let values):
            return "\(entity.name)(" + values.map { "\(SwiftName.member($0.0.name)): \($0.1.swift)" }.joined(separator: ", ") + ")"
        case .choice(let item, let values):
            if values.isEmpty, entity.cases.allSatisfy({ $0.values.isEmpty }) { return "\(entity.name).\(SwiftName.member(item.name))" }
            if values.isEmpty { return "\(entity.name).\(SwiftName.member(item.name))" }
            return "\(entity.name).\(SwiftName.member(item.name))(" + values.map { label, value in label.map { "\($0): \(value.swift)" } ?? value.swift }.joined(separator: ", ") + ")"
        }
    }

    /// A sample of `type` for the field `field` of `owner`; nil when there is none to make.
    func sample(_ type: TypeRef, field: String, owner: String, required: Bool = true) -> Sample? {
        switch type {
        case .optional(let wrapped):
            return sample(wrapped, field: field, owner: owner, required: false) ?? .null
        case .array(let element):
            return sample(element, field: singular(field), owner: owner, required: false).map { .array([$0]) } ?? .array([])
        case .dictionary(let key, let value):
            guard [.named("String"), .named("Int")].contains(key),
                  let k = sample(key, field: "key", owner: owner, required: false),
                  let v = sample(value, field: field, owner: owner, required: false) else { return .dictionary(keys: [], values: []) }
            return .dictionary(keys: [k], values: [v])
        case .named(let name):
            if let value = standard(name, field: field, owner: owner) { return value }
            if name == owner { return nil }
            guard entities[name] != nil, previewable.contains(name) else { return nil }
            if required || !reaches(name, owner) || owner < name { return .preview(name) }
            return nil
        }
    }

    private func standard(_ name: String, field: String, owner: String) -> Sample? {
        let lower = field.lowercased(), isID = field == "id" || field.hasSuffix("ID") || field.hasSuffix("Id")
        switch name {
        case "String":
            if isID { return .string("\(SwiftName.snake(owner).replacingOccurrences(of: "_", with: "-"))-1") }
            if lower.contains("email") { return .string("person@example.com") }
            if lower.hasSuffix("url") || lower.contains("link") || lower.contains("href") { return .string("https://example.com/\(SwiftName.snake(field))") }
            return .string("Sample \(SwiftName.words(field))")
        case "Int", "Int64", "Int32", "Int16", "Int8", "UInt", "UInt64", "UInt32", "UInt16", "UInt8": return .integer(isID ? 1 : 42)
        case "Double", "Float": return .number("4.5")
        case "Decimal": return .decimal("4.5")
        case "Bool": return .bool(false)
        case "Date": return .date(1_767_225_600)
        case "URL": return .url("https://example.com/\(SwiftName.snake(field))")
        case "UUID": return .uuid("00000000-0000-0000-0000-000000000001")
        case "Data": return .data
        default: return nil
        }
    }

    private func singular(_ name: String) -> String {
        name.hasSuffix("ies") ? String(name.dropLast(3)) + "y" : name.hasSuffix("s") && !name.hasSuffix("ss") ? String(name.dropLast()) : name
    }

    // MARK: - JSON

    /// `sample` as JSON, another type's preview written out in full, `indent` spaces deep.
    func json(_ sample: Sample, indent: Int = 0) -> String {
        let pad = String(repeating: " ", count: indent + 2), end = String(repeating: " ", count: indent)
        switch sample {
        case .string(let text), .url(let text), .uuid(let text): return Sample.json(text)
        case .integer(let value): return String(value)
        case .number(let text), .decimal(let text): return text
        case .bool(let value): return value ? "true" : "false"
        case .date(let seconds): return Sample.json(Sample.iso8601(seconds))
        case .data: return "\"\""
        case .null: return "null"
        case .array(let items):
            guard !items.isEmpty else { return "[]" }
            return "[\n" + items.map { pad + json($0, indent: indent + 2) }.joined(separator: ",\n") + "\n\(end)]"
        case .dictionary(let keys, let values):
            guard !keys.isEmpty else { return "{}" }
            return "{\n" + zip(keys, values).map { "\(pad)\(Sample.json($0.text)): \(json($1, indent: indent + 2))" }.joined(separator: ",\n") + "\n\(end)}"
        case .preview(let name):
            guard let entity = entities[name] else { return "null" }
            return json(entity, indent: indent)
        }
    }

    /// A type's preview as JSON: an object of its fields under their keys, a case's raw value, or a case with values
    /// as Swift writes one (`{"video": {"url": …}}`).
    func json(_ entity: Entity, indent: Int = 0, emptying: String? = nil, nulling: String? = nil) -> String {
        guard let shape = shape(of: entity) else { return "null" }
        let pad = String(repeating: " ", count: indent + 2), end = String(repeating: " ", count: indent)
        switch shape {
        case .record(let values):
            guard !values.isEmpty else { return "{}" }
            let members = values.map { field, value -> String in
                var value = value
                if field.name == emptying { value = .array([]) }
                if field.name == nulling { value = .null }
                return "\(pad)\(Sample.json(key(for: field))): \(json(value, indent: indent + 2))"
            }
            return "{\n" + members.joined(separator: ",\n") + "\n\(end)}"
        case .choice(let item, let values):
            if entity.cases.allSatisfy({ $0.values.isEmpty }) {
                return isIntegerEnum(entity) ? (item.raw ?? "0") : Sample.json(rawValue(of: item, in: entity))
            }
            let inner = values.enumerated().map { index, pair in
                "\(pad)  \(Sample.json(pair.0 ?? "_\(index)")): \(json(pair.1, indent: indent + 4))"
            }
            let body = inner.isEmpty ? "{}" : "{\n" + inner.joined(separator: ",\n") + "\n\(pad)}"
            return "{\n\(pad)\(Sample.json(item.name)): \(body)\n\(end)}"
        }
    }

    /// The JSON keys a type's preview is written with: the fields that are not nil.
    func encodedKeys(_ entity: Entity) -> [String] {
        guard case .record(let values)? = shape(of: entity) else { return [] }
        return values.filter { $0.1 != .null }.map { key(for: $0.0) }
    }

    // MARK: - Words

    private func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        let capped = first.uppercased() + text.dropFirst()
        return capped.hasSuffix(".") ? capped : capped + "."
    }

    private func article(_ word: String) -> String {
        guard let first = word.first?.lowercased() else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }
}
