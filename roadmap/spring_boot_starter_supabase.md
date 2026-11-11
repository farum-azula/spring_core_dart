# spring_boot_starter_supabase (planned, after the generator's split by starter)

Supabase in Spring's way, on a server and in Flutter apps: its database
through Spring Data, its Auth through Spring Security, Realtime as
streams, Storage as a template, Edge Functions as a declared interface.
All in the first version.

Order (the owner, November 2026): after
[generator_by_starter.md](generator_by_starter.md), so that whatever the
starter needs from the generator lands in a part of its own and nothing
Supabase-specific is wired into the core.

## Decisions (the owner, November 2026; replace those of October)

- **Our own client, not Supabase's packages.** PostgREST, Auth (GoTrue),
  Storage and Functions over `spring_web_dart`'s HTTP client; Realtime
  over the WebSocket starter (below). No third-party dependency, pure
  Dart, compiles to WebAssembly. Supabase's packages would save mostly
  the Realtime protocol, at the price of nine third-party packages, a
  session of their own to switch off, their own errors and logs.
- **Spring beans for everything, in the first version**: data, auth,
  Realtime, Storage, Edge Functions.
- **One session, Spring Security's.** Every call takes its token from
  one bean, `SupabaseCredentials`: in a Flutter app the signed-in user's
  access token (refreshed before it expires), else the anon key; on a
  server the current request's bearer token when it is a Supabase user's,
  else the anon key; the service role only inside
  `credentials.asServiceRole(...)`. A token is only ever sent to
  `spring.supabase.url`.
- **Nothing is forbidden in a Flutter app, it is warned about.** A key or
  a password that ships in an app (`service-role-key`, `db.url`,
  `auth.jwt-secret`) is the developer's choice (an internal tool, an admin
  app): no build error, one loud warning in the build's log and one in the
  application's log at startup, saying what ships in the app and what
  anyone holding the app can do with it.
- **Data only through Spring Data**, the path decided at build time and
  visible:
  - `spring.supabase.db.url` set: the data starter's SQL store over
    PostgreSQL, on a server or in a Flutter app (the developer's choice,
    with the warning above). Transactions, `@Lock`, SQL `@Query`,
    `JdbcClient` work.
  - not set (the default): the PostgREST store; `@Transactional`, `@Lock`,
    SQL `@Query` and `JdbcClient` on its repositories fail the build with
    the reason and the fix (`db.url`, or `@Procedure` for atomic work).
  - The startup log says the path, the connection kind and the
    repositories on it; the actuator's `info` too (never keys).
- **No token check of our own** (Security, below).

## The generator: nothing about Supabase in it

Everything the starter declares goes through mechanisms the generator
already has, or general features of the data starter's part of the
generator (after the split):

| What | How | Generator |
|---|---|---|
| `@EdgeFunctions`, `@StorageBucket`, `@RealtimeChannel`, `@PhoenixChannel` | annotations marked `@InterfaceProxy`, handlers in the starters | none |
| `StorageTemplate`, `SupabaseAuth`, `SupabaseCredentials` | beans | none |
| The PostgREST store | a `DataStore`; derived queries reach it as `Criteria` at run time | none |
| `@Procedure`, repository methods returning `Stream` | general data-starter features (database functions, watching changes), for any store that supports them | data part |
| Build errors for `@Transactional` / `@Lock` on PostgREST | a store declares its capabilities (transactions, locks, SQL); the data part checks capabilities, not "Supabase" | data part |

## 1. The package and its foundations

- **Expressions in every declared interface** (the owner, November
  2026): the texts of `@StorageBucket` and its methods' paths,
  `@RealtimeChannel` topics and `@EdgeFunction` names take, like the rest
  of the framework, `${property}` placeholders, `{parameter}` (a method's
  parameter by name) and SpEL in `#{...}`, evaluated at each call by the
  handler (the core's `SpelExpressionParser` with the template context;
  nothing in the generator): the parameters as `#name`, `authentication`
  and `principal` as in `@PreAuthorize`, beans as `@name`. So
  `@Upload('#{authentication.name}/avatar.png')` needs no user id
  parameter a caller could set to another user's. What an expression or a
  parameter gives is a value, never a path: each is one encoded segment
  (`/`, `..` and an empty value refused), so no call leaves its bucket or
  folder.

- `spring_boot_starter_supabase`: depends on `spring_boot_dart`,
  `spring_web_dart`, `spring_boot_starter_data`, `spring_security_core`,
  `spring_boot_starter_websocket`, `spring_boot_starter_feign`; not on the
  security starters (the server side is configured through their
  properties).
