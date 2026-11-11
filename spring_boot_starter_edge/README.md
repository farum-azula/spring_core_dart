# spring_boot_starter_edge

The same Spring Boot for Dart application as a **function**: on Supabase
Edge Functions, Cloudflare Workers, AWS Lambda, Deno Deploy, Netlify Edge
Functions and Vercel Functions. The application is compiled to JavaScript
(or WebAssembly) and answers through the platform's fetch API
instead of a socket; controllers, filters, Spring Security, Feign clients
and the other starters are those of a server.

Spring's counterparts: the serverless Java container
(`SpringBootLambdaContainerHandler`) and the adapters of Spring Cloud
Function.

```yaml
dependencies:
  spring_boot_starter_edge: ^0.7.3   # brings and exports the web starter
```

```dart
import 'package:spring_boot_starter_edge/spring_boot_starter_edge.dart';

import 'spring_gen/main.spring.dart';

@RestController()
class BooksController {
  @GetMapping('/books')
  Future<List<Book>> list() => books.all();
}

@SpringBootApplication()
void main() => runFetchApplication(() => springApplication);
```

```bash
dart run build_runner build
dart run spring_boot_starter_edge:build --platform supabase --name api
```

Run with `dart run bin/main.dart`, the same `main` starts an ordinary
server on `server.port`: that is how a function is developed and debugged.

## Building

`dart run spring_boot_starter_edge:build` compiles the application
(`dart compile js -O2 -DSPRING_ALL_PLATFORMS=true`) and writes the entry
file of the platform next to it. Nothing of it is written by hand, and
nothing of it is committed.

| `--platform` | Written to | Files | Deploy |
|---|---|---|---|
| `supabase` | `supabase/functions/<name>/` | `index.ts`, `main.js`, `prelude.js` | `supabase functions deploy <name>` |
| `cloudflare` | `build/cloudflare/` | `worker.mjs`, `main.js`, `prelude.js`; `wrangler.toml` in the application's directory (once) | `npx wrangler deploy` |
| `aws` | `build/aws/` | `index.mjs`, `main.cjs`, `prelude.js` | zip the directory; runtime Node.js 22, handler `index.handler` |
| `deno` | `build/deno/` | `main.ts`, `main.js`, `prelude.js` | Deno Deploy with `main.ts` as the entry point; anywhere else `deno run -A main.ts` (`PORT`) |
| `netlify` | `netlify/edge-functions/<name>/` | `index.js`, `main.js`, `prelude.js` | Netlify's build runs the command |
| `vercel` | `build/vercel/` | `index.mjs`, `main.cjs`, `prelude.js` | the function of a Vercel project (its `fetch` export) |

| Option | |
|---|---|
| `--name`, `-n` | The function's name, `api` by default. On Supabase and Netlify its directory, on Supabase also the first segment of its paths; the Worker's name in a new `wrangler.toml` |
| `--target`, `-t` | `js` (the default) or `wasm` |
| `--entry` | The Dart file with `main`, `bin/main.dart` by default |
| `--output`, `-o` | The function's directory |
| `--optimization` | The `-O` level of the compiler, 0 to 4, 2 by default |
| `--streaming` | AWS: a response-streaming handler (see below) |
| `--path` | Netlify: the paths the function answers, `/*` by default |
| `-D<name>=<value>` | A definition for the compiler |

A function with the web and security starters is about 1.8 MB of
JavaScript (0.6 MB gzipped); its context starts in 50 to 250 ms,
depending on the platform.

`package:spring_boot_starter_edge/build.dart` has the same build as code
(`EdgeBuild`), for build scripts and tests.

[A function from an empty directory to Supabase](doc/first-function.md)
is the whole way, step by step. [Deploying a function](doc/deploying.md) has the steps for Supabase,
Cloudflare and AWS, by hand and from GitHub Actions.

### WebAssembly

`--target wasm` compiles with `dart compile wasm` (WasmGC): `app.wasm`
(about 1.7 MB) with its `app.mjs`, and a small loader in place of the
script; the entry file is the same. The code of the application does not
change.

