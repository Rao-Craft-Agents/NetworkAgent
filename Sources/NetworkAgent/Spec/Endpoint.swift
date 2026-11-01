//  WHAT: One endpoint, as an endpoint line says it: the method and path, the parameters the path and query take,
//        the body, what it answers, and what the line marks (its name, paged, stores token, a doc).

import Foundation

struct Endpoint: Equatable, Sendable {
    /// A value a path or a query takes: its name on the wire and its type.
    struct Parameter: Equatable, Sendable {
        /// The name in the URL, as the line wrote it (`community_id`).
        var wire: String
        var type: TypeRef
        /// Whether the line wrote the type; a parameter it did not is a String, or an Int for a count (`page`, `limit`).
        var typed: Bool
        /// A query parameter a call must give (`?q!`); every path parameter is required.
        var required: Bool
    }

    /// One part of a multipart body: a file, several files, or a text field.
    struct Part: Equatable, Sendable {
        enum Kind: Equatable, Sendable { case file, files, value(TypeRef) }
        var wire: String
        var kind: Kind
        var required: Bool
    }

    enum Body: Equatable, Sendable {
        /// A value written as JSON.
        case json(TypeRef)
        /// A `multipart/form-data` form.
        case multipart([Part])
    }

    /// The line as written, to name it in a refusal.
    var line: String
    /// `GET`, `POST`, `PUT`, `PATCH`, `DELETE` or `HEAD`.
    var method: String
    /// The path with `{name}` where a parameter goes (`/api/v1/accounts/{id}/statuses`).
    var path: String
    var pathParameters: [Parameter]
    var query: [Parameter]
    var body: Body?
    /// What it answers; nil: nothing (a 204).
    var response: TypeRef?
    /// `as Group.name`: the group the line names, if any.
    var group: String?
    /// `as name`: the method's name, if the line gives one.
    var name: String?
    /// `paged`, and the response field that holds the items when the line names it (`paged(posts)`).
    var paged: Bool
    var itemsField: String?
    /// `stores token`, and the response field that holds the token when the line names it (`stores token(jwt)`).
    var storesToken: Bool
    var tokenField: String?
    var doc: String?

    /// `GET /api/v1/accounts/{id}`: what the endpoint is on the wire.
    var signature: String { "\(method) \(path)" }
}
