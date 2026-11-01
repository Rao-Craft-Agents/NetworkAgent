//  WHAT: A sample value of a type, said two ways: in Swift, as a type's `preview` builds it, and in JSON, as a test's
//        sample response sends it. One tree, so the JSON a test decodes is exactly the preview it compares with.

import Foundation

indirect enum Sample: Equatable {
    case string(String)
    case integer(Int)
    /// A number with a fraction, as written (`4.5`).
    case number(String)
    case bool(Bool)
    /// Seconds since 1970.
    case date(Int)
    case url(String)
    case uuid(String)
    case data
    case decimal(String)
    case null
    case array([Sample])
    /// Keys and values, each a String or an Int key.
    case dictionary(keys: [Sample], values: [Sample])
    /// `Name.preview`: another type's own sample.
    case preview(String)

    /// The value in Swift, as an argument of an initializer.
    var swift: String {
        switch self {
        case .string(let text): return Self.quoted(text)
        case .integer(let value): return String(value)
        case .number(let text): return text
        case .bool(let value): return value ? "true" : "false"
        case .date(let seconds): return "Date(timeIntervalSince1970: \(Self.grouped(seconds)))"
        case .url(let text): return "URL(string: \(Self.quoted(text)))!"
        case .uuid(let text): return "UUID(uuidString: \(Self.quoted(text)))!"
        case .data: return "Data()"
        case .decimal(let text): return "Decimal(string: \(Self.quoted(text)))!"
        case .null: return "nil"
        case .array(let items): return "[" + items.map(\.swift).joined(separator: ", ") + "]"
        case .dictionary(let keys, let values):
            guard !keys.isEmpty else { return "[:]" }
            return "[" + zip(keys, values).map { "\($0.swift): \($1.swift)" }.joined(separator: ", ") + "]"
        case .preview(let name): return "\(name).preview"
        }
    }

    /// The value in a URL: what a path or query parameter carries.
    var text: String {
        switch self {
        case .string(let text), .number(let text), .url(let text), .uuid(let text), .decimal(let text): return text
        case .integer(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .date(let seconds): return Self.iso8601(seconds)
        case .array(let items): return items.map(\.text).joined(separator: ",")
        default: return ""
        }
    }

    /// `2026-01-01T00:00:00Z` for 1 767 225 600.
    static func iso8601(_ seconds: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    /// A Swift string literal of `text`.
    static func quoted(_ text: String) -> String {
        var out = "\""
        for character in text {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default: out.append(character)
            }
        }
        return out + "\""
    }

    /// A JSON string of `text`.
    static func json(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

    /// `1767225600` → `1_767_225_600`.
    static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        guard digits.count > 4 else { return String(value) }
        var out = ""
        for (index, digit) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out += "_" }
            out.append(digit)
        }
        return (value < 0 ? "-" : "") + out
    }
}
