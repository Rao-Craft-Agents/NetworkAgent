//  WHAT: One domain type, as an entity line says it: a struct with fields, or an enum with cases.

import Foundation

struct Entity: Equatable, Sendable {
    enum Shape: Equatable, Sendable {
        case record([Field])
        case choice([Case])
    }

    var name: String
    var doc: String?
    var shape: Shape

    var fields: [Field] { if case .record(let fields) = shape { return fields } else { return [] } }
    var cases: [Case] { if case .choice(let cases) = shape { return cases } else { return [] } }
    var isEnum: Bool { if case .choice = shape { return true } else { return false } }
}

struct Field: Equatable, Sendable {
    var name: String
    var type: TypeRef
    var defaultValue: String?
    /// The key it is read from and written to in JSON, when not its name (`@post_id`).
    var key: String?
    var doc: String?
}

struct Case: Equatable, Sendable {
    var name: String
    /// What it carries, in order: a label when the line gave one.
    var values: [(label: String?, type: TypeRef)]
    /// The raw value it is written as, when the line gave one (`top = "top_all"`, `high = 2`).
    var raw: String?
    var doc: String?

    static func == (a: Case, b: Case) -> Bool {
        a.name == b.name && a.raw == b.raw && a.doc == b.doc
            && a.values.map(\.label) == b.values.map(\.label) && a.values.map(\.type) == b.values.map(\.type)
    }
}

/// A Swift type as a line wrote it: a name, an array, a dictionary, optional or not.
indirect enum TypeRef: Equatable, Sendable, CustomStringConvertible {
    case named(String)
    case array(TypeRef)
    case dictionary(TypeRef, TypeRef)
    case optional(TypeRef)

    var description: String {
        switch self {
        case .named(let name): return name
        case .array(let element): return "[\(element)]"
        case .dictionary(let key, let value): return "[\(key): \(value)]"
        case .optional(let wrapped):
            if case .named = wrapped { return "\(wrapped)?" }
            if case .array = wrapped { return "\(wrapped)?" }
            if case .dictionary = wrapped { return "\(wrapped)?" }
            return "(\(wrapped))?"
        }
    }

    var isOptional: Bool { if case .optional = self { return true } else { return false } }

    var unwrapped: TypeRef { if case .optional(let wrapped) = self { return wrapped } else { return self } }

    /// Every type name it mentions.
    var names: [String] {
        switch self {
        case .named(let name): return [name]
        case .array(let element): return element.names
        case .dictionary(let key, let value): return key.names + value.names
        case .optional(let wrapped): return wrapped.names
        }
    }
}
