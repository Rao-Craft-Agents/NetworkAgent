//  WHAT: The generated package's test support: the client every test sends through (a mock transport, a token kept for
//        `example.com`), what a test reads off a request, and the feed tests.

enum TestTemplates {
    /// `__TOKENS__` (the store's tokens) and `__AUTH__` are filled per call.
    static let fixture = #"""
    import Foundation
    @testable import __MODULE__

    /// A client on a mock transport, with a token kept for `example.com`: what every test sends through.
    enum Fixture {
        static let baseURL = URL(string: "https://example.com")!
        static let token = "test-token"

        static func client(retry: RetryPolicy = .never) -> (__STEM__Client, MockTransport) {
            let transport = MockTransport()
            let client = __STEM__Client(baseURL: baseURL, auth: __AUTH__, tokens: MemoryTokenStore(__TOKENS__),
                                        transport: transport, retry: retry)
            return (client, transport)
        }
    }

    """#

    static let inspect = #"""
    import Foundation

    extension URLRequest {
        /// The query by name, a repeated name's values joined with commas.
        var queryItems: [String: String] {
            guard let url, let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return [:] }
            var query: [String: String] = [:]
            for item in items {
                query[item.name] = query[item.name].map { $0 + "," + (item.value ?? "") } ?? (item.value ?? "")
            }
            return query
        }

        /// The keys of the JSON object the body holds.
        var jsonKeys: Set<String> {
            guard let httpBody, let object = try? JSONSerialization.jsonObject(with: httpBody) as? [String: Any] else { return [] }
            return Set(object.keys)
        }

