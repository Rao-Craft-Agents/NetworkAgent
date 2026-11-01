import Foundation

/// How a request proves who sends it.
public enum NetworkAuth: String, Codable, Sendable, CaseIterable {
    /// Nothing is sent: a public API.
    case none
    /// `Authorization: Bearer <token>`: OAuth access tokens and JWTs.
    case bearer
    /// `Authorization: Basic <base64 of user:password>`.
    case basic
    /// The token as the value of a header the call names in `authName` (`X-API-Key`).
    case header
    /// The token as a query parameter the call names in `authName` (`api_key`).
    case query
}

/// How a paged endpoint asks for the page after the one it has.
public enum NetworkPaging: String, Codable, Sendable, CaseIterable {
    /// No endpoint is paged.
    case none
    /// A `page` number in the query, counted from 1.
    case page
    /// A cursor in the query (`cursor`, `page_cursor`, `max_id`, `after`, `page_token`), the next one read off the
    /// response or its `Link` header.
    case cursor
}

/// How a type's fields are named in JSON.
public enum NetworkCoding: String, Codable, Sendable, CaseIterable {
    /// As they are named in Swift: the default.
    case exact
    /// snake_case: `displayName` is `display_name`.
    case snake
}
