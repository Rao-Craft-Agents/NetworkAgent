//  WHAT: A call's `dates`, read: `DateFormatter` patterns the API writes beside ISO 8601, and the words `seconds` and
//        `milliseconds` for an API that writes dates as numbers since 1970.

import Foundation

struct DateFormats {
    /// The patterns, in the order given.
    var patterns: [String] = []
    /// Whether a number is milliseconds rather than seconds.
    var milliseconds = false
    /// What the API's request bodies write: the first entry, else ISO 8601.
    var writes: Writes = .iso8601

    enum Writes: Equatable { case iso8601, seconds, milliseconds, pattern(String) }

    static let secondWords: Set<String> = ["seconds", "unix", "epoch", "timestamp"]
    static let millisecondWords: Set<String> = ["milliseconds", "millis", "ms"]

    init(_ entries: [String]) {
        for (index, entry) in entries.enumerated() {
            let word = entry.lowercased()
            let kind: Writes
            if Self.secondWords.contains(word) {
                kind = .seconds
            } else if Self.millisecondWords.contains(word) {
                milliseconds = true
                kind = .milliseconds
            } else {
                patterns.append(entry)
                kind = .pattern(entry)
            }
            if index == 0 { writes = kind }
        }
    }

    /// The coding template's blanks, filled.
    func fill(_ template: String) -> String {
        let formats = "[" + patterns.map(Sample.quoted).joined(separator: ", ") + "]"
        let formatsDoc = patterns.isEmpty ? "" : ", then " + patterns.map { "`\($0)`" }.joined(separator: ", ")
        let encode: String, encodeDoc: String
        switch writes {
        case .iso8601: encode = ".iso8601"; encodeDoc = "in ISO 8601"
        case .seconds: encode = ".secondsSince1970"; encodeDoc = "as seconds since 1970"
        case .milliseconds: encode = ".millisecondsSince1970"; encodeDoc = "as milliseconds since 1970"
        case .pattern(let pattern): encode = ".formatted(formatter(\(Sample.quoted(pattern))))"; encodeDoc = "as `\(pattern)`"
        }
        return template
            .replacingOccurrences(of: "__FORMATS_DOC__", with: formatsDoc)
            .replacingOccurrences(of: "__FORMATS__", with: formats)
            .replacingOccurrences(of: "__NUMBER_DOC__", with: milliseconds ? "milliseconds since 1970" : "seconds since 1970")
            .replacingOccurrences(of: "__NUMBER__", with: milliseconds ? "number / 1000" : "number")
            .replacingOccurrences(of: "__ENCODE_DOC__", with: encodeDoc)
            .replacingOccurrences(of: "__ENCODE__", with: encode)
    }
}
