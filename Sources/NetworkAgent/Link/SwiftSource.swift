//  WHAT: Swift source read just enough to edit a manifest: the end of a bracket, the arguments of a call and their
//        labels, past strings (plain, multi-line and raw) and comments.

import Foundation

struct SwiftSource {
    private(set) var bytes: [UInt8]

    init(_ text: String) { bytes = Array(text.utf8) }

    var text: String { String(decoding: bytes, as: UTF8.self) }

    /// An argument of a call, or an element of a list: where it starts and ends, and its label when it has one.
    struct Item {
        var start: Int
        var end: Int
        var label: String?
        /// Where the value starts: past the label and its colon.
        var value: Int
    }

    /// The index past whitespace and comments from `index`.
    func skip(_ index: Int) -> Int {
        var i = index
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D {
                i += 1
            } else if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F {
                while i < bytes.count, bytes[i] != 0x0A { i += 1 }
            } else if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A {
                var depth = 0
                repeat {
                    if bytes[i] == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2A { depth += 1; i += 2; continue }
                    if bytes[i] == 0x2A, i + 1 < bytes.count, bytes[i + 1] == 0x2F { depth -= 1; i += 2; continue }
                    i += 1
                } while depth > 0 && i < bytes.count
            } else {
                return i
            }
        }
        return bytes.count
    }

    /// The index past the string literal that starts at `index` (`"`, `"""` or `#…"`).
    func stringEnd(_ index: Int) -> Int {
        var i = index, hashes = 0
        while i < bytes.count, bytes[i] == 0x23 { hashes += 1; i += 1 }
        let triple = i + 2 < bytes.count && bytes[i] == 0x22 && bytes[i + 1] == 0x22 && bytes[i + 2] == 0x22
        i += triple ? 3 : 1
        let close: [UInt8] = (triple ? [0x22, 0x22, 0x22] : [0x22]) + Array(repeating: 0x23, count: hashes)
        while i < bytes.count {
            if bytes[i] == 0x5C, hashes == 0 { i += 2; continue }
            if i + close.count <= bytes.count, Array(bytes[i..<i + close.count]) == close { return i + close.count }
            i += 1
        }
        return bytes.count
    }

    /// The index of the bracket that closes the one at `open`.
    func matching(_ open: Int) -> Int? {
        var depth = 0, i = open
        while i < bytes.count {
            let byte = bytes[i]
            if byte == 0x22 || (byte == 0x23 && i + 1 < bytes.count && (bytes[i + 1] == 0x22 || bytes[i + 1] == 0x23)) { i = stringEnd(i); continue }
            if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F || bytes[i + 1] == 0x2A { i = skip(i); continue }
            if byte == 0x28 || byte == 0x5B || byte == 0x7B { depth += 1 }
            if byte == 0x29 || byte == 0x5D || byte == 0x7D {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }

    /// The items between the bracket at `open` and the one at `close`, split at its top-level commas.
    func items(_ open: Int, _ close: Int) -> [Item] {
        var items: [Item] = []
        var start = skip(open + 1), i = start
        func finish(_ end: Int) {
            var last = end
            while last > start, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[last - 1]) { last -= 1 }
            guard last > start else { return }
            var label: String?, value = start
            var j = start
            while j < last, bytes[j] == 0x5F || (bytes[j] >= 0x30 && bytes[j] <= 0x39) || ((bytes[j] | 0x20) >= 0x61 && (bytes[j] | 0x20) <= 0x7A) { j += 1 }
            let colon = skip(j)
            if j > start, colon < last, bytes[colon] == 0x3A, bytes[start] != 0x2E {
                label = String(decoding: bytes[start..<j], as: UTF8.self)
                value = skip(colon + 1)
            }
            items.append(Item(start: start, end: last, label: label, value: value))
        }
        while i < close {
            let byte = bytes[i]
            if byte == 0x22 || (byte == 0x23 && i + 1 < bytes.count && (bytes[i + 1] == 0x22 || bytes[i + 1] == 0x23)) { i = stringEnd(i); continue }
            if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F || bytes[i + 1] == 0x2A { i = skip(i); continue }
            if byte == 0x28 || byte == 0x5B || byte == 0x7B { i = (matching(i) ?? close) + 1; continue }
            if byte == 0x2C {
                finish(i)
                start = skip(i + 1)
                i = start
                continue
            }
            i += 1
        }
        finish(close)
        return items
    }

    /// The first index of `token` outside strings and comments, from `start`.
    func find(_ token: String, from start: Int = 0) -> Int? {
        let needle = Array(token.utf8)
        var i = start
        while i + needle.count <= bytes.count {
            let byte = bytes[i]
            if byte == 0x22 || (byte == 0x23 && i + 1 < bytes.count && (bytes[i + 1] == 0x22 || bytes[i + 1] == 0x23)) { i = stringEnd(i); continue }
            if byte == 0x2F, i + 1 < bytes.count, bytes[i + 1] == 0x2F || bytes[i + 1] == 0x2A { i = skip(i); continue }
            if Array(bytes[i..<i + needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    /// The text from `start` to `end`.
    func slice(_ start: Int, _ end: Int) -> String { String(decoding: bytes[start..<end], as: UTF8.self) }

    /// The spaces that begin the line holding `index`.
    func indentation(at index: Int) -> String {
        var start = index
        while start > 0, bytes[start - 1] != 0x0A { start -= 1 }
        var end = start
        while end < bytes.count, bytes[end] == 0x20 || bytes[end] == 0x09 { end += 1 }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    /// Applies `edits` (an index and the text inserted there, or a range replaced), from the last to the first, so
    /// each index is read in the text as it was.
    mutating func apply(_ edits: [(start: Int, end: Int, text: String)]) {
        for edit in edits.sorted(by: { $0.start > $1.start }) {
            bytes.replaceSubrange(edit.start..<edit.end, with: Array(edit.text.utf8))
        }
    }
}
