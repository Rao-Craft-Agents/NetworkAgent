//  WHAT: The generated package's `Feeds/` folder, when a call asks for feeds: RSS 2.0 (and 1.0), Atom and JSON Feed read
//        into one `Feed` of `FeedItem`s, with `XMLParser` and no dependency, and the client's `feed(at:)`.
//  PIN:  ONE SHAPE FOR EVERY FORMAT. An app shows a feed's items the same way whatever the site writes; what a format
//        says that others do not (an RSS enclosure, an Atom link's rel) lands in the field that means it.

enum FeedTemplates {
    static let feed = #"""
    import Foundation

    /// A feed, whatever it was written in: RSS 2.0 (and 1.0), Atom, or JSON Feed, read into one shape.
    public struct Feed: Codable, Hashable, Sendable {
        /// What a feed was written in.
        public enum Format: String, Codable, Hashable, Sendable {
            case rss, atom, json
        }

        public var format: Format
        public var title: String
        /// What the feed is about.
        public var summary: String?
        /// The site the feed is of.
        public var link: URL?
        /// The feed's image or icon.
        public var imageURL: URL?
        public var updated: Date?
        public var items: [FeedItem]

        public init(format: Format, title: String, summary: String? = nil, link: URL? = nil, imageURL: URL? = nil,
                    updated: Date? = nil, items: [FeedItem] = []) {
            self.format = format
            self.title = title
            self.summary = summary
            self.link = link
            self.imageURL = imageURL
            self.updated = updated
            self.items = items
        }
    }

    extension Feed {
        /// A feed to preview and test with.
        public static let preview = Feed(format: .rss, title: "Sample feed", summary: "Sample summary",
                                         link: URL(string: "https://example.com"), items: [FeedItem.preview])
    }

    """#

    static let feedItem = #"""
    import Foundation

    /// One entry of a feed: an article, a post, an episode.
    public struct FeedItem: Codable, Hashable, Identifiable, Sendable {
        /// A file an item carries: an episode's audio, a photo.
        public struct Attachment: Codable, Hashable, Sendable {
            public var url: URL
            public var mimeType: String?
            /// Its size in bytes, when the feed says.
            public var length: Int?

            public init(url: URL, mimeType: String? = nil, length: Int? = nil) {
                self.url = url
                self.mimeType = mimeType
                self.length = length
            }
        }

        /// Its guid or Atom id; else its link; else its title.
        public var id: String
        public var title: String?
        public var link: URL?
        /// A short text of it.
        public var summary: String?
        /// The whole of it, as HTML, when the feed carries it.
        public var content: String?
        public var author: String?
        public var published: Date?
        public var updated: Date?
        public var imageURL: URL?
        public var categories: [String]
        public var attachments: [Attachment]

        public init(id: String, title: String? = nil, link: URL? = nil, summary: String? = nil, content: String? = nil,
                    author: String? = nil, published: Date? = nil, updated: Date? = nil, imageURL: URL? = nil,
                    categories: [String] = [], attachments: [Attachment] = []) {
            self.id = id
            self.title = title
            self.link = link
            self.summary = summary
            self.content = content
            self.author = author
            self.published = published
            self.updated = updated
            self.imageURL = imageURL
            self.categories = categories
            self.attachments = attachments
        }
    }

    extension FeedItem {
        /// An item to preview and test with.
        public static let preview = FeedItem(id: "https://example.com/1", title: "Sample title",
                                             link: URL(string: "https://example.com/1"), summary: "Sample summary",
                                             published: Date(timeIntervalSince1970: 1_767_225_600))
    }

    """#

    static let feedParser = #"""
    import Foundation

    /// Reads a feed's bytes: JSON Feed by its JSON, RSS and Atom by `XMLParser`.
    public enum FeedParser {
        /// Why bytes could not be read as a feed.
        public struct Failure: Error, CustomStringConvertible {
            public let description: String
        }

        /// `data` read as a feed, whatever it was written in.
        public static func parse(_ data: Data) throws -> Feed {
            let first = data.prefix(1024).first { byte in
                byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D && byte != 0xEF && byte != 0xBB && byte != 0xBF
            }
            if first == UInt8(ascii: "{") { return try JSONFeedDocument.feed(from: data) }
            return try FeedXMLReader(data: data).read()
        }

        /// A feed's date: ISO 8601 (Atom, JSON Feed), else RFC 822 (RSS), with or without its weekday.
        static func date(_ text: String) -> Date? {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let date = DateParsing.iso8601(text) { return date }
            for formatter in rfc822 {
                if let date = formatter.date(from: text) { return date }
            }
            if let comma = text.firstIndex(of: ","), text.distance(from: text.startIndex, to: comma) <= 9 {
                let rest = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
                for formatter in rfc822 {
                    if let date = formatter.date(from: rest) { return date }
                }
            }
            return nil
        }

