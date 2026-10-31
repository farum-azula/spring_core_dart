# The edge starter: the same application on fetch platforms (planned, a 0.5.x patch)

Dart compiles to JavaScript, and the family already runs without
`dart:io` and without reflection (Flutter web proves it). Serverless
edge platforms run a JavaScript function that takes a `Request` and
returns a `Response` (the fetch API): Supabase Edge Functions (Deno),
Deno Deploy, Cloudflare Workers, Vercel and Netlify Edge Functions. One
adapter from that function to the web starter's dispatcher runs an
ordinary Spring Boot for Dart application there, controllers, filters,
security and Feign clients unchanged.

Spring's counterparts: Spring Cloud Function and its adapters (AWS
Lambda, Azure, Google Cloud), and AWS's serverless Java container that
runs Spring MVC applications in a function.

## 1. The fetch adapter

```dart
@RestController()
class BooksController {
  @GetMapping('/books')
  Future<List<Book>> list() => books.all();
}

@SpringBootApplication()
void main() => runFetchApplication(springApplication); // a fetch handler, no HttpServer
```

```
dart compile js -O2 bin/main.dart -o supabase/functions/books/main.js
supabase functions deploy books
```

- What exists: the web starter keeps `dart:io` behind `WebServerFactory`
  and conditional imports; the dispatcher, the filters, CORS,
  `ProblemDetail` and the security chain work on `ServerHttpRequest` /
  `ServerHttpResponse` of `spring_web_dart`. Missing: those two over the
  platform's `Request` / `Response` (through `dart:js_interop`), and a
  `runFetchApplication` that starts the context once per instance and
  hands every request to the dispatcher.
- The JavaScript entry (`index.ts` for Deno, `export default { fetch }`
  for Cloudflare) written by the generator or a command of the starter,
  never by hand.
- Request bodies and streamed responses (SSE) on the fetch streams;
  multipart in memory (no file system).
- Outgoing calls: `FetchHttpTransport` (exists).
- Platform-specific hooks behind one interface: background work after
  the response (`EdgeRuntime.waitUntil` on Supabase, `ctx.waitUntil` on
  Cloudflare), environment variables (`Deno.env`, the Worker's `env`) as
  a property source.
- JavaScript or WebAssembly, chosen by a property, so the same project
  builds either way without changing code or the workflow:

  ```yaml
  spring:
    edge:
      target: js      # js (default) | wasm
  ```

  - `js`: `dart compile js -O2`, one `main.js`; runs on every fetch
    platform.
  - `wasm`: `dart compile wasm -O2` (WasmGC), `main.wasm` with its
    `main.mjs` loader; faster code, but the platform's runtime must have
    WasmGC (V8-based runtimes do: Deno, so Supabase Edge Functions and
    Deno Deploy, and Cloudflare Workers — each checked before it is
    listed as supported).
  - The generator (or the starter's command) reads the property, as it
    does for `spring.flutter.web.*`, and writes the matching entry
    (`index.ts` loading `main.js`, or instantiating `main.wasm` through
    `main.mjs`); the GitHub Actions workflow runs the matching compile
    command. A profile can switch it (`application-wasm.yaml`) to compare
    both.
  - Checked at start: on a runtime without WasmGC the function fails at
    once with a message saying to use `target: js`, never half-working.
  - Measured and documented per platform: cold start, size (some
    platforms limit a function's size), throughput, js against wasm.

## 2. Supabase

- The function's environment (`SUPABASE_URL`, `SUPABASE_ANON_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`, the project's secrets) as properties.
- Supabase Auth's JWTs checked by the resource server (the project's
  issuer and JWKS), so `@PreAuthorize`, roles and `@AuthenticationPrincipal`
  work; the anonymous and service-role keys told apart.
- Later: the database through PostgREST (a client, or part of the data
  starter), Storage, Realtime.

## 3. Deploying from GitHub Actions

A ready workflow (documented, and written by a command of the starter
into the application's `.github/workflows/`):

- on a push to `main` (or a tag): `dart pub get`, the generator,
  `dart compile js`, the JavaScript entry;
- `supabase/setup-cli` and `supabase functions deploy <name>
  --project-ref <ref>` with the `SUPABASE_ACCESS_TOKEN` and the project
  ref as repository secrets; the function's secrets set with
  `supabase secrets set` from GitHub secrets, never committed;
- a preview deploy per pull request when the project has branching.

## What does not fit a function

- Instances are short-lived and share nothing: no in-memory sessions
  (JWT only), no `@Scheduled` (the platform's cron or a queue instead),
  no long background work beyond what the platform's `waitUntil` allows.
- No file system and no `dart:io`; no sockets but fetch (and WebSocket
  where the platform has it).
- The platforms' limits (CPU time per request, memory, function size)
  checked and documented before building; the cold start (a context
  started per instance) measured.

## Open: what the other starters do there (to design separately first)

Some starters cannot work fully in a function: timers (`@Scheduled`
with `fixedRate` / `fixedDelay`) die with the instance, an in-memory
cache or session store is per short-lived instance, there is no file
system for log files or multipart uploads, no isolates for `@Async`, no
listening socket for a WebSocket server. An application must not start
half-working: what cannot work fails the build or the start with the
reason; what works differently says so once.

The direction discussed (not decided): starters never name platforms.
`spring_boot_dart` holds a few facts about the runtime (does the process
live long, is memory shared between requests for long, is there a file
system, are there isolates, can it listen on a port); each starter
checks the facts it needs (the scheduler: "does the process live long");
only the edge starter knows the platforms and sets the facts for them.
The same facts would serve Flutter web (no file system, no isolates)
and the server's several isolates (no memory shared between them).

Two shapes to choose between (names readable, saying what they mean):

1. Facts named after what a starter needs, read like a sentence:

   ```dart
   runtime.canRunTimers               // timers outlive a request
   runtime.keepsMemoryBetweenRequests
   runtime.hasFileSystem
   runtime.canStartIsolates
   runtime.canListenOnPort
   ```

   The scheduler: `if (!runtime.canRunTimers) ...`. Precise, one fact per
   need.

2. The kind of runtime, no flags:

   ```dart
   enum RuntimeKind { server, app, browser, function }
   ```

   The scheduler: `if (runtime.kind == RuntimeKind.function) ...`.
   Simplest to read, still no platform names (Supabase and Cloudflare are
   both `function`), but coarser: a starter must know what each kind
   lacks (a browser has no file system).

It touches `spring_boot_dart` and every starter, so it is designed on
its own, before the edge starter: the list of facts, how a starter
declares what it needs (an annotation the generator can check at build
time, a condition, both), what fails the build, what fails the start,
what only warns, and Spring's counterparts (`@ConditionalOnCloudPlatform`,
`@ConditionalOnWebApplication`, `@ConditionalOnThreading`, the GraalVM
native image's unsupported features).

## When and the name

A 0.5.x patch, after the review and the 0.5.0 release
([review_0_5.md](review_0_5.md)), Supabase first. One package, working
name `spring_boot_starter_edge` ("Spring edge"): the fetch adapter and
the platforms' integrations (Supabase first) together, split only if a
platform needs dependencies of its own; the exact name settled when it is
built.
