//  WHAT: The entity line, the one form a model writes a type in:
//
//            Post "a post in a community": id String, title String, score Int = 0, author User?, tags [String]
//            Sort: hot | new | top = "top_all"
//            Media: image(URL) | video(url URL, seconds Double) | link(URL)
//
//        A name, an optional doc in quotes, a colon, then fields split by commas (a struct) or cases split by bars
//        (an enum). A field is a name and a type, `?` for optional, `= value` for a default, `@key` for its JSON key
//        and a trailing quoted doc. `struct` or `enum` before the name says which when a line cannot.
//  PIN:  A LINE THAT IS NOT UNDERSTOOD IS REFUSED WITH THE REASON. A guess would write a type the person did not ask
//        for, and the turn would build it; the model can only fix a line it is told about.

import Foundation

enum EntityLine {
    static func parse(_ line: String) throws -> Entity {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw NetworkError.line(line, "it is empty") }
        var forced: String?
        for keyword in ["struct ", "enum "] where text.hasPrefix(keyword) {
            forced = String(keyword.dropLast()); text = String(text.dropFirst(keyword.count)).trimmingCharacters(in: .whitespaces)
        }
        guard let colon = LineSplit.firstTop(text, ":") else {
            throw NetworkError.line(line, "a type is `Name: fields` or `Name: case | case`, and this has no colon")
        }
        var head = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
        let body = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        var doc: String?
        if let quote = head.firstIndex(of: "\"") {
            doc = String(head[quote...]).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            head = String(head[..<quote]).trimmingCharacters(in: .whitespaces)
        }
        guard SwiftName.isTypeName(head) else { throw NetworkError.line(line, "`\(head)` is not a type name (UpperCamelCase, letters and digits)") }
        guard !body.isEmpty else { throw NetworkError.line(line, "\(head) names no fields or cases") }

