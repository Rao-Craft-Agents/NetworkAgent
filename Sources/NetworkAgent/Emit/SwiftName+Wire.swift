//  WHAT: Names as an API writes them, said in Swift: `community_id` is `communityID`, `cid-version` is `cidVersion`,
//        `ids[]` is `ids`, `post` is the group `Posts`.

import Foundation

extension SwiftName {
    /// Words an API spells in lowercase that Swift spells in capitals when they are not first.
    static let initialisms: Set<String> = ["id", "ids", "url", "urls", "uri", "uuid", "json", "html", "api", "ip", "jwt", "ttl", "rss"]

    /// `community_id` → `communityID`, `cid-version` → `cidVersion`, `type_` → `type`, `pageToken` → `pageToken`,
    /// `Hash` → `hash`.
    static func camel(_ wire: String) -> String {
        let bare = wire.hasSuffix("[]") ? String(wire.dropLast(2)) : wire
        let words = bare.split(whereSeparator: { "_-. ".contains($0) }).map(String.init)
        guard let first = words.first else { return "value" }
        var out = first.first.map { $0.lowercased() + first.dropFirst() } ?? first
        if first == first.uppercased(), first.count > 1 { out = first.lowercased() }
        for word in words.dropFirst() {
            let lower = word.lowercased()
            if initialisms.contains(lower) {
                out += lower == "ids" ? "IDs" : lower == "urls" ? "URLs" : lower.uppercased()
            } else {
                out += word.prefix(1).uppercased() + word.dropFirst()
            }
        }
        return out.first?.isNumber == true ? "_" + out : out
    }

    /// `private_message` → `PrivateMessage`, `oauth` → `Oauth`.
    static func upperCamel(_ wire: String) -> String {
        let lower = camel(wire)
        return lower.prefix(1).uppercased() + lower.dropFirst()
    }

    /// `post` → `posts`, `community` → `communities`, `search` → `searches`, `statuses` → `statuses`.
    static func plural(_ word: String) -> String {
        let lower = word.lowercased()
        if lower.hasSuffix("s") { return word }
        if lower.hasSuffix("y"), let before = lower.dropLast().last, !"aeiou".contains(before) { return word.dropLast() + "ies" }
        if lower.hasSuffix("x") || lower.hasSuffix("ch") || lower.hasSuffix("sh") { return word + "es" }
        return word + "s"
    }

    /// What a name looks like with its separators and case taken away: `max_id` and `maxId` are both `maxid`.
    static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
