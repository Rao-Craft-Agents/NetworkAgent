//  WHAT: An Xcode project file as text that can be edited in place: an object found by its id, a key's value found in
//        an object, an item added to a list, a key added to an object, objects added to their section, each in the
//        layout Xcode writes.
//  PIN:  TEXT, NOT A REWRITE. Only what a link needs is added; every other byte stays, so the project's diff is the
//        link and nothing else, and Xcode reads the file as it wrote it.

import Foundation

struct PBXText {
    private(set) var bytes: [UInt8]

    init(_ text: String) { bytes = Array(text.utf8) }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    // MARK: - Reading

    /// The index of the first byte at or after `index` that is not whitespace or a comment.
    func skipTrivia(_ index: Int) -> Int {
        var i = index
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                i += 1
            } else if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A {   // /*
                i += 2
                while i + 1 < bytes.count, !(bytes[i] == 0x2A && bytes[i + 1] == 0x2F) { i += 1 }
                i += 2
            } else if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F {   // //
                while i < bytes.count, bytes[i] != 0x0A { i += 1 }
            } else {
                return i
            }
        }
        return bytes.count
    }

    /// The index just past the value that starts at `index`: a quoted string, a word, a `{…}` or a `(…)`.
    func valueEnd(_ index: Int) -> Int {
        guard index < bytes.count else { return index }
        switch bytes[index] {
        case 0x22:   // "
            var i = index + 1
            while i < bytes.count, bytes[i] != 0x22 { i += bytes[i] == 0x5C ? 2 : 1 }
            return min(i + 1, bytes.count)
        case 0x7B, 0x28:   // { (
            var depth = 0, i = index
            while i < bytes.count {
                let byte = bytes[i]
                if byte == 0x22 { i = valueEnd(i); continue }
                if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A || bytes[i + 1] == 0x2F { i = skipTrivia(i); continue }
                if byte == 0x7B || byte == 0x28 { depth += 1 }
                if byte == 0x7D || byte == 0x29 {
                    depth -= 1
                    if depth == 0 { return i + 1 }
                }
                i += 1
            }
            return bytes.count
        default:
            var i = index
            while i < bytes.count, !Self.endsWord(bytes[i]) {
                if bytes[i] == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A { break }
                i += 1
            }
            return i
        }
    }

    private static func endsWord(_ byte: UInt8) -> Bool {
        [0x20, 0x09, 0x0A, 0x0D, 0x3B, 0x2C, 0x29, 0x7D, 0x3D].contains(byte)   // space tab \n \r ; , ) } =
    }

    /// The `{` and `}` of the dictionary of the object `id`: where `id` stands as a key, followed by `=`.
    func object(_ id: String) -> (open: Int, close: Int)? {
        let needle = Array(id.utf8)
        var i = 0
        while let found = find(needle, from: i) {
            i = found + needle.count
            let before = found == 0 ? 0x0A : bytes[found - 1]
            guard [0x20, 0x09, 0x0A].contains(before) else { continue }
            let equals = skipTrivia(i)
            guard equals < bytes.count, bytes[equals] == 0x3D else { continue }
            let open = skipTrivia(equals + 1)
            guard open < bytes.count, bytes[open] == 0x7B else { continue }
            return (open, valueEnd(open) - 1)
        }
        return nil
    }

    /// The start and end of `key`'s value in the dictionary that opens at `open`.
    func value(of key: String, in dictionary: (open: Int, close: Int)) -> (start: Int, end: Int)? {
        var i = skipTrivia(dictionary.open + 1)
        while i < dictionary.close {
            let keyEnd = valueEnd(i)
            var name = String(decoding: bytes[i..<keyEnd], as: UTF8.self)
            if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
            let equals = skipTrivia(keyEnd)
            guard equals < bytes.count, bytes[equals] == 0x3D else { return nil }
            let start = skipTrivia(equals + 1)
            let end = valueEnd(start)
            if name == key { return (start, end) }
            let semicolon = skipTrivia(end)
            guard semicolon < bytes.count, bytes[semicolon] == 0x3B else { return nil }
            i = skipTrivia(semicolon + 1)
        }
        return nil
    }

    /// The tabs and spaces that begin the line holding `index`.
    func indentation(at index: Int) -> String {
        var start = index
        while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
        var end = start
        while end < bytes.count, bytes[end] == 0x09 || bytes[end] == 0x20 { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    func find(_ needle: [UInt8], from start: Int = 0) -> Int? {
        guard !needle.isEmpty, needle.count <= bytes.count else { return nil }
        var i = start
        while i <= bytes.count - needle.count {
            if bytes[i] == needle[0], Array(bytes[i..<i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    func contains(_ text: String) -> Bool { find(Array(text.utf8)) != nil }

    // MARK: - Editing

    mutating func insert(_ text: String, at index: Int) {
        bytes.insert(contentsOf: Array(text.utf8), at: index)
    }

    mutating func replace(_ start: Int, _ end: Int, with text: String) {
        bytes.replaceSubrange(start..<end, with: Array(text.utf8))
    }

    /// Adds `item` (`ID /* comment */`) to the list `key` of the object `id`, making the list when the object has
    /// none. False when there is no such object.
    @discardableResult
    mutating func append(_ item: String, to key: String, of id: String) -> Bool {
        guard let object = object(id) else { return false }
        if let list = value(of: key, in: object), bytes[list.start] == 0x28 {
            let close = list.end - 1
            let indent = indentation(at: list.start)
            var last = close - 1
            while last > list.start, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[last]) { last -= 1 }
            var newline = close - 1
            while newline > list.start, bytes[newline] != 0x0A { newline -= 1 }
            if newline > list.start, last < newline {
                // The list's last line is the closing one: the item goes on a line before it.
                var text = "\(indent)\t\(item),\n"
                if bytes[last] != 0x28, bytes[last] != 0x2C { text = ",\n" + text; insert(text, at: last + 1); return true }
                insert(text, at: newline + 1)
            } else {
                let comma = bytes[last] != 0x28 && bytes[last] != 0x2C ? "," : ""
                insert("\(comma)\n\(indent)\t\(item),\n\(indent)", at: last + 1)
            }
            return true
        }
        // No list yet: the key goes on a line before the object's closing brace.
        var newline = object.close - 1
        while newline > object.open, bytes[newline] != 0x0A { newline -= 1 }
        let indent = indentation(at: object.close) + "\t"
        insert("\(indent)\(key) = (\n\(indent)\t\(item),\n\(indent));\n", at: newline + 1)
        return true
    }

    /// Adds `text` (whole object lines) to the section of `isa`, making the section, in its sorted place, when the
    /// file has none.
    mutating func add(_ text: String, toSection isa: String) {
        if let end = find(Array("/* End \(isa) section */".utf8)) {
            insert(text, at: end)
            return
        }
        let section = "/* Begin \(isa) section */\n\(text)/* End \(isa) section */\n"
        var i = 0, insertion: Int?, lastEnd: Int?
        while let begin = find(Array("/* Begin ".utf8), from: i) {
            let nameStart = begin + 9
            var nameEnd = nameStart
            while nameEnd < bytes.count, bytes[nameEnd] != 0x20 { nameEnd += 1 }
            let name = String(decoding: bytes[nameStart..<nameEnd], as: UTF8.self)
            if name > isa, insertion == nil { insertion = begin }
            if let end = find(Array("/* End \(name) section */".utf8), from: nameEnd) {
                lastEnd = end + "/* End \(name) section */".utf8.count + 1
                i = end
            } else {
                i = nameEnd
            }
        }
        if let insertion {
            insert(section + "\n", at: insertion)
        } else if let lastEnd {
            insert("\n" + section, at: min(lastEnd, bytes.count))
        }
    }

    /// A 24-digit hex id no object of the file has.
    func freshID() -> String {
        while true {
            let id = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").prefix(24).uppercased()
            if !contains(String(id)) { return String(id) }
        }
    }

    /// `text` as a project file writes a value: bare when it is a plain word, quoted otherwise.
    static func quoted(_ text: String) -> String {
        let plain = !text.isEmpty && text.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || "_$/:.-".unicodeScalars.contains($0)
        }
        return plain ? text : "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