        let bars = LineSplit.top(body, on: "|")
        let isEnum = forced == "enum" || (forced == nil && bars.count > 1)
        if isEnum {
            let pieces = bars.count > 1 ? bars : LineSplit.top(body, on: ",")
            let cases = try pieces.map { try parseCase($0, in: line) }
            try unique(cases.map(\.name), what: "case", in: line)
            if cases.contains(where: { !$0.values.isEmpty }), let raw = cases.first(where: { $0.raw != nil }) {
                throw NetworkError.line(line, "case `\(raw.name)` has a raw value while another case carries values; an enum has one or the other")
            }
            return Entity(name: head, doc: doc, shape: .choice(cases))
        }
        let fields = try LineSplit.top(body, on: ",").map { try parseField($0, in: line) }
        try unique(fields.map(\.name), what: "field", in: line)
        return Entity(name: head, doc: doc, shape: .record(fields))
    }

    /// `title String = "x" @name "the headline"`, or `title: String`.
    static func parseField(_ piece: String, in line: String) throws -> Field {
        var text = piece.trimmingCharacters(in: .whitespaces)
        var doc: String?
        if text.hasSuffix("\""), let open = lastQuotedStart(text) {
            let candidate = String(text[open...])
            // A trailing quoted string is a doc only when it does not belong to a default (`= "x"`).
            let before = text[..<open].trimmingCharacters(in: .whitespaces)
            if !before.hasSuffix("=") {
                doc = candidate.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                text = before
            }
        }
        var key: String?
        if let at = lastTopAt(text) {
            key = String(text[text.index(after: at)...]).trimmingCharacters(in: .whitespaces)
            text = String(text[..<at]).trimmingCharacters(in: .whitespaces)
            guard let found = key, !found.isEmpty, !found.contains(" ") else { throw NetworkError.line(line, "`@` in `\(piece)` names no key") }
        }
        var defaultValue: String?
        if let equals = LineSplit.firstTop(text, "=") {
            defaultValue = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            text = String(text[..<equals]).trimmingCharacters(in: .whitespaces)
            if defaultValue?.isEmpty ?? true { throw NetworkError.line(line, "`\(piece)` has `=` and no value") }
        }
        let name: String, typeText: String
        if let colon = LineSplit.firstTop(text, ":") {
            name = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            typeText = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else if let space = text.firstIndex(of: " ") {
            name = String(text[..<space])
            typeText = String(text[space...]).trimmingCharacters(in: .whitespaces)
        } else {
            throw NetworkError.line(line, "`\(piece)` needs a name and a type, like `title String`")
        }
        let bare = name.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        guard SwiftName.isMemberName(bare) else { throw NetworkError.line(line, "`\(name)` is not a field name (lowerCamelCase)") }
        let type = try parseType(typeText, in: line)
        return Field(name: bare, type: type, defaultValue: defaultValue, key: key, doc: doc)
    }

    /// `hot`, `top = "top_all"`, `high = 2`, `video(url URL, seconds Double)`.
    static func parseCase(_ piece: String, in line: String) throws -> Case {
        var text = piece.trimmingCharacters(in: .whitespaces)
        var doc: String?
        if text.hasSuffix("\""), let open = lastQuotedStart(text), !text[..<open].trimmingCharacters(in: .whitespaces).hasSuffix("=") {
            doc = String(text[open...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            text = text[..<open].trimmingCharacters(in: .whitespaces)
        }
        var raw: String?
        if let equals = LineSplit.firstTop(text, "=") {
            raw = String(text[text.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            text = String(text[..<equals]).trimmingCharacters(in: .whitespaces)
        }
        var values: [(label: String?, type: TypeRef)] = []
        if let open = text.firstIndex(of: "("), text.hasSuffix(")") {
            let inside = String(text[text.index(after: open)..<text.index(before: text.endIndex)])
            text = String(text[..<open]).trimmingCharacters(in: .whitespaces)
            for part in LineSplit.top(inside, on: ",") {
                let words = part.split(separator: " ", maxSplits: 1).map(String.init)
                if words.count == 2, SwiftName.isMemberName(words[0]) {
                    values.append((words[0], try parseType(words[1], in: line)))
                } else if let colon = LineSplit.firstTop(part, ":"), SwiftName.isMemberName(String(part[..<colon]).trimmingCharacters(in: .whitespaces)) {
                    values.append((String(part[..<colon]).trimmingCharacters(in: .whitespaces),
                                   try parseType(String(part[part.index(after: colon)...]).trimmingCharacters(in: .whitespaces), in: line)))
                } else {
                    values.append((nil, try parseType(part, in: line)))
                }
            }
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "`"))
        // An API's own spelling (`Hot`, `TopDay`, `NSFW`) is a case named in Swift's spelling that keeps the API's as its
        // raw value: `case topDay = "TopDay"`. Nothing else could be meant, so it is not refused.
        if values.isEmpty, text.range(of: #"^[A-Z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil {
            if raw == nil { raw = "\"\(text)\"" }
            text = SwiftName.lowerCamel(text)
        } else if !values.isEmpty, text.first?.isUppercase == true {
            text = SwiftName.lowerCamel(text)
        }
        guard SwiftName.isMemberName(text) else { throw NetworkError.line(line, "`\(text)` is not a case name (lowerCamelCase)") }
        if raw != nil, !values.isEmpty { throw NetworkError.line(line, "case `\(text)` carries values and a raw value; an enum has one or the other") }
        return Case(name: text, values: values, raw: raw, doc: doc)
    }

    /// `String`, `User?`, `[String]`, `[String: Int]`, `[Post]?`, `Swift.Int`.
    static func parseType(_ text: String, in line: String) throws -> TypeRef {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { throw NetworkError.line(line, "a field has no type") }
        if trimmed.hasSuffix("?") { return .optional(try parseType(String(trimmed.dropLast()), in: line)) }
        if trimmed.hasPrefix("("), trimmed.hasSuffix(")") { return try parseType(String(trimmed.dropFirst().dropLast()), in: line) }
        if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
            let inside = String(trimmed.dropFirst().dropLast())
            if let colon = LineSplit.firstTop(inside, ":") {
                return .dictionary(try parseType(String(inside[..<colon]), in: line), try parseType(String(inside[inside.index(after: colon)...]), in: line))
            }
            return .array(try parseType(inside, in: line))
        }
        let aliases = ["string": "String", "int": "Int", "integer": "Int", "double": "Double", "float": "Double", "number": "Double",
                       "bool": "Bool", "boolean": "Bool", "date": "Date", "url": "URL", "uuid": "UUID", "data": "Data"]
        let name = aliases[trimmed.lowercased()] ?? trimmed
        guard name.split(separator: ".").allSatisfy({ SwiftName.isTypeName(String($0)) }) else {
            throw NetworkError.line(line, "`\(trimmed)` is not a type")
        }
        return .named(name)
    }

    private static func unique(_ names: [String], what: String, in line: String) throws {
        var seen: Set<String> = []
        for name in names where !seen.insert(name).inserted { throw NetworkError.line(line, "the \(what) `\(name)` is named twice") }
    }

    /// Where the last quoted string in `text` begins, when `text` ends with its closing quote.
    private static func lastQuotedStart(_ text: String) -> String.Index? {
        guard text.hasSuffix("\""), text.count >= 2 else { return nil }
        var index = text.index(before: text.index(before: text.endIndex))
        while true {
            if text[index] == "\"" { return index }
            if index == text.startIndex { return nil }
            index = text.index(before: index)
        }
    }

    /// The last `@` outside brackets and quotes.
    private static func lastTopAt(_ text: String) -> String.Index? {
        var found: String.Index?, depth = 0, quoted = false
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if c == "\"" { quoted.toggle() } else if !quoted {
                if "[({".contains(c) { depth += 1 } else if "])}".contains(c) { depth = max(0, depth - 1) }
                else if c == "@" && depth == 0 { found = index }
            }
            index = text.index(after: index)
        }
        return found
    }
}