- Properties (`spring.supabase.*`): `url`, `anon-key`,
  `service-role-key`, `db.url`, `db.rls`, `auth.enabled`,
  `auth.redirect-urls`, `auth.jwt-secret` (legacy projects; only a server
  checks tokens, so it has no use in a Flutter app), `realtime.*`,
  `storage.*`, `functions.*`, timeouts.
- Modules: one everywhere (the service role included), one
  `ModulePlatform.native` (the resource server's settings, the legacy
  secret).
- Warnings, never build errors: `service-role-key`, `db.url` or
  `auth.jwt-secret` in a Flutter app, in the build's log and once at
  startup (`service-role-key`: "ships in the app; whoever has the app
  reads and writes every table past row-level security").
- The HTTP client: base URL, `apikey` and `Authorization`, timeouts,
  errors to exceptions, an `Observation` per call (`supabase.rest`,
  `.auth`, `.storage`, `.functions`), logs without tokens or keys.

## 2. Data

- SQL path: `db.url` configures the data starter's PostgreSQL datasource;
  the connection kind is read from the URL and said at startup:
  `db.<ref>.supabase.co:5432` direct (IPv6); `…pooler.supabase.com:5432`
  session pooler (everything works); `…pooler.supabase.com:6543`
  transaction pooler (prepared statements off, a warning: no advisory
  locks across transactions, no LISTEN).
- `spring.supabase.db.rls: user` (off by default): each transaction sets
  `role authenticated` and `request.jwt.claims` of the current user, so
  row-level security applies with transactions and locks.
- PostgREST store: `Criteria` to filters (`eq`, `neq`, `gt`, `in`, `is`,
  `like`, `ilike`, `or`/`and`, `not`), `Sort` to `order`, `Pageable` to
  `Range` with an exact count, `@Version` as a `PATCH` filtered on the
  version (no row back: `OptimisticLockingFailureException`), upsert,
  `@Reference` / `@MappedCollection` as embedding, `deleteWhereAndReturn`.
- `@Procedure('name')`: `POST /rest/v1/rpc/name`, or `select * from name(...)`
  in the current transaction on the SQL path.
- Errors to the data starter's exceptions (`23505` duplicate key, `23503`
  foreign key, `42501` / RLS: permission denied, `PGRST116` no row, …).

## 3. Security

Supabase plugs into existing extension points; the filter chain is not
changed.

- Server: the starter sets the existing `JwtDecoder`'s settings
  (overridable): the project's JWKS
  (`/auth/v1/.well-known/jwks.json`), ES256 and RS256 only, issuer
  `https://<ref>.supabase.co/auth/v1` exactly, audience `authenticated`
  exactly; a user only with `role = authenticated` (`anon` and
  `service_role` bearer tokens refused: the anon key is itself a signed
  JWT); roles from `app_metadata` only, never `user_metadata` (users can
  edit it). Needs one change of the security starter:
  `authorities-claim-name` reading a nested claim (`app_metadata.roles`).
  Legacy HS256 projects: the secret on a server only, by an explicit
  property.
- `spring_security_core`: `LoginSession` (the current `Authentication`,
  its tokens, refresh, a stream of changes, sign-out); the Flutter
  security starter takes any `LoginSession` bean into `PrincipalNotifier`
  and the secret store.
- Flutter: `SupabaseAuth` (a `LoginSession`): sign-up, password, OTP
  (email, phone), magic link, providers with PKCE (redirect only to
  `auth.redirect-urls`, through the deep links), id tokens (native Google
  / Apple), password reset, `updateUser`, sign-out revoking the refresh
  token; refresh-token rotation, a failed refresh signs out; tokens never
  in logs, observations or the timeline.
- Attack tests, one each: expired, wrong `iss`, wrong `aud`, the anon key
  as bearer, the service role as bearer, `alg: none`, HS/RS confusion, a
  forged JWKS host, roles in `user_metadata`, a token relayed to another
  host, refresh replay, a redirect to an unlisted URL; compared with
  Spring Security; ZAP with a Supabase-secured example.
- Caches (the owner, November 2026: the user is part of the key). With
  row-level security one call answers differently per user, and a cache
  key made of the arguments alone would hand one user's rows to another,
  or a service-role answer to a user. So with this starter every cache
  key carries who the call is made as (`anon`, the user's id, `service`),
  by default, through the cache starter's existing extension points (a
  `CachingConfigurer` of the starter):
  - `SupabaseKeyGenerator` (bean `supabaseKeyGenerator`, a
    `KeyGenerator`), the default one with this starter: the key is who
    calls plus the arguments. Public: an application's own generator
    extends or calls it, and `keyGenerator: 'supabaseKeyGenerator'` names
    it where another default is set.
  - an explicit `key:` goes past any key generator (the cache starter's
    rule, as in Spring), so the starter's `CacheResolver` gives, for the
    operations that have a `key:`, caches that add the same part, taken
    from the same generator. No key is scoped twice.
  Nothing to write in `@Cacheable`; a cache of data that is the same for
  everyone is named in `spring.supabase.cache.shared`. A new login in a
  Flutter app thus never reads the previous user's entries. Tests: two
  users, the anon key and the service role on one cached method. Streams
  (`watchBy…`, a `Stream` download) are not cacheable, as now; a
  `@SignedUrl` cached for longer than its `expiresIn` is a warning at
  startup.
