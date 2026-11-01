//  WHAT: Splitting a line where a separator stands outside brackets, parentheses and quotes: `[String: Int]`,
//        `= [1, 2]` and `"a, b"` stay whole.

import Foundation

enum LineSplit {
    /// `text` cut at every `separator` that stands at the top level, each piece trimmed, empty pieces dropped.
    static func top(_ text: String, on separator: Character) -> [String] {
        var pieces: [String] = [], current = "", depth = 0, quoted = false, escaped = false
        for character in text {
            if quoted {
                current.append(character)
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { quoted = false }
                continue
            }
            switch character {
            case "\"": quoted = true; current.append(character)
            case "[", "(", "{", "<": depth += 1; current.append(character)
            case "]", ")", "}", ">": depth = max(0, depth - 1); current.append(character)
            case separator where depth == 0:
                pieces.append(current); current = ""
            default: current.append(character)
            }
        }
        pieces.append(current)
        return pieces.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The index of the first `character` at the top level, if any.
    static func firstTop(_ text: String, _ character: Character) -> String.Index? {
        var depth = 0, quoted = false, escaped = false
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if quoted {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }
            } else if c == "\"" {
                quoted = true
            } else if "[({<".contains(c) {
                depth += 1
            } else if "])}>".contains(c) {
                depth = max(0, depth - 1)
            } else if c == character && depth == 0 {
                return index
            }
            index = text.index(after: index)
        }
        return nil
    }
}
