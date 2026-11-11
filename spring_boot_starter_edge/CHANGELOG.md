## Unreleased

- The first version: `runFetchApplication`, the `main` of an application that runs as a function behind the fetch API (and as an ordinary server on the Dart VM); `FetchWebServer`, the web starter's `WebServer` without a socket, with the built-in server's checks of the request target, the body size limit and the error answers; complete responses with their length, streamed ones (server-sent events, downloads) when the handler flushes.
- `dart run spring_boot_starter_edge:build --platform supabase|cloudflare|aws`: compiles the application to JavaScript and writes the platform's entry file (`index.ts` for Supabase Edge Functions, `worker.mjs` and `wrangler.toml` for Cloudflare Workers, `index.mjs` for AWS Lambda behind a function URL, API Gateway or a load balancer; `--streaming` for a response-streaming handler). `EdgeBuild` is the same as code.
- The platform's environment variables are the application's environment; the address of the client is what the platform names (`sourceIp`, `CF-Connecting-IP`), never a header a client can set.
- `EdgeRuntime` (`platform`, `waitUntil`): work after the answer, kept alive by the platform.
- In a Supabase Edge Function: the function's name is the context path; `spring.supabase.url`, `anon-key` and `service-role-key` default to the function's environment; the anon key as a bearer token is a request without a token (`SupabaseAnonKeyFilter`, `spring.edge.supabase.anon-key-as-anonymous`).
- A warning once at start for what works differently in a function (`EdgeWarningContributor`: an in-memory rate limiter, `@Scheduled` methods, the cache starter; `spring.edge.warnings`).
- `FetchApplication`, `FetchRequest`, `FetchResponse`: the function without a platform, for tests.
- More platforms: `--platform deno` (Deno Deploy), `netlify` (Netlify Edge Functions) and `vercel` (Vercel Functions with the `fetch` export).
- `--target wasm`: the application as a WebAssembly module (`dart compile wasm`) with a loader in place of the script; on Supabase, Cloudflare, AWS Lambda and Deno.
- `dart run spring_boot_starter_edge:workflow`: a GitHub Actions workflow that builds and deploys the function (Supabase, Cloudflare, AWS).
- Work by the platform's schedule: `EdgeScheduledHandler` beans run for a Cloudflare cron trigger and an EventBridge schedule (`EdgeScheduledEvent`, `FetchApplication.scheduled`).
- In a Cloudflare Worker: `CloudflareBindings` (KV namespaces, D1 databases), and the rate limiter's counters in a D1 database (`D1RateLimitStore`, `spring.edge.cloudflare.rate-limit.database`, the store `d1`).
- The warning list names every `@Scheduled` method and every bean with state in memory (`TimerWorkEdgeWarning`, `InstanceStateEdgeWarning`).
