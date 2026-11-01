//  WHAT: What Swift accepts as a name, and how a name is said: keywords escaped, words split for a sample value,
//        snake_case for a JSON key.

import Foundation

enum SwiftName {
    static let keywords: Set<String> = ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
                                        "inout", "internal", "let", "open", "operator", "private", "precedencegroup", "protocol", "public",
                                        "rethrows", "static", "struct", "subscript", "typealias", "var", "break", "case", "catch", "continue",
                                        "default", "defer", "do", "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "throw",
                                        "switch", "where", "while", "as", "Any", "false", "is", "nil", "self", "Self", "super", "throws", "true",
                                        "try", "some", "any"]

    static func isTypeName(_ text: String) -> Bool {
        text.range(of: #"^[A-Z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    static func isMemberName(_ text: String) -> Bool {
        text.range(of: #"^[a-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    /// A member name as code writes it: a keyword in backticks.
    static func member(_ name: String) -> String { keywords.contains(name) ? "`\(name)`" : name }

    /// `displayName` → `display name`; `postID` → `post id`.
    static func words(_ name: String) -> String {
        var out = "", previous: Character?
        for character in name {
            if character == "_" { out.append(" ") }
            else if character.isUppercase, let p = previous, p.isLowercase || p.isNumber { out.append(" "); out.append(Character(character.lowercased())) }
            else { out.append(Character(character.lowercased())) }
            previous = character
        }
        return out
    }

    /// `displayName` → `display_name`.
    static func snake(_ name: String) -> String { words(name).replacingOccurrences(of: " ", with: "_") }

    /// `TopDay` → `topDay`, `NSFW` → `nsfw`, `URLPath` → `urlPath`: a type-like name said as a member.
    static func lowerCamel(_ name: String) -> String {
        let characters = Array(name)
        var upper = 0
        while upper < characters.count, characters[upper].isUppercase { upper += 1 }
        if upper == 0 { return name }
        // A run of capitals is an acronym: all of it lowercased, except the capital that starts the next word.
        let cut = upper == characters.count || upper == 1 ? upper : upper - 1
        return String(characters[..<cut]).lowercased() + String(characters[cut...])
    }
}
