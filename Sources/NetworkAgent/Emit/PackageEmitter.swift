//  WHAT: The whole package a call describes, as files: the manifest, the client and its support folders, the
//        endpoints, the models, the paging and feeds when asked for, and the tests; each by its path in the package.
//  PIN:  THE SAME LINES MAKE THE SAME FILES. No model is asked: a package is a function of its lines, so a second call
//        with more lines rewrites what changed and nothing else differs.

import Foundation

struct PackageEmitter {
    let api: API
    let models: ModelEmitter

    init(api: API) {
        self.api = api
        self.models = ModelEmitter(entities: api.entities, coding: api.coding)
    }

    /// Every file of the package: its path from the package's folder, and its text.
    func files() -> [(path: String, text: String)] {
        let source = "Sources/\(api.module)", tests = "Tests/\(api.module)Tests"
        var files: [(String, String)] = [("Package.swift", fill(ClientTemplates.package))]
        files.append(("\(source)/\(api.client).swift", client()))
        let endpoints = EndpointEmitter(api: api, models: models)
        files.append(("\(source)/\(api.client)+Preview.swift", endpoints.preview()))
        for (name, template) in [("HTTPTransport", TransportTemplates.httpTransport), ("HTTPResponse", TransportTemplates.httpResponse),
                                 ("URLSessionTransport", TransportTemplates.urlSessionTransport), ("MockTransport", TransportTemplates.mockTransport)] {
            files.append(("\(source)/Transport/\(name).swift", fill(template)))
        }
        for (name, template) in [("AuthScheme", AuthTemplates.authScheme), ("TokenStore", AuthTemplates.tokenStore),
                                 ("KeychainTokenStore", AuthTemplates.keychainTokenStore), ("MemoryTokenStore", AuthTemplates.memoryTokenStore)] {
            files.append(("\(source)/Auth/\(name).swift", fill(template)))
        }
        for (name, template) in [("HTTPMethod", RequestTemplates.httpMethod), ("Request", RequestTemplates.request),
                                 ("RequestBody", RequestTemplates.requestBody), ("QueryValue", RequestTemplates.queryValue),
                                 ("Multipart", RequestTemplates.multipart), ("MultipartFile", RequestTemplates.multipartFile),
                                 ("NoContent", RequestTemplates.noContent)] {
            files.append(("\(source)/Request/\(name).swift", fill(template)))
        }
        files.append(("\(source)/Coding/\(api.codingType).swift", fill(DateFormats(api.dates).fill(CodingTemplates.coding))))
        files.append(("\(source)/Coding/DateParsing.swift", fill(CodingTemplates.dateParsing)))
        if models.needsIndirect { files.append(("\(source)/Coding/Indirect.swift", fill(CodingTemplates.indirect))) }
        files.append(("\(source)/Errors/\(api.error).swift", fill(ErrorTemplates.error)))
        files.append(("\(source)/Errors/RetryPolicy.swift", fill(ErrorTemplates.retryPolicy)))
        for group in api.groups {
            files.append(("\(source)/Endpoints/\(api.groupFiles[group] ?? group).swift", endpoints.emit(group: group)))
        }
        for entity in api.entities {
            files.append(("\(source)/Models/\(entity.name).swift", models.emit(entity)))
        }
        switch api.paging {
        case .none: break
        case .page:
            files.append(("\(source)/Paging/Page.swift", fill(PagingTemplates.pageByNumber)))
            files.append(("\(source)/Paging/Pages.swift", fill(PagingTemplates.pagesByNumber)))
        case .cursor:
            files.append(("\(source)/Paging/Page.swift", fill(PagingTemplates.pageByCursor)))
            files.append(("\(source)/Paging/Pages.swift", fill(PagingTemplates.pagesByCursor)))
            files.append(("\(source)/Paging/LinkHeader.swift", fill(PagingTemplates.linkHeader)))
        }
        if api.feeds {
            for (name, template) in [("Feed", FeedTemplates.feed), ("FeedItem", FeedTemplates.feedItem), ("FeedParser", FeedTemplates.feedParser),
                                     ("FeedXMLReader", FeedTemplates.feedXMLReader), ("JSONFeedDocument", FeedTemplates.jsonFeedDocument),
                                     ("\(api.client)+Feed", FeedTemplates.clientFeed)] {
                files.append(("\(source)/Feeds/\(name).swift", fill(template)))
            }
        }

        var emitter = TestEmitter(api: api, models: models)
        var groupTests: [(String, String)] = []
        for group in api.groups {
            let file = api.groupFiles[group] ?? group
            groupTests.append(("\(tests)/\(file)Tests.swift", emitter.emit(group: group, file: file)))
        }
        files.append(("\(tests)/Support/Fixture.swift", fixture()))
        files.append(("\(tests)/Support/URLRequest+Inspect.swift", fill(TestTemplates.inspect)))
        files.append(("\(tests)/Support/Samples.swift", emitter.samplesFile()))
        files.append(("\(tests)/\(api.client)Tests.swift", emitter.clientTests()))
        files += groupTests
        if api.feeds { files.append(("\(tests)/FeedTests.swift", fill(TestTemplates.feedTests))) }
        return files.map { (path: $0.0, text: $0.1) }
    }

    /// The client's file: the template with the base URL and the auth of the call.
    private func client() -> String {
        var text = ClientTemplates.client
        if let base = api.baseURL {
            let declaration = "    /// The base URL a client starts at unless it is given another: `\(base)`.\n"
                + "    public static let defaultBaseURL = URL(string: \(Sample.quoted(base)))!\n\n"
            text = text.replacingOccurrences(of: "__BASE_DECL__", with: declaration)
                .replacingOccurrences(of: "__BASE_DEFAULT__", with: " = \(api.client).defaultBaseURL")
                .replacingOccurrences(of: "__EXAMPLE_BASE__", with: base)
        } else {
            text = text.replacingOccurrences(of: "__BASE_DECL__", with: "")
                .replacingOccurrences(of: "__BASE_DEFAULT__", with: "")
                .replacingOccurrences(of: "__EXAMPLE_BASE__", with: "https://api.example.com")
        }
        return fill(text.replacingOccurrences(of: "__AUTH__", with: authExpression))
    }

    /// The call's auth as the generated `AuthScheme` says it.
    var authExpression: String {
        switch api.auth {
        case .none: return ".none"
        case .bearer: return ".bearer"
        case .basic: return ".basic"
        case .header: return ".header(\(Sample.quoted(api.authName ?? "")))"
        case .query: return ".query(\(Sample.quoted(api.authName ?? "")))"
        }
    }

    private func fixture() -> String {
        let tokens = api.auth == .none ? "" : "[\"example.com\": token]"
        return fill(TestTemplates.fixture.replacingOccurrences(of: "__TOKENS__", with: tokens)
            .replacingOccurrences(of: "__AUTH__", with: authExpression))
    }

    /// A template with the package's names in it.
    func fill(_ template: String) -> String {
        template.replacingOccurrences(of: "__STEM__", with: api.stem)
            .replacingOccurrences(of: "__MODULE__", with: api.module)
            .replacingOccurrences(of: "__ABOUT__", with: "the \(api.stem) API")
    }
}