- What protects the data is the database: RLS, column privileges
  (`grant update (name) …`), `CHECK` and `pg_jsonschema`. The docs say so;
  a test sends a request straight to PostgREST with an extra column and
  expects the database to refuse it.

## 4. Realtime

- First, in the WebSocket starter (useful without Supabase): a Phoenix
  Channels client: the envelope (`topic`, `event`, `payload`, `ref`,
  `join_ref`), replies by `ref`, heartbeat, channels over one connection,
  rejoin after its existing reconnect; `@PhoenixChannel('topic')`
  interfaces with `@OnEvent` / `@Push`, like `@WebSocketClient`.
- In this starter, on top: the join payload (`postgres_changes` with a
  filter, broadcast, presence), the access token sent to the channels
  when it changes, presence from `presence_state` and `presence_diff`;
  repository methods `watchBy…` (`Stream<List<T>>`: the rows, then kept
  up to date) and `changesBy…` (`Stream<RowChange<T>>`), the criteria
  Realtime cannot filter applied on our side; `@RealtimeChannel` with
  `@Broadcast` and `@Presence`.

## 5. Storage

- `StorageTemplate`: `upload` (bytes or a stream, content type, upsert),
  `download` (a stream), `read<T>` / `store` (JSON through the
  `ObjectMapper`), `publicUrl`, `signedUrl`, `signedUploadUrl`, `list`,
  `delete`, `move`, `copy`, `exists`, `info`, buckets (service role);
  `resource(bucket, path)` as a `WritableResource`; `asServiceRole()`; a
  `MultipartFile` uploaded as a stream on a server; typed errors
  (not found, duplicate, permission denied). Resumable uploads (TUS)
  later.
- Declared buckets (the owner, November 2026), on top of the template:
  an `@StorageBucket('avatars')` interface (an `@InterfaceProxy`
  annotation of its own, not `@FeignClient`: a public URL is no request,
  a signed URL is completed from the answer, bodies are streams), its
  handler calling `StorageTemplate`. Methods with a path template filled
  from the parameters: `@Upload('{userId}/avatar.png', contentType:,
  upsert:)` (bytes, a stream or a `MultipartFile`), `@Download(...)`
  (`Stream<List<int>>` or `Uint8List`), `@SignedUrl(..., expiresIn:)`,
  `@PublicUrl(...)`, `@StorageObject(...)` (JSON through the
  `ObjectMapper`, read by a method that returns, stored by one that takes
  a value), `@DeleteObject(...)`. Why: the paths of a bucket in one place
  (Storage's RLS policies depend on the shape of the path), and AOP as on
  any bean (`@PreAuthorize`, `@Cacheable`). The template stays for what is
  not known at build time: `list`, `move`, `copy`, buckets. Not in Spring
  (Spring Cloud AWS has `S3Template` and `S3Resource` only): ours.

## 6. Edge Functions

- `@EdgeFunctions()` interfaces with `@EdgeFunction('name', method:)`, on
  the Feign machinery: `…/functions/v1`, the token from
  `SupabaseCredentials`, JSON, `@RequestParam` / `@RequestBody`, Feign's
  errors, an observation per call.

## 7. Schemas

- With [generator_by_starter.md](generator_by_starter.md) done, in the
  data part (for any database, not only Supabase): entities checked
  against the schema of the migrations at build time (a missing column, a
  type, nullability), and optionally `@Table` classes generated from the
  migrations. PostgREST's OpenAPI document (with the server key in the
  build environment only) as a source for a project without migrations;
  `spring.json.schemas` learns pointers into a document (`#/definitions`)
  and PostgreSQL's formats.

## 8. Tests

The owner, November 2026: everything is written and tested first without
the full stack; the stand in Docker (the whole of Supabase) comes last,
when the rest is done. The starter's tests run in a CI pipeline of their
own (`.github/workflows/supabase.yml`), not in the main one.

