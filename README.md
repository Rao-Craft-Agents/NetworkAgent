# NetworkAgent

Turn the endpoints of an API into a client your app can call. Jot each endpoint down as you would in notes, its
method, its path and what it answers, and `network` writes the typed Swift client for that API as a local package and
links it into your project: a sign-in that keeps its token, a method for every endpoint, the types it sends and
answers, paging, retries, uploads, and tests that run.

## What you can ask

```
$network the recipe API at api.recipes.example: sign in with email and password for a bearer token
$network the recipes page by page, one recipe, create and delete one, and a photo upload
$network a Mastodon-like timeline paged by max_id and the Link header, each status with its account
$network PantryKit, reading RSS, Atom and JSON Feed
```

Craft writes the lines from your request, shows the call on its agent map as `network-1`, and builds and tests what
it writes with the turn.

## What you get

- **A client package, linked in.** A package such as `Packages/RecipeKit` with a `Sendable` client whose base URL can
  change while the app runs, linked into every app target of your Xcode project, or into its `Package.swift`.
- **A typed method for every endpoint.** `async throws` methods with path, query, JSON and multipart bodies,
  documented from your lines, and an `AsyncSequence` of pages for each paged one, by page number, a cursor or the
  `Link` header.
- **Sign-in handled.** Bearer, basic, header or query auth, with tokens kept per host in the Keychain and carried by
  every request after sign-in.
- **Retries and dates handled.** Retries on 429 and, for idempotent methods, on 5xx, with backoff and `Retry-After`;
  dates read in ISO 8601 and the formats you name.
- **The types, a mock and tests.** The request and response types, a `MockTransport` and a preview client, RSS, Atom
  and JSON Feed when asked, and a test for every endpoint.

## How it works

- It asks no model: the same lines make the same package every time.
- Every type a line names is a primitive or has a line of its own. A line it cannot read, a type no line declares, a
  paged endpoint with no page or cursor, a token with nowhere to come from: each is refused with the reason, every
  one at once, and nothing is written.
- The API is kept in the package's `api.json`, so a later call adds to it: give only what is new.
- Every file is parsed with `swiftc -parse` before any lands; what it makes is built and tested with the turn.

## Works well with

`network` writes the clients [Loom](https://github.com/riteshpakala/Loom)'s kits are, for any API: a Lemmy-like API
with a JWT and page paging, a Mastodon-like one paged by its `Link` header, feeds, an IPFS-like upload. Its types are
written in the line `models` reads, while the app's own types stay with `models`; `mocks` fills its package with
believable data until the server exists, and the services `granite` makes call it.

## Get it

In Craft, install Network from the Agent Store, or run
`craft agents add https://github.com/Rao-Craft-Agents/NetworkAgent.git`, then say `$network` in a request.

## Requirements

- A Mac on macOS 14 or later, with Xcode.
- The package is Swift 6 for iOS 17 and macOS 14, with no dependencies; linking raises a deployment target below
  those.
- MIT licensed.

## For developers

What a call takes and answers, the endpoint line and how the package is made are in the
[reference](Docs/Reference.md). The agent standard it follows is [Schema/Network.md](Schema/Network.md), and how it
is measured is [TESTING.md](TESTING.md).
