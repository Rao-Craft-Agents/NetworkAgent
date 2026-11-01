# NetworkAgent

An app's backend API layer, written as a local Swift package from one compact line an endpoint, shipped as a
[Granite](https://github.com/riteshpakala/Granite) agent package. A call says each endpoint the way a person would jot
it down and each type in [ModelsAgent](https://github.com/Rao-Craft-Agents/ModelsAgent)'s line; the package writes the
typed client of that API into `Packages/<Name>`: a `Sendable` client whose base URL changes while the app runs, a
transport and a mock, auth with tokens kept per host in the Keychain, requests with path, query, JSON and multipart
bodies, a typed method an endpoint, the DTOs, paging as an `AsyncSequence`, errors and retries, RSS/Atom/JSON Feed when
asked, and tests that run. Then it links the package into the project. Swift 6, iOS 17 and macOS 14, no dependencies.

It is one of the [Rao Craft Agents](https://github.com/Rao-Craft-Agents): independent packages that, tagged in prompts
along the life of a project, build an app of [Loom](https://github.com/riteshpakala/Loom)'s quality. `network` writes
the clients Loom's kits are (a Lemmy-like API with a JWT and page paging, a Mastodon-like one paged by its `Link`
header, feeds, an IPFS-like upload), from lines, for any API.

## How an app finds it

NetworkAgent is a `GraniteAgentPackage`, and it carries a record in its binary:

```swift
@used @section("__DATA_CONST,__granite")
let networkRecord: GraniteRoster.Record = { GraniteRoster.record(NetworkAgent.self) }
```

In [Craft](https://github.com/riteshpakala/Craft), install it from the Agent Store or with
`craft agents add https://github.com/Rao-Craft-Agents/NetworkAgent.git`, then say `$network` in a request:

```
$network the recipe API at api.recipes.example: sign in with email and password for a bearer token, the recipes
page by page, one recipe, create and delete one, and a photo upload
```

The model writes the lines; the call shows on Craft's agent map as `network-1`, and the files it names are built and
tested with the turn.

## What a call takes and answers

| Field | | |
|---|---|---|
| `name` | optional | the package, library and module: `RecipeKit` (its types drop `Kit`: `RecipeClient`); `API` when left out |
| `baseURL` | optional | where the client sends unless told otherwise; the app may change it while it runs |
| `auth` | optional | `bearer`, `basic`, `header`, `query` or `none`; `bearer` when a line stores a token |
| `authName` | optional | the header (`X-API-Key`) or query parameter (`api_key`) for `header` and `query` |
| `endpoints` | optional | one line an endpoint (below) |
| `entities` | optional | one line a type the endpoints send and answer, ModelsAgent's line |
| `paging` | optional | `page` or `cursor`; read from the lines when left out |
| `feeds` | optional | whether the client reads RSS, Atom and JSON Feed (`feed(at:)`); false when left out |
| `coding` | optional | `snake` for snake_case JSON keys; `exact` when left out |
| `dates` | optional | date formats beside ISO 8601: `yyyy-MM-dd HH:mm:ss`, or `seconds` / `milliseconds` |
| `into` | optional | the package's folder, relative to the project; `Packages/<name>` when left out |
| `link` | optional | whether the package is linked into the project; true when left out |
| `directory` | the host's | the folder the host works in; a host fills it and does not show it to a model, and a call whose JSON leaves it out works in the folder the host offers (`AgentHost.directory`) |

The answer is a `NetworkResult`: every file written (`path`, `paths`, absolute, the project file included when it was
linked), the package's folder, the client type, its endpoint methods, the types, what it was linked into, and a
sentence for anything else it did.

## The line

```
POST /v1/session body(Credentials) -> Session as signIn stores token
GET /v1/recipes?page,per_page,course:Course -> RecipePage as recipes paged "the newest recipes first"
GET /v1/recipes/{id:Int} -> Recipe as recipe
DELETE /v1/recipes/{id:Int} as deleteRecipe
POST /v1/photos multipart(photo, caption:String?) -> Photo as Media.uploadPhoto
GET /v1/timeline?max_id,limit -> [Post] as timeline paged
```

- A method, a path and its query. `{id}` is a String path parameter, `{id:Int}` a typed one. The query is
  `?name,name:Type`: each an optional argument of the method, a String unless typed (`page`, `limit`, `per_page`,
  `offset` are Int), required with a trailing `!`. The Swift name is the wire name in camelCase (`community_id` is
  `communityID`), and the wire name is what is sent.
- Then, in any order: `body(Type)` (JSON) or `multipart(field, …)` (a bare name is a file; `name:[File]` several;
  `name:Type` a text field, optional with `?`), `-> Type` (`Data` is the bytes, `String` the text; none is a 204),
  `as name` or `as Group.name`, `paged` or `paged(field)`, `stores token` or `stores token(field)`, and a quoted doc.
- The group is the file an endpoint goes in (`Endpoints/<Group>.swift`): the name before the dot, else the path's first
  segment after `api` and a version, plural when a type has its name (`Endpoints/Posts.swift` beside `Models/Post.swift`).
- Every type a line names is a primitive or has an entity line. A line it cannot read, a type no line declares, a paged
  endpoint with no page or cursor, a token with nowhere to come from: each is refused with the reason, every one at
  once, and nothing is written.

## How the package is made

| Step | What |
|---|---|
| Read | every line parsed and merged with the package's `api.json` (a later call adds; a line replaces the one with its method and path, its name or its type) |
| Resolve | names in Swift, groups, paging (page number, a cursor from the response, or the `Link` header), the token's field |
| Client | `<Stem>Client`: `baseURL` behind a lock, `send(_:)` and `exchange(_:)`, auth from the token kept for the request's host, retries on 429 and (for idempotent methods) 5xx with backoff and `Retry-After` |
| Endpoints | a typed `async throws` method a line, doc-commented from it; a `<name>Pages(…)` `AsyncSequence` for each paged one |
| Models | ModelsAgent's types, public: snake keys written into `CodingKeys`; a default, and an enum field's unknown case, read as the default; a field that holds its own type again (a status that shares a status) kept `@Indirect` |
| Support | `Transport/` (URLSession, a public `MockTransport`), `Auth/` (Keychain and memory token stores), `Request/` (path, query, JSON, multipart), `Errors/`, `Coding/` (ISO 8601 with or without fractions and a zone, then the call's formats), `Paging/`, `Feeds/` |
| Tests | a test an endpoint (the request it makes, the sample answer read and compared with the preview), the page sequences, and the client's own (base URL, the token's host, retries, errors, dates, forms, the preview client) |
| Link | every application target of the project's `.xcodeproj` (a local package reference, the product, the Frameworks phase; a deployment target below the package's raised), or the project's `Package.swift`; once |
| Check | every file staged, parsed with `swiftc -parse`, then moved into the project together |

No model is asked: the same lines make the same package every time.

## Testing

```
swift test                     # the record, the schema, the lines, the files, the links, the record across calls
NETWORK_BUILD=1 swift test     # Lemmy-like, Mastodon-like, feeds and IPFS-like packages built, their own tests run,
                               # built for the iOS simulator; one linked into an Xcode project built for macOS and iOS
```

MIT licensed.