        /// The body as text.
        var bodyText: String {
            httpBody.map { String(decoding: $0, as: UTF8.self) } ?? ""
        }
    }

    """#

    static let feedTests = ##"""
    import Foundation
    import XCTest
    @testable import __MODULE__

    /// Feeds in each format read into one shape, and fetched like any request.
    final class FeedTests: XCTestCase {
        private let midnight = Date(timeIntervalSince1970: 1_767_225_600)

        func testAnRSSFeed() throws {
            let feed = try FeedParser.parse(Data(Self.rss.utf8))
            XCTAssertEqual(feed.format, .rss)
            XCTAssertEqual(feed.title, "The Sample Kitchen")
            XCTAssertEqual(feed.summary, "Recipes, weekly")
            XCTAssertEqual(feed.link, URL(string: "https://kitchen.example"))
            XCTAssertEqual(feed.imageURL, URL(string: "https://kitchen.example/logo.png"))
            XCTAssertEqual(feed.items.count, 2)
            let soup = feed.items[0]
            XCTAssertEqual(soup.id, "kitchen-soup")
            XCTAssertEqual(soup.title, "Tomato soup")
            XCTAssertEqual(soup.link, URL(string: "https://kitchen.example/soup"))
            XCTAssertEqual(soup.summary, "A soup for cold days")
            XCTAssertEqual(soup.content, "<p>Simmer for <b>30</b> minutes.</p>")
            XCTAssertEqual(soup.author, "Ada")
            XCTAssertEqual(soup.published, midnight)
            XCTAssertEqual(soup.categories, ["Soups", "Winter"])
            XCTAssertEqual(soup.imageURL, URL(string: "https://kitchen.example/soup.jpg"))
            XCTAssertEqual(soup.attachments.first?.length, 2048)
            XCTAssertEqual(feed.items[1].id, "https://kitchen.example/bread", "an item with no guid is known by its link")
            XCTAssertEqual(feed.items[1].published, midnight.addingTimeInterval(3600), "a numeric zone")
        }

        func testAnAtomFeed() throws {
            let feed = try FeedParser.parse(Data(Self.atom.utf8))
            XCTAssertEqual(feed.format, .atom)
            XCTAssertEqual(feed.title, "Sample Bakery")
            XCTAssertEqual(feed.link, URL(string: "https://bakery.example/"))
            XCTAssertEqual(feed.updated, midnight)
            let entry = try XCTUnwrap(feed.items.first)
            XCTAssertEqual(entry.id, "urn:uuid:sample-bread")
            XCTAssertEqual(entry.title, "Sourdough")
            XCTAssertEqual(entry.link, URL(string: "https://bakery.example/sourdough"))
            XCTAssertEqual(entry.author, "Grace")
            XCTAssertEqual(entry.summary, "A loaf that takes two days")
            XCTAssertEqual(entry.content, "Feed the starter the night before.")
            XCTAssertEqual(entry.published, midnight)
            XCTAssertEqual(entry.updated, midnight.addingTimeInterval(0.5))
            XCTAssertEqual(entry.categories, ["Bread"])
            XCTAssertEqual(entry.imageURL, URL(string: "https://bakery.example/loaf.jpg"))
        }

        func testAJSONFeed() throws {
            let feed = try FeedParser.parse(Data(Self.json.utf8))
            XCTAssertEqual(feed.format, .json)
            XCTAssertEqual(feed.title, "Sample Pantry")
            XCTAssertEqual(feed.link, URL(string: "https://pantry.example/"))
            XCTAssertEqual(feed.items.map(\.id), ["1", "jam"])
            XCTAssertEqual(feed.items[0].title, "Pickles")
            XCTAssertEqual(feed.items[0].content, "<p>Brine and wait.</p>")
            XCTAssertEqual(feed.items[0].author, "Lin")
            XCTAssertEqual(feed.items[0].published, midnight)
            XCTAssertEqual(feed.items[0].categories, ["Preserves"])
            XCTAssertEqual(feed.items[1].summary, "Fruit and sugar")
        }

        func testAFeedIsFetchedWithoutAnotherHostsToken() async throws {
            let (client, transport) = Fixture.client()
            transport.enqueue(HTTPResponse(headers: ["Content-Type": "application/rss+xml"], body: Data(Self.rss.utf8)))
            let feed = try await client.feed(at: URL(string: "https://kitchen.example/feed.xml")!)
            XCTAssertEqual(feed.items.count, 2)
            let request = try XCTUnwrap(transport.lastRequest)
            XCTAssertEqual(request.url?.absoluteString, "https://kitchen.example/feed.xml")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            XCTAssertTrue(request.value(forHTTPHeaderField: "Accept")?.contains("application/rss+xml") == true)
        }

        func testWhatIsNotAFeedIsRefused() async throws {
            XCTAssertThrowsError(try FeedParser.parse(Data("<html><body>Hello</body></html>".utf8)))
            let (client, transport) = Fixture.client()
            transport.enqueue(HTTPResponse(body: Data("<html></html>".utf8)))
            do {
                _ = try await client.feed(at: URL(string: "https://kitchen.example/")!)
                XCTFail("a page that is not a feed is thrown")
            } catch __STEM__Error.decoding(let type, _, _) {
                XCTAssertEqual(type, "Feed")
            }
        }

        static let rss = #"""
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel>
            <title>The Sample Kitchen</title>
            <link>https://kitchen.example</link>
            <description>Recipes, weekly</description>
            <image><url>https://kitchen.example/logo.png</url><title>The Sample Kitchen</title><link>https://kitchen.example</link></image>
            <item>
              <title>Tomato soup</title>
              <link>https://kitchen.example/soup</link>
              <guid isPermaLink="false">kitchen-soup</guid>
              <description>A soup for cold days</description>
              <content:encoded><![CDATA[<p>Simmer for <b>30</b> minutes.</p>]]></content:encoded>
              <dc:creator>Ada</dc:creator>
              <pubDate>Thu, 01 Jan 2026 00:00:00 GMT</pubDate>
              <category>Soups</category>
              <category>Winter</category>
              <enclosure url="https://kitchen.example/soup.jpg" type="image/jpeg" length="2048"/>
            </item>
            <item>
              <title>Bread</title>
              <link>https://kitchen.example/bread</link>
              <pubDate>Thu, 1 Jan 2026 02:00:00 +0100</pubDate>
            </item>
          </channel>
        </rss>
        """#

        static let atom = #"""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/">
          <title>Sample Bakery</title>
          <link href="https://bakery.example/"/>
          <link rel="self" href="https://bakery.example/atom.xml"/>
          <updated>2026-01-01T00:00:00Z</updated>
          <id>urn:uuid:sample-bakery</id>
          <entry>
            <title>Sourdough</title>
            <link rel="alternate" href="https://bakery.example/sourdough"/>
            <id>urn:uuid:sample-bread</id>
            <published>2026-01-01T01:00:00+01:00</published>
            <updated>2026-01-01T00:00:00.5Z</updated>
            <author><name>Grace</name></author>
            <summary>A loaf that takes two days</summary>
            <content type="html">Feed the starter the night before.</content>
            <category term="Bread"/>
            <media:thumbnail url="https://bakery.example/loaf.jpg"/>
          </entry>
        </feed>
        """#

        static let json = #"""
        {
          "version": "https://jsonfeed.org/version/1.1",
          "title": "Sample Pantry",
          "home_page_url": "https://pantry.example/",
          "items": [
            {"id": 1, "title": "Pickles", "content_html": "<p>Brine and wait.</p>", "authors": [{"name": "Lin"}],
             "date_published": "2026-01-01T00:00:00Z", "tags": ["Preserves"]},
            {"id": "jam", "title": "Jam", "summary": "Fruit and sugar"}
          ]
        }
        """#
    }

    """##
}