        private static let rfc822: [DateFormatter] = [
            "EEE, d MMM yyyy HH:mm:ss zzz", "EEE, d MMM yyyy HH:mm:ss Z", "EEE, d MMM yyyy HH:mm zzz", "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm:ss zzz", "d MMM yyyy HH:mm:ss Z", "d MMM yyyy HH:mm zzz", "d MMM yyyy HH:mm Z",
            "EEE, d MMM yy HH:mm:ss zzz", "EEE, d MMM yy HH:mm:ss Z", "d MMM yy HH:mm:ss Z",
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }

    """#

    static let feedXMLReader = #"""
    import Foundation
    #if canImport(FoundationXML)
    import FoundationXML
    #endif

    /// The XML half of `FeedParser`: one pass of `XMLParser` over RSS (2.0 and 1.0) or Atom, keeping what each element
    /// says in the field that means it.
    final class FeedXMLReader: NSObject, XMLParserDelegate {
        private let parser: XMLParser
        private var format: Feed.Format?
        private var feed = Feed(format: .rss, title: "")
        private var item: FeedItem?
        /// The open elements, outermost first, and the text each holds so far.
        private var path: [String] = []
        private var texts: [String] = []

        init(data: Data) {
            parser = XMLParser(data: data)
            super.init()
            parser.delegate = self
        }

        func read() throws -> Feed {
            let parsed = parser.parse()
            guard let format else { throw FeedParser.Failure(description: "this is not an RSS, Atom or JSON feed") }
            if !parsed, feed.items.isEmpty, feed.title.isEmpty {
                let reason = parser.parserError?.localizedDescription ?? "the XML ends early"
                throw FeedParser.Failure(description: "the feed's XML could not be read: \(reason)")
            }
            feed.format = format
            return feed
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let name = elementName.lowercased()
            path.append(name)
            texts.append("")
            guard let format else {
                switch name {
                case "rss", "rdf:rdf": format = .rss
                case "feed": format = .atom
                default: parser.abortParsing()
                }
                return
            }
            switch name {
            case "item", "entry":
                item = FeedItem(id: "")
            case "link" where format == .atom:
                guard let href = attributes["href"], let url = URL(string: href) else { break }
                switch attributes["rel"] ?? "alternate" {
                case "alternate":
                    if item != nil {
                        if item?.link == nil { item?.link = url }
                    } else if feed.link == nil {
                        feed.link = url
                    }
                case "enclosure":
                    item?.attachments.append(.init(url: url, mimeType: attributes["type"], length: attributes["length"].flatMap { Int($0) }))
                default:
                    break
                }
            case "enclosure":
                guard item != nil, let href = attributes["url"], let url = URL(string: href) else { break }
                let type = attributes["type"]
                item?.attachments.append(.init(url: url, mimeType: type, length: attributes["length"].flatMap { Int($0) }))
                if type?.hasPrefix("image/") == true { image(url) }
            case "media:thumbnail", "media:content":
                guard let href = attributes["url"], let url = URL(string: href) else { break }
                if name == "media:thumbnail" || attributes["medium"] == "image" || attributes["type"]?.hasPrefix("image/") == true {
                    image(url)
                }
            case "itunes:image":
                if let href = attributes["href"], let url = URL(string: href) { image(url) }
            case "category" where format == .atom:
                if let term = attributes["term"], item != nil { item?.categories.append(term) }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if !texts.isEmpty { texts[texts.count - 1] += string }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if !texts.isEmpty { texts[texts.count - 1] += String(decoding: CDATABlock, as: UTF8.self) }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            let name = elementName.lowercased()
            let text = texts.popLast() ?? ""
            path.removeLast()
            // An element's text counts in the one around it too: XHTML content keeps its words.
            if !texts.isEmpty { texts[texts.count - 1] += text }
            let parent = path.last ?? ""
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)

            if name == "item" || name == "entry" {
                if var finished = item {
                    if finished.id.isEmpty { finished.id = finished.link?.absoluteString ?? finished.title ?? "\(feed.items.count + 1)" }
                    feed.items.append(finished)
                }
                item = nil
                return
            }
            guard !value.isEmpty else { return }
            if item != nil {
                switch (name, parent) {
                case ("title", "item"), ("title", "entry"): item?.title = value
                case ("link", "item") where format == .rss: item?.link = URL(string: value)
                case ("guid", _), ("id", "entry"): item?.id = value
                case ("description", "item"), ("summary", "entry"): item?.summary = value
                case ("content:encoded", _), ("content", "entry"): item?.content = value
                case ("pubdate", _), ("published", _), ("dc:date", _), ("issued", _): item?.published = FeedParser.date(value)
                case ("updated", "entry"), ("modified", _): item?.updated = FeedParser.date(value)
                case ("author", "item"), ("dc:creator", _): if item?.author == nil { item?.author = value }
                case ("name", "author"): item?.author = value
                case ("category", "item"): item?.categories.append(value)
                default: break
                }
            } else {
                switch (name, parent) {
                case ("title", "channel"), ("title", "feed"): feed.title = value
                case ("description", "channel"), ("subtitle", "feed"): feed.summary = value
                case ("link", "channel") where format == .rss: feed.link = feed.link ?? URL(string: value)
                case ("url", "image"), ("icon", "feed"), ("logo", "feed"): feed.imageURL = feed.imageURL ?? URL(string: value)
                case ("lastbuilddate", "channel"), ("pubdate", "channel"), ("updated", "feed"):
                    feed.updated = feed.updated ?? FeedParser.date(value)
                default: break
                }
            }
        }