| Platform | WebAssembly |
|---|---|
| Supabase | yes; list the module in `config.toml`: `[functions.<name>] static_files = ["./functions/<name>/*.wasm"]` |
| Cloudflare | yes: wrangler compiles the module at deploy (a Worker may not at run time) |
| AWS Lambda (Node.js 22) | yes |
| Deno Deploy | yes |
| Netlify, Vercel | not checked |

### A deploy workflow

```bash
dart run spring_boot_starter_edge:workflow --platform supabase --name api
```

writes `.github/workflows/deploy-<name>.yml` into the repository of the
application: on every push to `main` (`--branch`) it runs the generator,
builds the function (`--target`) and deploys it. For `supabase`
(`supabase functions deploy`), `cloudflare` (`wrangler deploy`) and `aws`
(`aws lambda update-function-code`, with GitHub's OIDC). What it needs is
named in its first lines and comes from the repository's secrets and
variables; nothing secret is written. The file is yours afterwards
(`--force` replaces it). Deno Deploy, Netlify and Vercel deploy from the
repository themselves: give them the build command.

## The platforms

### Supabase Edge Functions

- The platform gives the function its paths with the function's name in
  front (`/functions/v1/api/books` arrives as `/api/books`). The entry
  sets `SERVER_CONTEXT_PATH` to `/<name>`, so the mappings are those of a
  server: `@GetMapping('/books')`.
- The context starts while the instance loads.
- The function's environment is the application's environment: a secret
  `GREETING` is `${GREETING}`, and `SPRING_SUPABASE_AUTH_ISSUER` is
  `spring.supabase.auth.issuer`.
- With [`spring_boot_starter_supabase`](../spring_boot_starter_supabase/README.md):
  `spring.supabase.url`, `anon-key` and `service-role-key` default to
  `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`, so
  the repositories (the REST path), Storage and the resource server need
  no configuration. Only the REST path: a function has no sockets, so no
  `spring.supabase.db.url`, no `@Transactional`.
- Set `verify_jwt = false` for the function in `supabase/config.toml`: the
  application checks the tokens itself (the resource server), and can then
  have endpoints open to everyone.
- **The anon key as a bearer token is no token.** The Supabase clients
  send the project's anon key as the bearer token of everyone who is not
  signed in. The key is public and names nobody, so such a request goes on
  without its `Authorization` header (`supabaseAnonKeyFilter`): an open
  endpoint answers it, a protected one answers 401. Nothing is gained by
  sending the key. `spring.edge.supabase.anon-key-as-anonymous: false`
  lets the resource server refuse it instead. The service role key is
  never a user's token: 401.
- On the local stack the functions reach the project at
  `http://kong:8000` while the tokens name `http://127.0.0.1:54321`: set
  `SPRING_SUPABASE_AUTH_ISSUER = "http://127.0.0.1:54321/auth/v1"` under
  `[edge_runtime.secrets]` of `config.toml`. Not needed on a hosted
  project.
- The address of the client is the address of the connection, which is
  the platform's gateway. A rate limit by address needs
  `spring.web.rate-limit.trusted-proxies`; a limit by user does not.

[`example/supabase/function`](../example/supabase/function) is such a
function.

### Cloudflare Workers

- The Worker's `env` arrives with a request, so the context starts with
  the first one. Its string values (`[vars]`, secrets) are the
  application's environment; bindings that are objects (KV, D1) are not
  properties.
- The address of the client is `CF-Connecting-IP`, which Cloudflare's
  network sets itself and replaces when a client sends it.
- `wrangler.toml` is written once into the application's directory, with
  the name, the built `worker.mjs` as `main` and today's compatibility
  date; after that it is yours (bindings, routes, cron triggers).
- **Bindings.** The bean `cloudflareBindings` gives the Worker's KV
  namespaces and D1 databases by the names of their bindings:

  ```dart
  Future<String?> theme() => bindings.kv('SETTINGS').get('theme');

  Future<List<Map<String, Object?>>> orders(String user) => bindings
      .d1('DB')
      .query('select id, total from orders where user = ?1', [user]);
  ```

  They arrive with a request: use them while one is handled, not in a
  constructor. Other kinds of bindings (queues, R2, Durable Objects) have
  no API here yet.
- **The rate limiter in D1.** With
  `spring.edge.cloudflare.rate-limit.database: DB` (the binding of a D1
  database) the rate limiter's counters are in that database
  (`D1RateLimitStore`: one atomic statement, the table created when it is
  missing), shared by every instance of the Worker. KV is no place for
  counters: its writes are not atomic.
- **Cron triggers** (`[triggers] crons` of `wrangler.toml`) run the
  application's `EdgeScheduledHandler` beans (see below).

### AWS Lambda

The entry answers the four HTTP triggers: a function URL and an API
Gateway HTTP API (payload 2.0), an API Gateway REST API (payload 1.0) and
an Application Load Balancer.

- The event becomes a request, the response the result the trigger
  expects: text as text, anything else as base64, cookies where the
  trigger wants them.
- The address of the client is the event's `sourceIp`; behind a load
  balancer, the last address of `X-Forwarded-For`, which the balancer
  adds itself.
- `process.env` is the application's environment.
- A response is buffered by default: an event stream arrives when it
  ended. `--streaming` writes a response-streaming handler for a function
  URL with `InvokeMode: RESPONSE_STREAM`; then the body is sent while it
  is written.

### Deno Deploy, Netlify, Vercel

- `deno`: `main.ts` serves with `Deno.serve`; the address of the client
  is the address of the connection. Run by Deno in the starter's tests.
- `netlify`: an Edge Function for every path (`--path`); the address of
  the client is `context.ip`, the environment `Netlify.env`.
- `vercel`: a function with the web `fetch` export on the Node.js
  runtime; the address of the client is `x-real-ip`, which Vercel sets.

The entries of Netlify and Vercel are checked under the same runtimes
(Deno, Node) with stand-ins for what those platforms give a function,
not on the platforms themselves.

A container platform (Google Cloud Run, Azure Container Apps, Fly) needs
none of this: the application runs there as the ordinary server it is.

## What a function does differently

| | On a server | In a function |
|---|---|---|
| Start | once, when the process starts | once per instance, with its first request (Supabase, AWS: while it loads) |
| TLS, HTTP/2, compression, connection limits | `server.*` | the platform |
| `server.max-http-request-body-size`, `server.request-timeout` | applied | applied |
| A target with `%2F`, `%5C`, `%00`, `.` or `..` | 400 | 400 (`requestTargetProblem`, the same check) |
| The address of the client | the peer of the socket | what the platform names; never a header a client can set |
| Server-sent events, downloads | streamed | streamed (AWS: with `--streaming`) |
| WebSocket endpoints | yes | no: `UnsupportedError` |
| Multipart uploads | on disk above a threshold | in memory |
| `dart:io`, isolates, a database driver | yes | do not compile to JavaScript: the compiler says so |
| Sessions | in memory | per instance: use tokens (`SessionCreationPolicy.stateless`) |

### Work after the answer

A platform may stop an instance as soon as its response is sent.
`EdgeRuntime.waitUntil` keeps it until the work ends:

```dart
@PostMapping('/orders')
Order place(@RequestBody() Order order) {
  runtime.waitUntil(mail.confirm(order)); // after the response
  return order;
}
```

`EdgeRuntime.waitUntil` on Supabase, `ctx.waitUntil` on Cloudflare,
Netlify and Vercel; on AWS the invocation ends when the work did. On a
server, and on Deno Deploy, the work just runs. `EdgeRuntime.platform` is
`supabase`, `cloudflare`, `aws`, `deno`, `netlify`, `vercel`, or `null`
on a server.

### Work by a schedule

A timer does not outlive a request, so `@Scheduled` methods do not run
between requests. The platform's schedule does that work: it runs the
function, and the function calls every `EdgeScheduledHandler` bean.

```dart
@Component()
class NightlyReport implements EdgeScheduledHandler {
  NightlyReport(this.reports);
  final Reports reports;

  @override
  Future<void> onScheduled(EdgeScheduledEvent event) async {
    if (event.schedule == '0 3 * * *') {
      await reports.send();
    }
  }
}
```

- Cloudflare: a cron trigger; `event.schedule` is its expression.
- AWS: an EventBridge rule or schedule with the function as its target;
  `event.schedule` is the rule's ARN.
- Supabase: `pg_cron` calls an endpoint of the function over HTTP, which
  is an ordinary request.

A handler that fails fails the run, after the other handlers ran.

### The warning list

What compiles but works differently is said once, when a function starts:

```
WARN  Running as a function; these work differently here:
  - the rate limiter counts in memory: every instance has its own counters, ...
  - @Scheduled Rates.refresh (PeriodicTrigger(fixedRate: 1:00:00.000000)): timers do not outlive a request; ...
  - cached values (bean 'cacheManager'): kept in the memory of each short-lived instance, ...
  - sessions (bean 'httpSessionRepository'): kept in the memory of each short-lived instance, ...
```

Each line comes from an `EdgeWarningContributor` bean. The starter has
three: an in-memory rate limiter; every `@Scheduled` method (the beans
that are a `TimerDrivenWork`); every bean that keeps its state in the
memory of its instance (the beans that are an `IsolateLocalState`: the
in-memory caches and sessions; a cache kept elsewhere is not listed).
Those two interfaces are `spring_core_dart`'s, and say nothing about a
platform: a pool of isolates warns about the same beans. A bean of the
contributor's type adds its own lines. `spring.edge.warnings: false`
turns the list off.

### The rate limiter

`spring.web.rate-limit.*` and `@RateLimiter` work as on a server, but an
instance's memory is not a place to count: use a shared store. With the
Supabase starter the default store is the project's database function
(`rate_limit_acquire`, called as the service role); in a Worker, a D1
database (`spring.edge.cloudflare.rate-limit.database`); elsewhere declare
a `RateLimitStore` bean. When the store fails, the request is refused
(`on-store-failure: deny`, the default).

## Properties

| Property | Default | |
|---|---|---|
| `spring.edge.runtime` | — | The platform, set by the entry file; read it, do not write it |
| `spring.edge.warnings` | `true` | The warning list at start |
| `spring.edge.supabase.anon-key-as-anonymous` | `true` | The anon key as a bearer token is a request without a token |
| `spring.edge.cloudflare.rate-limit.database` | — | The binding of the D1 database the rate limiter counts in |
| `spring.edge.cloudflare.rate-limit.table` | `rate_limit` | The table of its buckets, created when it is missing |

## Testing

`FetchApplication` is the application as a platform's entry calls it,
without a platform:

```dart
final function = FetchApplication(() => springApplication);
final response = await function.fetch(
  FetchRequest('GET', Uri.parse('https://example.com/books')),
  environment: {'GREETING': 'hello'},
);
expect(response.status, 200);
await function.close();
```

`function.scheduled(EdgeScheduledEvent(time: ...))` runs the scheduled
handlers the same way.

The starter's own tests run a test function (`tool/edge_checks` of the
repository; [`example/`](example) is the example)
with one set of checks ([`test/platform_checks.dart`](test/platform_checks.dart))
in every runtime it can have on a developer's machine, as JavaScript and
as WebAssembly:

| Where | What runs the function |
|---|---|
| the Dart VM | `FetchApplication` |
| AWS Lambda | Node with the entry called by events (function URL, API Gateway, load balancer, EventBridge), and AWS's Lambda runtime image |
| Cloudflare Workers | `workerd` (`wrangler dev`), with a KV namespace, a D1 database and a cron trigger |
| Supabase | the Edge Runtime of the Supabase CLI's stack, behind its gateway |
| Deno Deploy, Netlify | Deno |
| Vercel | Node |

Not run there: the platforms themselves (a deployed function). The
response-streaming handler of AWS is checked with a stand-in for the
runtime's `awslambda`: AWS's emulator does not stream.

## Not yet

- Cloudflare's other bindings (queues, R2, Durable Objects).
- Azure Functions and Google Cloud Functions (their own request types;
  their container platforms run the ordinary server).
- Deploy workflows for Deno Deploy, Netlify and Vercel.
