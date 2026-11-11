# Deploying a function

How an application built with `spring_boot_starter_edge` gets to
Supabase Edge Functions, Cloudflare Workers and AWS Lambda, step by step:
by hand first, then from GitHub Actions.

The steps use each platform's own command line tool. They were written
against the tools' documented commands and the local runtimes the
starter's tests use; a deployed function was not part of those tests, so
treat a command that the platform has since changed as the platform's
word over this page's.

## What is deployed

`dart run spring_boot_starter_edge:build` writes a directory with:

- the application, compiled: one JavaScript file (`main.js`, about
  1.8 MB, 0.6 MB gzipped), or with `--target wasm` a WebAssembly module
  (`app.wasm`, about 1.7 MB) with its loader;
- the platform's entry file, which the platform calls for every request
  and which hands the request to the application.

That directory is the whole function: no Dart SDK, no `pubspec.yaml`, no
packages go to the platform. The platform starts an instance, loads the
entry, the application's context starts once (50 to 250 ms), and the
instance answers requests until the platform stops it.

**JavaScript or WebAssembly.** Both are the same application and pass the
same tests. JavaScript runs everywhere and is the default. WebAssembly
(`--target wasm`) needs a runtime with WasmGC, which Supabase's Edge
Runtime, Cloudflare Workers and Node.js 22 of AWS Lambda have; it is
deployed the same way, with one more file. Measure both for your
application before choosing: the starter makes no promise that one is
faster.

Before any deploy, in the application's directory:

```bash
dart pub get
dart run build_runner build     # the generated code of the application
```

## Supabase Edge Functions

You need the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
and a project. The application's directory has (or gets) a `supabase/`
directory, as `supabase init` makes it.

**1. Sign in and choose the project** (once):

```bash
supabase login
supabase link --project-ref <ref>      # <ref>.supabase.co
```

**2. Declare the function** in `supabase/config.toml`:

```toml
[functions.api]
verify_jwt = false        # the application checks the tokens itself
```

With `verify_jwt = true` (the platform's default) the gateway refuses
every request without a token of the project before the application sees
it, so an endpoint open to everyone would not be. For a WebAssembly
build, also list the module:

```toml
[functions.api]
verify_jwt = false
static_files = ["./functions/api/*.wasm"]
```

**3. Build** into `supabase/functions/api/`:

```bash
dart run spring_boot_starter_edge:build --platform supabase --name api
# or: ... --name api --target wasm
```

The name is the function's address: `/functions/v1/api/...`. The
application's mappings do not repeat it (`@GetMapping('/todos')` answers
`/functions/v1/api/todos`).

**4. Secrets.** The platform gives every function `SUPABASE_URL`,
`SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY`; the starter makes
`spring.supabase.*` of them. Everything else the application reads from
its environment is a secret of the project:

```bash
supabase secrets set MAIL_API_KEY=... GREETING=hello
```

A secret `SPRING_MAIL_HOST` is the property `spring.mail.host`; any
secret is `${NAME}` in `application.yml`.

**5. The database**, when the application counts its rate limits there:
copy `package:spring_boot_starter_supabase/sql/rate_limit.sql` into
`supabase/migrations/` and push it:

```bash
supabase db push
```

**6. Deploy:**

```bash
supabase functions deploy api
```

The CLI bundles `index.ts` with what it imports (`main.js`,
`prelude.js`; the module of a WebAssembly build goes as a static file)
and uploads it.

**7. Call it:**

```bash
curl https://<ref>.supabase.co/functions/v1/api/health
curl https://<ref>.supabase.co/functions/v1/api/todos?list=home \
  -H "Authorization: Bearer <a user's access token>"
```

The function's logs (the application's log lines, its start, the warning
list) are on the function's page of the dashboard.

**Locally** the same directory runs in the CLI's stack: `supabase start`
serves `supabase/functions/api` at
`http://127.0.0.1:54321/functions/v1/api`. There the functions reach the
project at `http://kong:8000` while the tokens name
`http://127.0.0.1:54321`, so the local stack needs one more line in
`config.toml` (a hosted project does not):

```toml
[edge_runtime.secrets]
SPRING_SUPABASE_AUTH_ISSUER = "http://127.0.0.1:54321/auth/v1"
```

## Cloudflare Workers

You need Node.js (for `npx wrangler`) and a Cloudflare account.

**1. Sign in** (once): `npx wrangler login`.

**2. Build:**

```bash
dart run spring_boot_starter_edge:build --platform cloudflare --name shop
# or: ... --name shop --target wasm
```

It writes `build/cloudflare/` and, the first time, `wrangler.toml` into
the application's directory:

```toml
name = "shop"
main = "build/cloudflare/worker.mjs"
compatibility_date = "2026-11-11"
```

`wrangler.toml` is yours from then on; commit it. `build/` is not
committed.

**3. Configuration.** Plain values go into `wrangler.toml`, secrets to
Cloudflare; both are the application's environment (`${NAME}`,
`SPRING_...` as properties):

```toml
[vars]
GREETING = "hello"
```

```bash
npx wrangler secret put JWT_SECRET
```

**4. Bindings**, when the application uses them
(`CloudflareBindings`, the rate limiter in D1):

```bash
npx wrangler d1 create shop                 # prints the database_id
npx wrangler kv namespace create SETTINGS   # prints the id
```

```toml
[[d1_databases]]
binding = "DB"
database_name = "shop"
database_id = "<printed>"

[[kv_namespaces]]
binding = "SETTINGS"
id = "<printed>"

[vars]
# The rate limiter's counters in that database, shared by every instance.
SPRING_EDGE_CLOUDFLARE_RATE_LIMIT_DATABASE = "DB"
```

**5. Deploy:**

```bash
npx wrangler deploy
```

