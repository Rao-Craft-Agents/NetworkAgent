//  WHAT: The generated package's `Paging/` folder, in the call's paging: a page and the sequence of every page, by page
//        number or by cursor, and the `Link` header a cursor may come in.
//  PIN:  A SEQUENCE THAT ENDS. Pages end after an empty page, a page that names no next one, or (by cursor) a page that
//        names the cursor it was asked with, so a server that repeats itself cannot loop a list forever.

enum PagingTemplates {
    static let pageByNumber = #"""
    import Foundation

    /// One page of a paged endpoint: its items, its number, and the next page's number, nil on the last.
    public struct Page<Item: Sendable>: Sendable {
        public var items: [Item]
        /// This page's number, from 1.
        public var number: Int
        /// The next page's number; nil when this page is the last.
        public var next: Int?

        public init(items: [Item], number: Int, next: Int?) {
            self.items = items
            self.number = number
            self.next = next
        }
    }

    extension Page: Equatable where Item: Equatable {}
    extension Page: Hashable where Item: Hashable {}

    """#

    static let pagesByNumber = #"""
    import Foundation

    /// Every page of a paged endpoint, each asked for when it is read: the sequence ends after an empty page or one that
    /// names no next. Keep an iterator to load a page at a time as a list scrolls.
    ///
    /// ```swift
    /// for try await page in client.recipesPages(perPage: 20) {
    ///     recipes += page.items
    /// }
    /// ```
    public struct Pages<Item: Sendable>: AsyncSequence, Sendable {
        public typealias Element = Page<Item>

        private let first: Int
        private let fetch: @Sendable (Int) async throws -> Page<Item>

        /// The pages from number `first` on, each read by `fetch`.
        public init(from first: Int = 1, fetch: @escaping @Sendable (Int) async throws -> Page<Item>) {
            self.first = first
            self.fetch = fetch
        }

        public func makeAsyncIterator() -> Iterator {
            Iterator(number: first, fetch: fetch)
        }

        public struct Iterator: AsyncIteratorProtocol {
            var number: Int?
            let fetch: @Sendable (Int) async throws -> Page<Item>

            public mutating func next() async throws -> Page<Item>? {
                guard let current = number else { return nil }
                let page = try await fetch(current)
                guard !page.items.isEmpty else {
                    number = nil
                    return nil
                }
                number = page.next
                return page
            }
        }
    }

    """#

    static let pageByCursor = #"""
    import Foundation

    /// One page of a paged endpoint: its items, the cursor it was asked with, and the cursor of the next page, nil on
    /// the last.
    public struct Page<Item: Sendable>: Sendable {
        public var items: [Item]
        /// The cursor this page was asked with; nil for the first.
        public var cursor: String?
        /// The cursor that asks for the next page; nil when this page is the last.
        public var next: String?

        public init(items: [Item], cursor: String?, next: String?) {
            self.items = items
            self.cursor = cursor
            self.next = next
        }
    }

    extension Page: Equatable where Item: Equatable {}
    extension Page: Hashable where Item: Hashable {}

    """#

    static let pagesByCursor = #"""
    import Foundation

    /// Every page of a paged endpoint, each asked for when it is read: the sequence ends after an empty page, one that
    /// names no next cursor, or one that names the cursor it was asked with. Keep an iterator to load a page at a time
    /// as a list scrolls.
    ///
    /// ```swift
    /// for try await page in client.recipesPages(limit: 20) {
    ///     recipes += page.items
    /// }
    /// ```
    public struct Pages<Item: Sendable>: AsyncSequence, Sendable {
        public typealias Element = Page<Item>

        private let first: String?
        private let fetch: @Sendable (String?) async throws -> Page<Item>

        /// The pages from the cursor `first` on (nil: the first page), each read by `fetch`.
        public init(from first: String? = nil, fetch: @escaping @Sendable (String?) async throws -> Page<Item>) {
            self.first = first
            self.fetch = fetch
        }

        public func makeAsyncIterator() -> Iterator {
            Iterator(cursor: first, fetch: fetch)
        }

        public struct Iterator: AsyncIteratorProtocol {
            var cursor: String?
            var finished = false
            let fetch: @Sendable (String?) async throws -> Page<Item>

            public mutating func next() async throws -> Page<Item>? {
                guard !finished else { return nil }
                let page = try await fetch(cursor)
                guard !page.items.isEmpty else {
                    finished = true
                    return nil
                }
                if let next = page.next, next != cursor {
                    cursor = next
                } else {
                    finished = true
                }
                return page
            }
        }
    }

    """#

    static let linkHeader = #"""
    import Foundation

    /// The `Link` header (RFC 8288), as APIs that page by it write it:
    /// `<https://example.com/v1/items?max_id=7>; rel="next", <https://example.com/v1/items?min_id=9>; rel="prev"`.
    public enum LinkHeader {
        /// The URL the header names for `rel`; nil when it names none.
        public static func url(_ header: String?, rel: String = "next") -> URL? {
            guard let header else { return nil }
            for link in header.split(separator: ",") {
                let parts = link.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let target = parts.first, target.hasPrefix("<"), target.hasSuffix(">") else { continue }
                let rels = parts.dropFirst()
                    .filter { $0.lowercased().hasPrefix("rel=") }
                    .flatMap { $0.dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: "\"")).split(separator: " ") }
                    .map { $0.lowercased() }
                if rels.contains(rel.lowercased()) { return URL(string: String(target.dropFirst().dropLast())) }
            }
            return nil
        }

        /// The value of the query parameter `name` in the URL the header names for `rel`: the next page's cursor.
        public static func value(_ header: String?, rel: String = "next", parameter name: String) -> String? {
            guard let url = url(header, rel: rel),
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
            return items.first { $0.name == name }?.value
        }
    }

    """#
}
