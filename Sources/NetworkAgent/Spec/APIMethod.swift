//  WHAT: One endpoint as the client's method: its Swift name and group, its arguments with Swift names and types,
//        what it sends and answers, how it pages, and where its token is.

import Foundation

struct APIMethod: Sendable {
    /// A path or query parameter, or a multipart text field, as the method takes it.
    struct Argument: Sendable, Equatable {
        /// The name on the wire (`community_id`).
        var wire: String
        /// The name in Swift (`communityID`).
        var name: String
        var type: TypeRef
        var required: Bool
    }

    /// A multipart part as the method takes it.
    struct Part: Sendable, Equatable {
        var part: Endpoint.Part
        var name: String
    }

    /// What the method answers.
    enum Answer: Sendable, Equatable {
        /// Nothing: the call answers when the server does.
        case nothing
        /// JSON, read as the type.
        case json(TypeRef)
        /// The body's bytes.
        case data
        /// The body as text.
        case text
    }

    /// Where the marker of the page after this one comes from.
    enum Next: Sendable, Equatable {
        /// The page number, one up.
        case number
        /// A field of the response (`nextPage`), a String or an Int.
        case field(String, TypeRef)
        /// The `Link` header's `rel="next"` URL, its value of the cursor parameter.
        case link
    }

    struct Paging: Sendable, Equatable {
        /// The type of one item.
        var item: TypeRef
        /// The response field that holds the items; nil when the response is the array.
        var itemsField: String?
        /// Whether that field is optional (`posts [Post]?`).
        var itemsOptional: Bool
        /// The query argument the page or cursor goes in.
        var marker: Argument
        var next: Next
        /// The `limit` argument, if the endpoint takes one: a page shorter than it is the last.
        var limit: Argument?
    }

    /// Where a `stores token` endpoint's token is.
    enum Token: Sendable, Equatable {
        /// A field of the response, and whether it is optional.
        case field(String, optional: Bool)
        /// The response itself (`-> String`).
        case whole
    }

    var endpoint: Endpoint
    var name: String
    var group: String
    var path: [Argument]
    var query: [Argument]
    var body: TypeRef?
    var parts: [Part]
    var answer: Answer
    var paging: Paging?
    var token: Token?

    /// The name of the helper that reads every page: `postsPages`.
    var pagesName: String { name + "Pages" }

    /// The argument labels, in the method's order: the body unlabeled, then the path, the form and the query.
    var labels: [String] {
        (body == nil ? [] : ["_"]) + path.map(\.name) + parts.map(\.name) + query.map(\.name)
    }

    /// `posts(page:limit:)`: the method's name as Swift tells it from another.
    var fullName: String { name + "(" + labels.map { $0 + ":" }.joined() + ")" }

    /// `postsPages(from:limit:)`.
    var pagesFullName: String {
        let others = labels.filter { $0 != paging?.marker.name }
        return pagesName + "(" + (["from"] + others).map { $0 + ":" }.joined() + ")"
    }
}
