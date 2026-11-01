//  WHAT: The lines a package was made from, kept in its folder as `api.json`: a later call adds to them instead of
//        starting over, and the files the last call wrote are known, so one the package no longer has is taken away.
//  PIN:  A CALL ADDS; A LINE REPLACES ITS OWN. An endpoint line replaces the earlier one with its method and path or
//        its name, an entity line the earlier one of its type; everything else stays. A model asked for two more
//        endpoints writes two lines, not the forty the package already has.

import Foundation

struct APIRecord: Codable, Equatable {
    var name: String
    var baseURL: String?
    var auth: NetworkAuth
    var authName: String?
    var paging: NetworkPaging
    var feeds: Bool
    var coding: NetworkCoding
    var dates: [String]
    var endpoints: [String]
    var entities: [String]
    /// The files the package holds, from its folder.
    var files: [String]

    static let fileName = "api.json"

    /// The record in `folder`, if a call wrote one there.
    static func read(in folder: URL) -> APIRecord? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(APIRecord.self, from: data)
    }

    /// The record as it is written: keys sorted, one line a field, so a diff shows what a call changed.
    var text: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(self)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// The record of `api`, the package that holds `files`.
    init(api: API, call: API.Call, files: [String]) {
        name = api.module
        baseURL = api.baseURL
        auth = api.auth
        authName = api.authName
        paging = api.paging
        feeds = api.feeds
        coding = api.coding
        dates = api.dates
        endpoints = call.endpoints
        entities = call.entities
        self.files = files.sorted()
    }

    /// `input`'s fields over `record`'s: a field the call gives wins, one it leaves out keeps the earlier call's.
    static func call(_ input: NetworkAgent.Input, over record: APIRecord?) -> API.Call {
        let endpoints = clean(input.endpoints), entities = clean(input.entities)
        return API.Call(name: input.name ?? record?.name,
                        baseURL: input.baseURL ?? record?.baseURL,
                        auth: input.auth ?? record?.auth,
                        authName: input.authName ?? record?.authName,
                        paging: input.paging ?? record?.paging,
                        feeds: input.feeds ?? record?.feeds,
                        coding: input.coding ?? record?.coding,
                        dates: input.dates ?? record?.dates,
                        endpoints: merge(record?.endpoints ?? [], endpoints, keys: endpointKeys),
                        entities: merge(record?.entities ?? [], entities, keys: entityKeys))
    }

    private static func clean(_ lines: [String]?) -> [String] {
        (lines ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// `old` with each line a `new` line shares a key with replaced in place, then the rest of `new`.
    static func merge(_ old: [String], _ new: [String], keys: (String) -> Set<String>) -> [String] {
        let newKeys = new.map(keys)
        var placed: Set<Int> = [], merged: [String] = []
        for line in old {
            let lineKeys = keys(line)
            if let index = newKeys.firstIndex(where: { !$0.isDisjoint(with: lineKeys) }) {
                if placed.insert(index).inserted { merged.append(new[index]) }
            } else {
                merged.append(line)
            }
        }
        for (index, line) in new.enumerated() where !placed.contains(index) { merged.append(line) }
        return merged
    }

    /// An endpoint line's method and path, and its name when it gives one.
    static func endpointKeys(_ line: String) -> Set<String> {
        guard let endpoint = try? EndpointLine.parse(line) else { return ["line " + line] }
        var keys: Set<String> = ["signature " + endpoint.signature]
        if let name = endpoint.name { keys.insert("name " + name) }
        return keys
    }

    /// An entity line's type name.
    static func entityKeys(_ line: String) -> Set<String> {
        if let entity = try? EntityLine.parse(line) { return ["type " + entity.name] }
        return ["line " + line]
    }
}