wrangler bundles `worker.mjs` with `main.js` (and uploads `app.wasm` as
a module of a WebAssembly build: Cloudflare compiles it at deploy, a
Worker may not at run time) and prints the address,
`https://shop.<your-subdomain>.workers.dev`.

**6. Your own domain and schedules**, in `wrangler.toml`:

```toml
routes = [{ pattern = "api.example.com", custom_domain = true }]

[triggers]
crons = ["0 3 * * *"]     # runs the EdgeScheduledHandler beans
```

**Locally:** `npx wrangler dev` runs the same Worker in Cloudflare's
runtime with local stand-ins for D1 and KV.

**Limits to know.** A Worker's script may be 3 MB gzipped on the free
plan and 10 MB on the paid one; a function with the web and security
starters is 0.6 MB. The free plan also limits the CPU time of a request
to 10 ms, which the start of the application's context on an instance's
first request can exceed; the paid plan's limit is far above it.

## AWS Lambda

You need the [AWS CLI](https://docs.aws.amazon.com/cli/), signed in to
an account.

**1. Build and zip:**

```bash
dart run spring_boot_starter_edge:build --platform aws --name api
(cd build/aws && zip -q -r ../function.zip .)
```

**2. A role for the function** (once): it lets Lambda run the function
and write its logs.

```bash
aws iam create-role --role-name api-function \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
aws iam attach-role-policy --role-name api-function \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
```

**3. Create the function** (once):

```bash
aws lambda create-function --function-name api \
  --runtime nodejs22.x --handler index.handler \
  --architectures arm64 --memory-size 512 --timeout 30 \
  --role arn:aws:iam::<account>:role/api-function \
  --zip-file fileb://build/function.zip
```

The handler is always `index.handler`. More memory also means more CPU,
and so a shorter start.

**4. An address.** The simplest is a function URL:

```bash
aws lambda create-function-url-config --function-name api --auth-type NONE
aws lambda add-permission --function-name api --statement-id url \
  --action lambda:InvokeFunctionUrl --principal "*" \
  --function-url-auth-type NONE
```

`--auth-type NONE` means AWS lets every request through and the
application decides (Spring Security), as on a server. The same function
also answers an API Gateway HTTP API, an API Gateway REST API and an
Application Load Balancer, without another build: the entry tells the
events apart.

**5. Configuration:** the function's environment variables are the
application's environment.

```bash
aws lambda update-function-configuration --function-name api \
  --environment "Variables={GREETING=hello,JWT_SECRET=...}"
```

**6. Deploy a new version:**

```bash
dart run spring_boot_starter_edge:build --platform aws --name api
(cd build/aws && zip -q -r ../function.zip .)
aws lambda update-function-code --function-name api \
  --zip-file fileb://build/function.zip
```

**Streaming.** A response is buffered by default: server-sent events
arrive when the stream ended. For a body sent while it is written, build
with `--streaming` and switch the function URL to streaming:

```bash
dart run spring_boot_starter_edge:build --platform aws --name api --streaming
aws lambda update-function-url-config --function-name api \
  --invoke-mode RESPONSE_STREAM
```

A streaming build answers function URLs only.

**Schedules.** An EventBridge rule with the function as its target runs
the application's `EdgeScheduledHandler` beans:

```bash
aws events put-rule --name nightly --schedule-expression "cron(0 3 * * ? *)"
aws lambda add-permission --function-name api --statement-id nightly \
  --action lambda:InvokeFunction --principal events.amazonaws.com \
  --source-arn arn:aws:events:<region>:<account>:rule/nightly
aws events put-targets --rule nightly \
  --targets "Id=api,Arn=arn:aws:lambda:<region>:<account>:function:api"
```

**The rate limiter.** The starter has no shared store for AWS: declare a
`RateLimitStore` bean over what the application has (a table in
DynamoDB, a database), or the limits are counted per instance, which the
function says when it starts.

## From GitHub Actions

```bash
dart run spring_boot_starter_edge:workflow --platform supabase --name api
dart run spring_boot_starter_edge:workflow --platform cloudflare --name shop
dart run spring_boot_starter_edge:workflow --platform aws --name api
```

Each writes `.github/workflows/deploy-<name>.yml` into the repository:
on every push to `main` (`--branch`) it installs the dependencies, runs
the generator, builds the function (`--target wasm` for a WebAssembly
build) and deploys it with the steps above. It writes no secret; set
what it names in the repository's settings:

| Platform | Secrets and variables |
|---|---|
| Supabase | `secrets.SUPABASE_ACCESS_TOKEN` (an access token of the account), `secrets.SUPABASE_PROJECT_REF` |
| Cloudflare | `secrets.CLOUDFLARE_API_TOKEN` (a token that may edit Workers), `secrets.CLOUDFLARE_ACCOUNT_ID` |
| AWS | `secrets.AWS_ROLE_ARN` (a role GitHub may assume through OIDC, allowed `lambda:UpdateFunctionCode`), `vars.AWS_REGION`, `vars.AWS_LAMBDA_FUNCTION` |

The workflow deploys the code. What is set once stays outside it: the
function's secrets (`supabase secrets set`, `wrangler secret put`, the
Lambda function's environment), the Supabase migrations, and creating
the Lambda function with its role and address.

## Checking a deployed function

- `GET` an endpoint open to everyone; then one that needs a token,
  without it (401) and with it.
- The first lines of the function's log: `Function started in ... ms`,
  and the warning list (`Running as a function; these work differently
  here`), which names an in-memory rate limiter, `@Scheduled` methods
  and in-memory caches.
- A small load: `dart run tool/function_load.dart <url> --clients 16
  --seconds 10` from the starter's directory prints the rate, the
  latencies and the statuses.
