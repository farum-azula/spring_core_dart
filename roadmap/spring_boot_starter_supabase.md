# spring_boot_starter_supabase (planned, after spring_boot_starter_data)

Supabase in Spring's way, on a server and in Flutter apps: its database
through the data starter's repositories, its Auth as one more login of
the security starters, later Storage, Realtime and Edge Functions
([serverless.md](serverless.md)).

## Decisions (the owner, October 2026)

- **Its own starter, on Supabase's official packages** (`supabase`, pure
  Dart: `postgrest`, `gotrue`, `realtime_client`, `storage_client`; its
  publisher is supabase.io). The third-party dependency stays in this
  starter (the rule of `roadmap/README.md`); the data and security
  starters do not know Supabase.
- **One session, ours.** The security starters keep the user, the tokens
  and their refresh (`PrincipalNotifier`, the secret stores, the server's
  session). Supabase's client never keeps a session of its own: it is
  given the current access token (the `accessToken` callback of
  `SupabaseClient`, made for third-party auth), so there are never two
  logins to keep apart.
- **Supabase Auth is a login like the others.** With this starter and
  `spring.supabase.*`, it plugs into security by itself:
  - Flutter app: a login service next to the OAuth2 ones (email and
    password, magic link, OTP, the providers Supabase Auth offers),
    whose tokens go to our `PrincipalNotifier` and secret store, and
    from there to Supabase's client and to Feign / the REST clients;
  - server: Supabase's access tokens are accepted as bearer tokens —
    the resource server's `JwtDecoder` from the project's JWKS
    (`https://<ref>.supabase.co/auth/v1/.well-known/jwks.json`, issuer
    `https://<ref>.supabase.co/auth/v1`, audience `authenticated`), the
    roles from `app_metadata` (a `GrantedAuthoritiesMapper`), so
    `@PreAuthorize` works on a Supabase user;
  - other logins (Keycloak, Google through our OAuth2 login) can be
    Supabase's "third-party auth": their token goes to Supabase as it
    is, row-level security reads its claims.
- **The tables only through the data starter** (the owner): this
  starter depends on `spring_boot_starter_data` and has no table API of
  its own; applications use the data starter's entities, repositories
  and templates, the same code as with any database. Underneath, by
  where it runs:
  - **on a server** with `spring.supabase.db.url` (Supabase's direct or
    pooler connection string; the `postgres` driver in the
    application's dependencies) it configures the data starter's
    PostgreSQL datasource: everything of the data starter works —
    transactions, `@Lock`, SQL `@Query`, `JdbcClient`;
  - **in a Flutter app** (no database credentials there) it adds a store
    of the data starter over PostgREST, described next; the user's
    token decides what row-level security lets through.
- **The PostgREST store**: a store this starter adds to the data starter
  (`@Repository(store: 'supabase')`, or the default store of a Flutter
  app with this starter), generated calls of the
  `postgrest` client: derived queries as filters
  (`findByTitleContainingIgnoreCase` → `.ilike('title', '%dune%')`),
  `Pageable` as `range` with an exact count, `Sort` as `order`,
  `@Version` as a `PATCH` filtered on the version (no row back:
  `OptimisticLockingFailureException`), joins as PostgREST embedding
  (`@Select('id,title,author:authors(name)')`), Postgres functions as
  `@Rpc('place_order')` (the way to do several changes atomically, with
  locks inside the function). No `@Transactional`, `@Lock` or SQL
  `@Query` on these repositories: build errors. Errors translated into
  the data starter's `DataAccessException`s (`23505` →
  `DuplicateKeyException`, row-level security → permission denied); logs
  as the data starter's (the method, the filters, the time; never the
  token or the key).
- **`service_role`** (bypasses row-level security) only on a server, from
  the environment; the starter refuses it in a Flutter build.

## Properties

```properties
spring.supabase.url=https://xyz.supabase.co
spring.supabase.anon-key=${SUPABASE_ANON_KEY}
# Server only, never in an app:
spring.supabase.service-role-key=${SUPABASE_SERVICE_ROLE_KEY}
spring.supabase.db.url=postgresql://postgres.xyz:${DB_PASSWORD}@aws-0-eu-central-1.pooler.supabase.com:5432/postgres
# Supabase Auth as the login (Flutter), or accepted tokens (server):
spring.supabase.auth.enabled=true
```

## Later

Realtime (`Stream<List<Order>>` from a repository method), Storage
(`Resource`s), Edge Functions (the serverless roadmap), the offline
cache with SQLite and sync.