        /// `url` as the open item's image, or the feed's when no item is open; the first one found stays.
        private func image(_ url: URL) {
            if item != nil {
                if item?.imageURL == nil { item?.imageURL = url }
            } else if feed.imageURL == nil {
                feed.imageURL = url
            }
        }
    }

    """#

    static let jsonFeedDocument = #"""
    import Foundation

    /// A JSON Feed (1.0 and 1.1) as its JSON says it, read before it becomes a `Feed`.
    struct JSONFeedDocument: Decodable {
        struct Author: Decodable {
            var name: String?
        }

        struct Attachment: Decodable {
            var url: String
            var mimeType: String?
            var sizeInBytes: Int?
        }

        /// An id written as a string or as a number.
        struct Identifier: Decodable {
            var text: String

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let number = try? container.decode(Int.self) { text = String(number) } else { text = try container.decode(String.self) }
            }
        }

        struct Item: Decodable {
            var id: Identifier?
            var url: String?
            var title: String?
            var contentHtml: String?
            var contentText: String?
            var summary: String?
            var image: String?
            var bannerImage: String?
            var datePublished: String?
            var dateModified: String?
            var author: Author?
            var authors: [Author]?
            var tags: [String]?
            var attachments: [Attachment]?
        }

        var title: String?
        var homePageUrl: String?
        var description: String?
        var icon: String?
        var favicon: String?
        var items: [Item]?

        static func feed(from data: Data) throws -> Feed {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let document: JSONFeedDocument
            do {
                document = try decoder.decode(JSONFeedDocument.self, from: data)
            } catch {
                throw FeedParser.Failure(description: "the JSON is not a JSON Feed: \(error.localizedDescription)")
            }
            let items = (document.items ?? []).enumerated().map { index, item in
                let link = item.url.flatMap { URL(string: $0) }
                return FeedItem(
                    id: item.id?.text ?? item.url ?? item.title ?? "\(index + 1)",
                    title: item.title,
                    link: link,
                    summary: item.summary ?? item.contentText,
                    content: item.contentHtml ?? item.contentText,
                    author: item.authors?.first?.name ?? item.author?.name,
                    published: item.datePublished.flatMap { DateParsing.iso8601($0) },
                    updated: item.dateModified.flatMap { DateParsing.iso8601($0) },
                    imageURL: (item.image ?? item.bannerImage).flatMap { URL(string: $0) },
                    categories: item.tags ?? [],
                    attachments: (item.attachments ?? []).compactMap { attachment in
                        URL(string: attachment.url).map { FeedItem.Attachment(url: $0, mimeType: attachment.mimeType, length: attachment.sizeInBytes) }
                    })
            }
            return Feed(format: .json, title: document.title ?? "", summary: document.description,
                        link: document.homePageUrl.flatMap { URL(string: $0) },
                        imageURL: (document.icon ?? document.favicon).flatMap { URL(string: $0) }, items: items)
        }
    }

    """#

    static let clientFeed = #"""
    import Foundation

    extension __STEM__Client {
        /// The feed at `url`, read whatever it is written in: RSS, Atom or JSON Feed. A token goes with it only when the
        /// client keeps one for `url`'s host.
        public func feed(at url: URL) async throws -> Feed {
            var request = Request<Feed>(.get, "", headers: [
                "Accept": "application/rss+xml, application/atom+xml, application/feed+json, application/xml;q=0.9, */*;q=0.8",
            ]) { data, _ in
                try FeedParser.parse(data)
            }
            request.url = url
            return try await send(request)
        }
    }

    """#
}
