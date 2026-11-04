import Foundation
import GraniteAgents

/// What a call answers: the files written, as absolute paths, and what the package now offers.
public struct NetworkResult: AgentAnswer, Equatable {
    /// The client's file.
    public var path: String?
    /// Every file written: the package's, and a project or manifest the package was linked into.
    public var paths: [String]
    /// The package's folder.
    public var package: String
    /// The client type an app makes: `RecipeClient`.
    public var client: String
    /// The client's endpoint methods, in the order the lines gave them.
    public var endpoints: [String]
    /// The types the package declares from the entity lines.
    public var types: [String]
    /// The Xcode projects and manifests the package was linked into.
    public var linked: [String]
    /// One sentence each: what the call did beside writing, or left out, and why.
    public var notes: [String]

    public init(path: String?, paths: [String], package: String, client: String, endpoints: [String], types: [String],
                linked: [String], notes: [String]) {
        self.path = path; self.paths = paths; self.package = package; self.client = client; self.endpoints = endpoints
        self.types = types; self.linked = linked; self.notes = notes
    }
}