| Level | What | Needs |
|---|---|---|
| 1 | `Criteria` to PostgREST filters; the Phoenix protocol against a fake server; `StorageTemplate`, Auth and functions against a fake HTTP server; every token check with generated keys (expired, wrong `iss` / `aud`, `alg: none`, HS/RS confusion, the anon key and the service role as bearer, roles in `user_metadata`); path segments; cache keys with the caller; SpEL | nothing |
| 2 | The SQL path: `db.url`, transactions, locks, `@Procedure`, row-level security through `db.rls: user` | one PostgreSQL container (`PostgresContainer`) |
| 3 | The PostgREST store against a real PostgREST: filters, error codes, `Range` and counts, embedding, upsert, `@Version`; RLS with a token signed by the test's own key | PostgreSQL and PostgREST containers |
| 4, last | What only the real services answer: Auth (sign-up, password, OTP and magic links through the mail catcher, PKCE, refresh rotation and replay, sign-out, the JWKS Auth serves), Realtime (the join, changes filtered by RLS, a new token on an open channel, presence, broadcast, reconnect), Storage (streams, signed URLs that open and expire, policies, `move` / `copy`), Edge Functions, the gateway (`apikey`, one URL), one login for everything | the whole stack: the Supabase CLI (`supabase/setup-cli`, pinned; `supabase start -x studio,imgproxy,vector,logflare`, `supabase db reset`, `supabase status -o env`, `dart test --tags supabase`) |

- Level 4 is a small contract suite (the logic is covered by 1 to 3), so
  one stack for the whole run is enough. The same suite nightly / manual
  against a hosted project (secrets in GitHub), for API changes.
- Later, for applications (not needed for the starter's own tests): a
  `SupabaseContainer` in `spring_boot_starter_test` over Supabase's
  official Docker Compose file, when the test starter has Compose
  (`@Container`, `@ServiceConnection` setting `spring.supabase.*`,
  users through the admin API, `signedInAs(email)`). No official
  single-container image exists (`supabase/supabase-dev` is abandoned).
- To check at level 4: the CLI's asymmetric signing key, so the JWKS path
  is tested against the stack itself.

## 9. Example and docs

- `example/supabase`: a Flutter app (login, a live list, avatars, one Edge
  Function) and a server (`@PreAuthorize` on Supabase users, `db.url` with
  transactions), its Supabase project beside it; built and tested in CI.
- Every call an `Observation` (the timeline), Realtime channels in the
  task manager, the data path in the actuator's `info`.
- Site pages in English and Japanese, changelogs, `docs/dependencies.md`.

## As built (November 2026): what differs from the plan above

- **A value in a path is checked when it is given**, by `PathSegmentEncoder`
  (`{parameter}` and `#{...}`), and again by `StorageTemplate`, which
  encodes the segments.
- **`@EdgeFunction` names take `${property}` and `@PathVariable()`
  parameters, not SpEL**: an `@EdgeFunctions` interface is a Feign client
  (settings `spring.feign.client.config.supabase-functions.*`), and a
  function's name is fixed where it is deployed.
- **No `resource(bucket, path)`**: the core has no `WritableResource`, and
  `Resource.exists()` is synchronous, which a remote object cannot answer.
- **Uploads are read whole before they are sent**: `HttpTransport` takes a
  request body as bytes. A streamed request body is work for
  `spring_web_dart` (resumable uploads, TUS, come with it).
- **No `@MappedCollection` on the REST store**: the rows of an aggregate
  are written together, in a transaction. Such an entity is refused with
  the reason; references to other aggregates are plain columns and work.
- **The warnings for a key in a Flutter app are at startup only**; the
  build's log would need the generator to know the properties of a
  starter. Open.
- **`spring.supabase.db.rls: user` is refused through the transaction
  pooler** (port 6543): a role set outside a transaction could be used by
  another client's statement.
- **The default store is a property**, `spring.data.store` (general, in
  the data starter); this starter sets it to `supabase` as a default of
  the lowest precedence, and `spring.datasource.url` to
  `spring.supabase.db.url` when that is set.
- **The server's token checks are properties of the security starter**
  (`required-claims`, `secret-key`, a path in `authorities-claim-name`):
  general features there, set by this starter as defaults the application
  can override. The starter does not depend on the security starters.
- **Not on pub.dev yet** (`tool/publish.dart`, `notPublished`): after
  level 4 of the tests.
- **Its tests run only in `.github/workflows/supabase.yml`**
  (`tool/test_all.dart`, `ownPipeline`).
- **The example is `example/supabase`**: `app/` (Flutter, outside the
  workspace), `server/` (a workspace package) and `supabase/` (the CLI
  project, a part of `test/stack`'s). Their tests without a project run in
  the main pipeline; the server's test against a project in the `stack`
  job of `supabase.yml`, the app's by hand. The server lists
  `spring_boot_starter_data` and `postgres` itself for the SQL path.

## Open

- Realtime method names: `watchBy…` / `changesBy…` (proposed) or the
  return type alone.
