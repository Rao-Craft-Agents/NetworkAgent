# craft-agent/1 · network

Writes an app's backend API layer — a typed Swift client package with auth, paging, retries, uploads, feeds, models and tests — from one compact line an endpoint, and links it into the project.

network's copy of Craft's agent standard (`craft-agent/1`, Craft's `Schema/Agent.md`), written by
`craft agents schema network` from its record. Everything above **Changes** is written again each time; Changes is
network's own log.

| File | What it holds |
| --- | --- |
| [`network.input.schema.json`](network.input.schema.json) | What it takes, as JSON Schema |
| [`network.answer.schema.json`](network.answer.schema.json) | What it answers: `granite-answer/1` with its own kinds |

## What it takes

| Field | Required | What it is |
| --- | --- | --- |
| `name` | no | the package, its library and module: `RecipeKit` (its types drop Kit: `RecipeClient`); API when left out |
| `baseURL` | no | where the client sends unless told otherwise, `https://api.recipes.example`; the app may change it while it runs |
| `auth` | no | how requests are signed: bearer (OAuth, JWT), basic, header or query (both named in authName), none; bearer when a line stores a token |
| `authName` | no | the header (`X-API-Key`) or query parameter (`api_key`) the token goes in, for auth header or query |
| `endpoints` | no | one line an endpoint: `GET /v1/recipes/{id:Int}?full:Bool -> Recipe as recipe`, then `body(Type)` or `multipart(photo, caption:String?)`, `paged`, `stores token`, a quoted doc |
| `entities` | no | the types the endpoints send and answer, one line each: `Recipe "a dish": id Int, title String, minutes Int = 30, course Course?`; an enum is `Course: starter \| main \| dessert` |
| `paging` | no | page (a `page` number in the query) or cursor (a `cursor`, `page_cursor`, `max_id`, `after` or `page_token` query; the next one from the response or its Link header); read from the lines when left out |
| `feeds` | no | whether the client reads RSS, Atom and JSON Feed with `feed(at:)`; false when left out |
| `coding` | no | snake for snake_case JSON keys; exact when left out |
| `dates` | no | date formats the API writes beside ISO 8601, as patterns (`yyyy-MM-dd HH:mm:ss`), or `seconds` or `milliseconds` for numbers |
| `into` | no | the package's folder, relative to the project; Packages/<name> when left out |
| `link` | no | whether the package is linked into the project's app targets (an .xcodeproj) or its Package.swift; true when left out |

`directory` is filled by Craft with the project folder. The person's request and the host's model are offered
beside the call, never in it.

## What it makes

Nothing declared yet (`makes`): Craft holds no file for it and measures no `made`.

## What it answers

A `granite-answer/1` answer (Granite's `Schema/GraniteAgent.md` §4.2): `paths`, `made` against `expected` by kind and
name, `problems` for what it could only do in part, `payloads` for files that keep a standard of their own, and its
own keys beside them. Craft measures each call by what it made of what it expected.

## How it refuses

With an `AgentRefusal`: a kind and reasons, each with its fix. `input` and `call` are the call's to correct; `build`,
`device`, `reach`, `model` and `host` what stood in the way; `answer` and `parse` its own bug.

## Changes

Each change made to make this agent more precise, dated, with the regime run that measured it and what it
made of what it was asked before and after (`TESTING.md`). Newest first.

### 2026-11-04 · answer `granite-answer/1`

network's answer is a `granite-answer/1` answer by its defaults, and its refusals carry a kind (`call`, `parse`, `host`). It declares nothing it makes yet, so Craft holds no file for it and measures no `made`. (dbac458)

Measured: not yet. Answers before this were pre-standard, so there is no precision to compare; the next regime chain on Margin is the first measure.
