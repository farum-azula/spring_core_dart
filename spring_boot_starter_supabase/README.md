# spring_boot_starter_supabase

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-supabase](https://farum-azula.org/components/spring-boot-starter-supabase)

[Supabase](https://supabase.com) for
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications, on a server and in Flutter apps: the project's database
through Spring Data repositories, its Auth through Spring Security,
Realtime as streams, Storage as a template and as declared buckets, Edge
Functions as declared interfaces.

The client is the starter's own, over the `HttpTransport` of
`spring_web_dart` and the WebSocket starter: it adds no third-party
package (none of Supabase's; `spring_security_core` brings the family's
one temporary exception, `pointycastle`), and it compiles to
WebAssembly. Every call is made as the same user: one
bean, `SupabaseCredentials`, gives each call its key and its token, and
what a user may read and write is decided by the database (row-level
security).

## Install

```yaml
dependencies:
  spring_boot_starter_supabase: ^0.7.4

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.7.4   # required: writes the repositories and the declared interfaces
```

```bash
dart run build_runner build
```

One import is enough:
`package:spring_boot_starter_supabase/spring_boot_starter_supabase.dart`
re-exports the data, cache, Feign, WebSocket and logging starters,
`spring_security_core` and `spring_web_dart`. The starter does not depend
on the security starters: a server that accepts the project's tokens adds
`spring_boot_starter_security`, a Flutter app that opens a provider's
login window adds `spring_boot_starter_flutter_security`.

## A first example

```yaml
# lib/resources/application.yml
spring:
  supabase:
    url: https://abcd.supabase.co
    anon-key: ${SUPABASE_ANON_KEY}
```

```dart
@Table('todos')
class Todo {
  Todo({required this.title, this.done = false, this.id, this.createdAt});

  @Id()
  int? id;

  String title;
  bool done;
  DateTime? createdAt;
}

// A Spring Data repository: on the project's REST API, as the current user.
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  Future<List<Todo>> findByDoneOrderByCreatedAtDesc(bool done);
}

@StorageBucket('avatars')
abstract interface class Avatars {
  @Upload('#{authentication.name}/avatar.png', upsert: true)
  Future<void> put(Uint8List bytes);

  @SignedUrl('{userId}/avatar.png', expiresIn: Duration(minutes: 5))
  Future<Uri> link(String userId);
}

@EdgeFunctions()
abstract interface class Functions {
  @EdgeFunction('send-invite')
  Future<InviteResult> sendInvite(@RequestBody() Invite invite);
}

@Service()
class Account {
  Account(this.auth, this.todos);

  final SupabaseAuth auth;
  final Todos todos;

  Future<List<Todo>> open(String email, String password) async {
    await auth.signInWithPassword(email: email, password: password);
    // From here every call is made with the user's token.
    return todos.findByDoneOrderByCreatedAtDesc(false);
  }
}
```

The generator writes the beans of `Todos`, `Avatars` and `Functions`. The
repository's query is one request,
`GET /rest/v1/todos?done=eq.false&order=created_at.desc`, with the anon
key as `apikey` and the user's token as the bearer token.

## Configuration

```yaml
spring:
  supabase:
    url: https://abcd.supabase.co
    anon-key: ${SUPABASE_ANON_KEY}
    service-role-key: ${SUPABASE_SERVICE_ROLE_KEY}   # a server only
    db:
      url: ${SUPABASE_DB_URL}                         # optional: SQL instead of the REST API
      rls: user
    auth:
      redirect-urls: [com.example.app://login]
```

| Key | Type | Default | Meaning |
|---|---|---|---|
| `spring.supabase.url` | string | none | The project's address (`https://<ref>.supabase.co`, or the local stack's `http://127.0.0.1:54321`): `http` or `https`, no trailing slash, user, query or fragment (the start fails otherwise). Every service is called under it, and a key or a token is only ever sent to it |
| `spring.supabase.anon-key` | string | none | The anon (publishable) key: `apikey` of every call, and the bearer token while nobody is signed in. Meant to be public |
| `spring.supabase.service-role-key` | string | none | The service role (secret) key, used only inside `SupabaseCredentials.asServiceRole`. It passes row-level security: keep it on a server |
| `spring.supabase.connect-timeout` | duration | `10s` | How long the Realtime connection may take to open, unless the WebSocket client `supabase-realtime` (or `default`) sets its own `connect-timeout`. An HTTP call is limited by `timeout` |
| `spring.supabase.timeout` | duration | `30s` | How long a call may take, the answer's body included. The bodies of Storage downloads are not limited by it |
| `spring.supabase.db.url` | string | none | The PostgreSQL address of the project (`postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres`, or a pooler's). Set: the repositories use SQL over it. Not set: they use the REST API |
| `spring.supabase.db.rls` | `off`, `user` | `off` | As whom SQL runs: the user of `db.url` (`off`), or the current user, with the role `authenticated` (or `anon`) and the token's claims (`user`) |
| `spring.supabase.db.schema` | string | the API's (`public`) | The schema the REST API reads and writes (`Accept-Profile` / `Content-Profile`) |
| `spring.supabase.db.max-rows` | int | `1000` | The most rows the REST API returns in one answer (the project's "Max rows"); an answer that long is read on in further calls |
| `spring.supabase.auth.enabled` | bool | `true` | Whether the starter plugs Supabase Auth into Spring Security: the server's defaults, and the `supabaseAuth` and `supabaseAuthAdmin` beans |
| `spring.supabase.auth.redirect-urls` | list | empty | The addresses a login through a provider, a magic link or a password reset may come back to; the first is the default. Any other `redirectTo` is refused before a request is made |
| `spring.supabase.auth.issuer` | string | `<url>/auth/v1` | The issuer of the project's tokens (their `iss`) |
| `spring.supabase.auth.jwt-secret` | string | none | The legacy JWT secret of a project that still signs with HS256. Server only: with it tokens can be forged for any user |
| `spring.supabase.auth.persist-session` | bool | `true` | Whether the session is kept across restarts, in the application's `SecretStore` (in memory without one) |
| `spring.supabase.auth.auto-refresh` | bool | `true` | Whether the access token is refreshed by a timer before it expires; without it, when the next call needs it |
| `spring.supabase.auth.refresh-margin` | duration | `30s` | How long before its expiry an access token counts as expired |
| `spring.supabase.realtime.heartbeat-interval` | duration | `25s` | How often the Realtime connection says it is alive |
| `spring.supabase.realtime.timeout` | duration | `10s` | How long a join or a message waits for its answer |
| `spring.supabase.realtime.max-message-size` | data size | `4MB` | The largest message read from Realtime; a larger one closes the connection |
| `spring.supabase.storage.signed-url-expiry` | duration | `1h` | How long a signed URL is valid when the call does not say |
| `spring.supabase.functions.region` | string | none | The region the functions run in (the `x-region` header); the nearest one when not set |
| `spring.supabase.functions.timeout` | duration | `spring.supabase.timeout` | How long a function may take |
| `spring.supabase.cache.shared` | list | empty | The caches whose entries are the same for every user; every other cache keeps the entries of each caller apart |

Two more places take settings of the starter's parts:

- `spring.websocket.client.config.supabase-realtime.*` tunes the Realtime
  connection (`reconnect.*`, `connect-timeout`, `max-text-message-size`,
  `phoenix.*`); what is set there wins over `spring.supabase.realtime.*`.
- `spring.feign.client.config.supabase-functions.*` tunes the Edge
  Functions clients (the name of `@EdgeFunctions(name:)`), except
  `follow-redirects`: they never follow a redirect.

At startup the starter says once how the repositories reach the database,
without any password:

```text
Supabase: the repositories use the REST API of abcd.supabase.co, as the current user (row-level security applies); no transactions, locks or SQL (spring.supabase.db.url for those)
```

## Who a call is made as: `SupabaseCredentials`

The repositories, Storage, Edge Functions and Realtime all ask one bean,
`supabaseCredentials`, for the key and the token of a call. The first
that applies:

1. inside `asServiceRole`: the service role key;
2. in a client application with a signed-in user (the `LoginSession`
   bean, which is `SupabaseAuth`): the user's access token, refreshed
   before it expires;
3. on a server handling a request with a bearer token: that token, when
   it is a user's token of this project (its `iss` is the project's
   issuer, its `role` is `authenticated`, it has a `sub`). A token of
   another issuer (Keycloak, a test user) is never sent to Supabase;
4. else the anon key.

```dart
// On a server, a job that must see every row:
await credentials.asServiceRole(() => todos.deleteByDone(true));
```

`asServiceRole` holds for the body and for what it starts (it is kept in
the `Zone`), and throws a `StateError` before the body runs when
`spring.supabase.service-role-key` is not set. `credentials.caller` says
who the next call is made as: `anon`, `user:<id>` or `service`.

The server does not check a token here: the resource server of
`spring_boot_starter_security` has refused anything invalid before a
controller runs ([Security on a server](#security-on-a-server)).

**Keys in a client application.** Nothing is forbidden; it is warned
about. When the application is a Flutter app, each of
`spring.supabase.service-role-key`, `spring.supabase.db.url` and
`spring.supabase.auth.jwt-secret` that is set is logged once at startup
as a warning that says what whoever has the app can do with it (read and
write every table past row-level security; the database password; sign a
token for any user). The warning is at startup only, not in the build's
log.

## Data

The data is reached only through Spring Data: entities, repositories,
derived queries, `Pageable` and `Sort` of `spring_boot_starter_data`.
There are two paths, decided by the configuration:

| | `spring.supabase.db.url` not set (default) | `spring.supabase.db.url` set |
|---|---|---|
| The store | `supabase` (`PostgrestDataStore`): one HTTP request per call to `/rest/v1` | `jdbc`: SQL over PostgreSQL |
| Made as | the current user (`SupabaseCredentials`): row-level security applies | the user of the address (usually `postgres`, who passes row-level security), or the current user with `db.rls: user` |
| `@Transactional`, `@Lock`, SQL `@Query`, `JdbcClient` | no | yes |
| `@MappedCollection` | no | yes |
| How it is set | the starter sets `spring.data.store=supabase` | the starter sets `spring.datasource.url` to `db.url`; the application lists the `postgres` driver package, as for any PostgreSQL data source (the generator writes the driver's glue for the driver package an application lists itself; the data starter comes with this one) |

Both are defaults of the lowest precedence: what the application sets
itself wins. With a `spring.datasource.url` of its own and no `db.url`,
the application's default store stays its own, and a repository goes to
the REST API with `@UseStore('supabase')`.

### The REST store

A derived query becomes filters of PostgREST:

| In the method name | Sent as |
|---|---|
| `findByDone(false)` | `done=eq.false` |
| `Not` | `neq`; with `null`, `not.is.null` |
| `IsNull`, `IsNotNull`, `True`, `False` | `is.null`, `not.is.null`, `is.true`, `is.false` |
| `LessThan`, `LessThanEqual`, `GreaterThan`, `GreaterThanEqual` | `lt`, `lte`, `gt`, `gte` |
| `Between` | `gte` and `lte` |
| `In`, `NotIn` | `in.(…)`, `not.in.(…)`, text values quoted |
| `Like`, `NotLike`, `StartingWith`, `EndingWith`, `Containing`, `NotContaining` | `match` (`imatch` with `IgnoreCase`): an anchored regular expression with the text escaped, so a `*` or a `(` of the value is only text |
| `IgnoreCase` on an equality | `imatch.^text$` |
| `And` | one parameter per condition |
| `Or` | one `or=(…)` parameter, groups as `and(…)`, text values quoted |
| `OrderBy…`, `Sort` | `order=column.asc`, `.desc`, `.nullsfirst`, `.nullslast` |
| `Pageable`, `First`, `Top` | `offset` and `limit` (ordered by the id when no order is given), and for a `Page` a `GET` of no rows (`limit=0`) with `Prefer: count=exact`, as for `count` |

- **`save`.** A new entity is a `POST` (an id that is `null` is left to
  the database); an existing one a `PATCH` filtered on its id. Both ask
  for the row back (`Prefer: return=representation`).
- **`@Version`** works: the update is also filtered on the version it
  read, and no row updated is an `OptimisticLockingFailureException`.
  Without a version it is an
  `IncorrectUpdateSemanticsDataAccessException`.
- **Deleting every row** is sent as `id=not.is.null`: a project's
  database refuses a `DELETE` without a condition.
- **The schema** is `spring.supabase.db.schema`, or the entity's own.

What the REST store cannot do, each refused with the reason and the fix:

- transactions and locks (`@Transactional`, `@Lock`) and the SQL of
  `@Query`: the store says so in its `capabilities`. A repository on
  this store that uses them fails the build, with the fix in the message
  (`spring.supabase.db.url`), and so does a `@Transactional` bean when
  the build's default store is `supabase`. The build reads
  `spring.supabase.url` from `application.yml` (or
  `application.properties`) without a profile; with only
  `spring.supabase.db.url` set it cannot tell the default store, and
  the check happens when the application starts;
- an entity with a `@MappedCollection` (the rows of an aggregate are
  written together, in a transaction); a reference to another aggregate
  is a plain column and works;
- `Distinct`, an order that ignores case, and `IgnoreCase` on a
  comparison other than equality and the text patterns.

For work that must be atomic, write a database function (`@Procedure`), or set
`spring.supabase.db.url`.

A property marked `@Json` (a class of the application, a list or a map
of them) goes into a `jsonb` or `json` column: the store sends it as
nested JSON in the body and reads the answer back into the class through
the application's `ObjectMapper`, with no `@Introspected` to add.
Derived queries cannot filter or sort by it; for a condition on what is
inside, write a database function and call it with `@Procedure`, or use
`@Query` over `spring.supabase.db.url`. The table is yours to create
(`packaging jsonb not null`).

Without `@Json`, the REST store sends a plain `Map` or `List` as JSON as it
is and reads it back. Over `spring.supabase.db.url` the store is the data
starter's SQL store, which refuses such a property when the repository is
created, with the fix (`add @Json() …`); a `List` of simple values in an
array column (`tags text[]`) stays.

### Database functions and changes of rows

`@Procedure('name')` of the data starter declares a database function on a
repository method. On the REST store it is one request,
`POST /rest/v1/rpc/<name>` (`rpc` there is the REST API's own path, not
a name of this package), made as the current user, with the method's
parameters as named arguments in snake case:

```dart
abstract interface class Accounts implements CrudRepository<Account, int> {
  // POST /rest/v1/rpc/transfer   {"from_id": 1, "to_id": 2, "amount": 50}
  @Procedure('transfer')
  Future<void> transfer(int fromId, int toId, int amount);

  @Procedure('accounts_over')
  Future<List<Account>> over(int balance);
}
```

The name is a plain identifier (`@Procedure('schema.name')` is refused on this
store); the function's schema is `spring.supabase.db.schema`. Under the
annotation the store calls a function by name
(`store.callFunction('transfer', {'from_id': 1, …})`): a function that
returns rows gives them, a scalar gives one row with one column named
after the function. With `db.url` the same method calls
`select * from "transfer"(…)` in the caller's transaction.

The REST store also reports the changes of its rows, from Realtime, so a
repository on it has the data starter's two kinds of stream methods:

```dart
abstract interface class Todos implements ListCrudRepository<Todo, int> {
  // The open todos of a list, now and after every change.
  Stream<List<Todo>> watchByListIdAndDoneOrderByIdAsc(String listId, bool done);

  // Each insert, update and delete of the todos of a list.
  Stream<RowChange<Todo>> changesByListId(String listId);
}
```

Both subscribe to the whole table, without a filter of Realtime, and
apply the conditions on this side. A subscription with a filter gets no
delete at all (a delete carries only the primary key, which no filter can
test) and no update that takes a row out of the filter, so a watched list
would keep rows that are gone. What follows:

- `changesBy…` gives an insert or an update whose row matches; an update
  whose row does not match as well, since the row may have matched before
  (test `change.row` when only the rows in the condition matter); and
  **every delete of the table, as the id only**: `change.id` is set,
  `row` and `previous` are null. Realtime does not apply row-level
  security to deletes, so these are also ids of rows the user could not
  read.
- `watchBy…` runs its query again after each of those, once per burst of
  changes; its lists are always exactly the rows of the query.
- With `alter table todos replica identity full` Realtime sends the whole
  old row: `previous` is set, and only the updates and deletes of rows
  that matched before (or match now) are left.
- The cost: every change of the table the user may read travels to the
  client, and a watched query also runs after updates and deletes of rows
  it never held. All the streams of one table share one channel. For a
  large, busy table of which a client follows a small part, use
  `realtime.postgresChanges(table:, filter:)` yourself, knowing what a
  filter leaves out.
- A row that is deleted right after it was written may be reported by
  its delete alone: Realtime checks row-level security against the row as
  it is when it reads the change, and a row that is gone cannot be read.

The SQL store reports no changes: with `db.url`, such a repository takes
`@UseStore('supabase')`.

### Errors

Errors are the data starter's `DataAccessException`s, the same as on the
SQL path:

| Answer | Exception |
|---|---|
| a PostgreSQL code (`23505`, `23503`, `42501`, …) | what the PostgreSQL dialect gives for it: `DuplicateKeyException`, `DataIntegrityViolationException`, `PermissionDeniedDataAccessException`, … |
| `PGRST301`, `PGRST302`, `PGRST303`, or status 401 / 403 | `PermissionDeniedDataAccessException` |
| `PGRST200`, `PGRST202`, `PGRST204`, `PGRST205`, or status 404 | `InvalidDataAccessResourceUsageException` |
| status 409 | `DataIntegrityViolationException` |
| status 500 and above | `DataAccessResourceFailureException` |
| anything else (a filter or a body the API cannot read) | `InvalidDataAccessApiUsageException` |
| no answer | `DataAccessResourceFailureException`; `QueryTimeoutException` for a timeout |

A row that was inserted but may not be read back (the policies allow the
insert and not the select) is a `PermissionDeniedDataAccessException`.

### SQL: `spring.supabase.db.url`

The kind of connection is read from the address and said at startup:

| Address | Kind | Notes |
|---|---|---|
| `db.<ref>.supabase.co:5432` | direct connection | |
| `….pooler.supabase.com:5432` | session pooler | |
| `….pooler.supabase.com:6543` | transaction pooler | a warning at startup: it keeps no session between transactions, so prepared statements, advisory locks and `LISTEN` do not work through it |

`spring.supabase.db.rls: user` (the bean `supabaseRlsSessionHook`, a
`JdbcSessionHook`) makes every transaction, and every statement outside
one, run as the caller, the way the REST API does:

- a signed-in user: the role `authenticated` and the claims of their
  token (`request.jwt.claims`, so `auth.uid()` and `auth.jwt()` work in
  the policies);
- nobody: the role `anon`;
- inside `asServiceRole`: nothing is changed.

In a transaction they are set for that transaction only (`set local`).
Outside one they are set on the connection and reset before it goes back
to the pool; a connection whose reset fails is closed. Only the data
source of `db.url` is touched. Through the transaction pooler `rls: user`
is refused at startup: a role set outside a transaction could be used by
another client's statement.

The database protects the data: row-level security, column privileges,
constraints. The starter only makes sure the database knows who calls.

## Security on a server

On a server (`ModulePlatform.native`; not in a browser build) the starter
sets the properties of Spring Security's resource server, so
`spring_boot_starter_security` accepts the tokens of the project's Auth
as bearer tokens. It applies when `spring.supabase.url` is set and
`spring.supabase.auth.enabled` is not `false`.

| `spring.security.oauth2.resourceserver.jwt.` | Value |
|---|---|
| `jwk-set-uri` | `<url>/auth/v1/.well-known/jwks.json` |
| `jws-algorithms` | `ES256,RS256` |
| `issuer-uri` | `spring.supabase.auth.issuer`, else `<url>/auth/v1` |
| `audiences` | `authenticated` |
| `required-claims.role` | `authenticated` |
| `require-expiry` | `true` |
| `authorities-claim-name` | `app_metadata.roles` |
| `authority-prefix` | `ROLE_` |

So a token must be signed by one of the project's keys with ES256 or
RS256, carry exactly that issuer, the audience `authenticated`, the
role `authenticated` and an `exp`: a token without one is refused. The anon key and the service role key are signed
tokens too; as bearer tokens they are refused (their role is another).
Roles come from `app_metadata.roles` only, as `ROLE_<role>`:
`user_metadata` is never read, since a user can write it. An anonymous
sign-in (`is_anonymous`) is a user with the role `authenticated` and no
roles. A top-level claim literally named `app_metadata.roles` would be
read before the nested one; only the project's own access token hook can
write top-level claims, a user cannot.

```dart
@PreAuthorize("hasRole('editor')")
Future<void> publish(Post post) async { ... }
```

**A legacy secret.** A project that still signs its tokens with HS256
sets `spring.supabase.auth.jwt-secret`; the defaults are then
`secret-key` (that secret) and `jws-algorithms=HS256` instead of the key
set, with the same claim checks. Whoever has the secret can sign a token
for any user: on a server only.

**Overriding.** The defaults have the lowest precedence (below the
application's files, above its `defaultProperties`): whatever the
application sets under `spring.security.oauth2.resourceserver.jwt.*`
wins, key by key. The filter chain is not changed; a chain of your own
works as with any resource server.

## Rate limiting on a server: the database function

A server written with `spring_boot_starter_web` limits its requests with
`spring.web.rate-limit.*` (its
[Rate limiting](../spring_boot_starter_web/README.md#rate-limiting)
section). Where it keeps the buckets depends on how the application
reaches the database:

- **over the REST API** (no `spring.supabase.db.url`; what an edge
  function does): behind one database function, called through
  `/rest/v1/rpc` as the service role (`SupabaseRateLimitStore`;
  `spring.web.rate-limit.store: procedure`). It needs
  `spring.supabase.service-role-key`; the start says so when it is
  missing.
- **over SQL** (`spring.supabase.db.url`): in the same table, with the
  data starter's SQL store (`store: jdbc`).

Both do the whole arithmetic in one statement on the database's clock, so
every server and every function instance shares the limits. The table
and the function come from a migration of the project: the REST API
cannot create them, so the application does not start without them (it
calls the function once at startup and says what to run;
`spring.web.rate-limit.verify-store: false` skips the call). Copy
`lib/sql/rate_limit.sql` of this package
(`package:spring_boot_starter_supabase/sql/rate_limit.sql`) into
`supabase/migrations/`:

```sql
-- The rate limiter's buckets in a Supabase project, for the store that
-- calls a database function through the REST API (SupabaseRateLimitStore,
-- spring.web.rate-limit.store: procedure). Copy it into the project's
-- migrations (supabase/migrations/<timestamp>_rate_limit.sql). To use
-- other names, rename the table and the function here and set
-- spring.supabase.rate-limit.function.
--
-- One row is one bucket; the times are seconds since 1970. Unlogged: a
-- bucket lost in a crash is a full bucket, and counting writes no WAL.
create unlogged table if not exists public.rate_limit (
  key text primary key,
  tokens double precision not null,
  allowed boolean not null,
  updated_at double precision not null,
  expires_at double precision not null
);
create index if not exists rate_limit_expires_at
  on public.rate_limit (expires_at);

-- Closed to the roles of the REST API's users: row-level security with no
-- policy, and no privilege. Nobody reads or resets a counter but through
-- the function, and that is the service role's.
alter table public.rate_limit enable row level security;
revoke all on table public.rate_limit from public, anon, authenticated;

-- Takes p_permits from the bucket of p_key (capacity p_capacity, filled
-- with p_refill_per_second) when they are there, in one statement: the
-- row is locked from the read to the write, so two calls never both get
-- the last permit. The clock is the database's.
create or replace function public.rate_limit_acquire(
  p_key text,
  p_capacity double precision,
  p_refill_per_second double precision,
  p_permits double precision default 1
)
returns table (allowed boolean, remaining double precision, retry_after_ms bigint)
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_now double precision := extract(epoch from clock_timestamp());
  v_allowed boolean;
  v_tokens double precision;
begin
  if p_key is null
    or coalesce(p_capacity, 0) <= 0
    or coalesce(p_refill_per_second, 0) <= 0
    or coalesce(p_permits, 0) <= 0
  then
    raise exception 'rate_limit_acquire needs a key and a positive capacity, refill and permits'
      using errcode = '22023';
  end if;

  insert into public.rate_limit as b (key, tokens, allowed, updated_at, expires_at)
  values (
    p_key,
    case when p_permits <= p_capacity then p_capacity - p_permits else p_capacity end,
    p_permits <= p_capacity,
    v_now,
    v_now + p_capacity / p_refill_per_second
  )
  on conflict (key) do update set
    tokens = case
      when least(p_capacity, b.tokens + greatest(0, v_now - b.updated_at) * p_refill_per_second) >= p_permits
      then least(p_capacity, b.tokens + greatest(0, v_now - b.updated_at) * p_refill_per_second) - p_permits
      else least(p_capacity, b.tokens + greatest(0, v_now - b.updated_at) * p_refill_per_second)
    end,
    allowed = least(p_capacity, b.tokens + greatest(0, v_now - b.updated_at) * p_refill_per_second) >= p_permits,
    updated_at = greatest(b.updated_at, v_now),
    expires_at = greatest(b.updated_at, v_now) + p_capacity / p_refill_per_second
  returning b.allowed, b.tokens into v_allowed, v_tokens;

  -- Now and then, the buckets that are full again go (a key without a
  -- row has a full bucket).
  if random() < 0.001 then
    delete from public.rate_limit as b where b.expires_at < v_now;
  end if;

  return query select
    v_allowed,
    floor(v_tokens),
    case when v_allowed then 0::bigint
      else ceil((p_permits - v_tokens) / p_refill_per_second * 1000)::bigint
    end;
end;
$$;

revoke all on function public.rate_limit_acquire(text, double precision, double precision, double precision)
  from public, anon, authenticated;
grant execute on function public.rate_limit_acquire(text, double precision, double precision, double precision)
  to service_role;
```

The table is `unlogged` and closed to `anon` and `authenticated` (row-level
security without a policy, no privilege), and so is the function: a client
with the anon key or a user's token can neither call it, nor read a
counter, nor reset one. To use other names, rename them in the migration
and set `spring.supabase.rate-limit.function`.

## Sign-in in a client application: `SupabaseAuth`

`SupabaseAuth` (the bean `supabaseAuth`, also the application's
`LoginSession`) signs users up and in, keeps the session fresh and across
restarts, and signs them out.

```dart
await auth.signInWithPassword(email: email, password: password);
print(auth.user?.email);
await auth.logout();
```

| Method | What it does |
|---|---|
| `signUp(password:, email: / phone:, data:, redirectTo:)` | Creates a user. The signed-in user, or `null` while the address is to be confirmed |
| `signInWithPassword(password:, email: / phone:)` | Email or phone and password |
| `signInWithOtp(email: / phone:, createUser:, redirectTo:)` | Sends a one-time code or a magic link; nobody is signed in yet |
| `verifyOtp(token:, type:, email: / phone:)` | Signs in with the code (`SupabaseOtpType`) |
| `signInWithIdToken(provider:, idToken:, accessToken:, nonce:)` | The ID token of a provider's own SDK (native Google or Apple) |
| `signInWithProvider(provider, scopes:, redirectTo:, queryParameters:)` | Opens the provider's page in the application's `AuthorizationWindow` and exchanges the code (PKCE) |
| `authorizationUrl(provider, …)`, then `completeSignIn(redirect)` | The same for an application that opens the browser itself |
| `exchangeCode(code)` | Exchanges the code of the login that waits |
| `resetPassword(email, redirectTo:)` | Sends the email; `completeSignIn` signs in, `updateUser(password:)` sets the password |
| `updateUser(email:, password:, data:)`, `reloadUser()` | Changes or reads again the signed-in user |
| `refreshSession()`, `accessToken()` | A new pair of tokens now; a token that is not about to expire |
| `restore()` | The session of the last run (it runs by itself at startup) |
| `logout(scope:)` | `local` (default), `global` or `others` (`SupabaseLogoutScope`) |

- **One login.** The signed-in user is Spring Security's: a
  `SupabaseAuthenticationToken` in the `SecurityContextHolder` (its name
  is the user's id, its principal the `SupabaseUser`, its authorities
  `ROLE_<role>` for each string of `app_metadata.roles`), an
  `AuthenticationSuccessEvent` at each login and restore, a
  `LogoutSuccessEvent` at `logout`, and `authenticationChanges` at every
  change.
- **The session** is kept in the application's `SecretStore`
  (`persist-session`; in memory without a store bean) and restored at
  startup. Without a network the user is restored all the same and the
  tokens are refreshed at their next use.
- **Refresh.** `accessToken()` refreshes a token that expires within
  `refresh-margin`; however many callers wait, one request is made. With
  `auto-refresh` a timer does it before the expiry. When Auth refuses the
  refresh token (`SupabaseAuth.sessionEndingCodes`) the user is signed
  out; when Auth cannot be reached the session stays and the call fails.
- **Redirects** go only to `spring.supabase.auth.redirect-urls`, exactly
  as written there: any other `redirectTo` is an `ArgumentError` before a
  request is made. The redirect that comes back must be the address that
  was asked for.
- **PKCE (S256).** Providers and email links use it. The verifier never
  leaves the application; for `authorizationUrl` and the email links it
  waits in the `SecretStore`, so the application may be restarted in
  between. One login waits at a time.
- **Logout** never depends on the network: the user is signed out here
  first, then the session is revoked at Auth.
- **Errors** are Spring Security's `AuthenticationException`s with Auth's
  error code (`SupabaseAuthFailure.errorCode`, `statusCode`):
  `BadCredentialsException` (`invalid_credentials`, `otp_expired`, …),
  `DisabledException` (`email_not_confirmed`, …), `LockedException`
  (`user_banned`), `CredentialsExpiredException`
  (`SupabaseSessionExpiredException`: the refresh token was refused),
  `UsernameNotFoundException`, `SupabaseWeakPasswordException`
  (`reasons`), `AuthenticationServiceException` (a status of 500 and
  above). A `SupabaseAuthErrorTranslator` bean gives an error code of
  your project an exception of its own. No answer at all is a
  `SupabaseUnavailableException`. No token, password or code is ever in a
  message or a log.

`signInWithProvider` needs an `AuthorizationWindow` bean
(`spring_boot_starter_flutter_security` declares one); without it, it
throws a `StateError` that names `authorizationUrl` and `completeSignIn`.

**The admin API.** `SupabaseAuthAdmin` (the bean `supabaseAuthAdmin`)
creates, reads, changes and deletes users as the service role
(`createUser`, `user`, `users`, `updateUser`, `deleteUser`). It belongs
on a server; without `service-role-key` a call fails before any request.
Roles are written there: `appMetadata: {'roles': ['editor']}`.

Not there: anonymous sign-in, multi-factor authentication, linking
identities, SSO (SAML), inviting users and generating links through the
admin API.

## Realtime

`SupabaseRealtime` (the bean `supabaseRealtime`) gives changes of rows,
messages between clients (Broadcast) and who is online (Presence), as
streams over one WebSocket connection: a Phoenix socket of the WebSocket
starter. The connection opens with the first channel that is used and
closes with the last one that is left.

```dart
@RealtimeChannel('room:{id}', presenceKey: '#{authentication.name}')
abstract interface class Room {
  @Broadcast('cursor')
  Stream<Cursor> cursors(String id);

  @Broadcast('cursor')
  Future<void> moveCursor(String id, Cursor cursor);

  @Presence()
  Stream<List<Member>> members(String id);

  @Presence()
  Future<void> join(String id, Member me);

  @PostgresChanges(table: 'messages', filter: 'room_id=eq.{id}')
  Stream<RealtimeRowChange> messages(String id);
}
```

| Method of a `@RealtimeChannel` interface | What it does |
|---|---|
| `@Broadcast('event') Stream<T> name(...)` | The broadcasts of the other clients, each payload read as `T`; one that cannot be read is an error event, and the stream goes on |
| `@Broadcast('event') Future<void> name(..., payload)` | Sends one; `{}` without a payload parameter |
| `@Presence() Stream<List<T>> name(...)` | Everyone present, now and after each change (`RealtimePresence` gives the key and the reference too) |
| `@Presence() Future<void> name(..., state)` | Makes this client present with the state; without a state parameter, ends its presence |
| `@PostgresChanges(table:, schema:, filter:, kind:) Stream<RealtimeRowChange> name(...)` | The changes of the rows of a table |

The channel's name, its `presenceKey` and a filter take `${property}`,
`{parameter}` and SpEL in `#{...}`; each name that comes out is one
channel, joined when first used and left when its last stream is
cancelled and nothing is tracked. A value put into a filter is one value
(quoted when it has a `,`, `(`, `)`, `{`, `}`, `"` or `\`, or is the
word `null`), never a part of the filter; an empty value is refused,
since a filter of Realtime cannot say it.

In code, `realtime.channel(name, private:, self:, ack:, presenceKey:)`
gives a `RealtimeChannelSession` (`postgresChanges`, `broadcast`,
`events`, `send`, `presence`, `track`, `untrack`, `leave`), and
`realtime.postgresChanges(table:, schema:, filter:, kind:)` the changes
of a table on a channel of their own.

- **Changes of rows** need the table in the publication
  `supabase_realtime`, and the user must be allowed to read the rows.
  `oldRecord` has only the primary key unless the table has
  `replica identity full`. With a `filter`, the server sends no delete
  and no update that takes a row out of the filter; deletes are not
  checked against row-level security (they carry only the key).
- **Tokens.** Every channel is joined with the access token of
  `SupabaseCredentials`. A new token of the same user is sent to the
  joined channels without joining again (a refreshed one at the next
  heartbeat). When another user signs in, or the user signs out, the
  channels are joined again with the new token (the anon key for nobody):
  the streams go on, nothing the server still sent for the user before
  arrives, and a message of that moment is missed. A channel acts as the application itself (its
  login, or the anon key): it never takes the token of a server's
  request. A channel asked inside `asServiceRole` is joined as the
  service role.
- **Reconnection.** After a lost connection every channel is joined
  again, what was tracked is tracked again, and the streams go on. When
  the server ends a channel, its streams get a `RealtimeException` and
  are done.
- **In the repositories.** The REST store reports the changes of its
  rows from Realtime, so a repository has `watch…By` and `changes…By`
  methods with entities ([Data](#database-functions-and-changes-of-rows)).

The wire format is `1.0.0` (JSON text). Realtime's binary broadcasts
(`vsn` 2.0.0) are not read. There is no REST fallback for a broadcast:
`send` joins the channel.

## Storage

`StorageTemplate` (the bean `storageTemplate`) reads and writes objects
as the current user, so the policies on `storage.objects` decide what a
call may do.

```dart
await storage.upload('avatars', 'u1/avatar.png', bytes,
    contentType: 'image/png', upsert: true);
final link = await storage.signedUrl('avatars', 'u1/avatar.png');
final settings = await storage.read<Settings>('config', 'app.json');
```

| Method | What it does |
|---|---|
| `upload(bucket, path, content, contentType:, upsert:, cacheControl:)` | Bytes, a `String` (UTF-8) or a `Stream<List<int>>` |
| `download(bucket, path)`, `downloadBytes(bucket, path)` | The bytes as they arrive; the whole object |
| `read<T>(bucket, path)`, `store(bucket, path, value, upsert:)` | JSON through the `ObjectMapper`; `read` gives `null` for no object |
| `publicUrl(bucket, path, download:)` | The address in a public bucket; nothing is asked of Storage |
| `signedUrl(bucket, path, expiresIn:)`, `signedUploadUrl(bucket, path)` | An address that reads, or takes one upload, without a token |
| `list(bucket, prefix:, limit:, offset:, sortBy:, descending:, search:)` | The objects and folders directly under a prefix |
| `delete`, `deleteAll`, `move`, `copy`, `exists`, `info` | |
| `buckets()`, `bucket(id)`, `createBucket`, `updateBucket`, `emptyBucket`, `deleteBucket` | Buckets; with `asServiceRole()` |
| `asServiceRole()` | The same template with every call as the service role |

A declared bucket keeps the paths of a bucket in one place, and its bean
takes AOP like any other (`@PreAuthorize`, `@Cacheable`):

```dart
@StorageBucket('avatars')
abstract interface class Avatars {
  @Upload('#{authentication.name}/avatar.png', upsert: true)
  Future<void> put(Uint8List bytes);

  @Download('{userId}/avatar.png')
  Stream<List<int>> get(String userId);

  @SignedUrl('{userId}/avatar.png', expiresIn: Duration(minutes: 5))
  Future<Uri> link(String userId);

  @PublicUrl('{userId}/avatar.png')
  Uri publicLink(String userId);

  @StorageObject('{userId}/settings.json')
  Future<Settings?> settings(String userId);

  @StorageObject('{userId}/settings.json')
  Future<void> saveSettings(String userId, Settings settings);

  @DeleteObject('{userId}/avatar.png')
  Future<void> remove(String userId);
}
```

| Annotation | The method |
|---|---|
| `@Upload(path, contentType:, upsert:, cacheControl:)` | takes the content (`Uint8List`, `List<int>`, `Stream<List<int>>` or `String`; the parameter the path does not use, or the one marked `@RequestBody()`) and returns `Future<void>` |
| `@Download(path)` | returns `Stream<List<int>>`, `Future<Uint8List>` or `Future<Uint8List?>` (`null` for no object) |
| `@SignedUrl(path, expiresIn:)` | returns `Future<Uri>` or `Future<String>` |
| `@PublicUrl(path, download:)` | returns `Uri` or `String` |
| `@StorageObject(path, upsert:)` | reads JSON when it returns a value, writes it when it takes one and returns `Future<void>` |
| `@DeleteObject(path)` | returns `Future<void>`; nothing there is no error |

**Path rules.** A path takes `${property}` from the configuration,
`{name}` from the method's parameter of that name, and SpEL in `#{...}`
(the parameters as `#name`, `authentication` and `principal` as in
`@PreAuthorize`, beans as `@name`). What a parameter or an expression
gives is one segment of the path: a value with a `/`, a `\`, a control
character, `.`, `..` or nothing in it is refused, so a call never leaves
its folder. `StorageTemplate` checks again: a path with an empty, `.` or
`..` segment is an `ArgumentError`. A wrongly declared interface stops
the start, with every problem of the interface in one message.

**Errors** are `StorageException`s (a `SupabaseException`):
`StorageObjectNotFoundException` (or the caller may not see it),
`StorageObjectAlreadyExistsException`,
`StoragePermissionDeniedException`, `StorageObjectTooLargeException`.

An upload is read whole before it is sent, a stream too. There is no
resumable upload (TUS) and no `Resource` of an object.

## Edge Functions

```dart
@EdgeFunctions()
abstract interface class Functions {
  @EdgeFunction('send-invite')
  Future<InviteResult> sendInvite(@RequestBody() Invite invite);

  @EdgeFunction('stats', method: HttpMethod.get)
  Future<Map<String, Object?>> stats(@RequestParam('from') String from);

  @EdgeFunction('reports/{year}', method: HttpMethod.get)
  Future<String> report(@PathVariable() int year);
}
```

An `@EdgeFunctions` interface is a Feign client of
`<spring.supabase.url>/functions/v1` with the key and the token of
`SupabaseCredentials`: parameters (`@RequestBody`, `@RequestParam`,
`@RequestHeader`, `@PathVariable`), results and errors (`FeignException`)
are Feign's. A method without `@EdgeFunction` stops the start.

What a function may answer:

| The method returns | The answer is |
|---|---|
| `Future<T>` (a class, a `Map`, a `List`), `Future<String>` | JSON, or text |
| `Future<Uint8List>` | a file, read whole |
| `EventStream<T>`, `Stream<T>` | server-sent events, as they arrive |
| `Stream<List<int>>` | the body as it arrives, whatever its content type |
| `Future<ResponseEntity<T>>` | the status, the headers and the body |

```dart
@EdgeFunction('progress', method: HttpMethod.get)
EventStream<Map<String, Object?>> progress();

@EdgeFunction('export', method: HttpMethod.get)
Future<Uint8List> export();

@EdgeFunction('export', method: HttpMethod.get)
Stream<List<int>> exportStream();
```

A request body is read whole before it is sent.

- A function's name takes `${property}` and `{name}` filled by a
  `@PathVariable()` parameter; it takes no SpEL.
- The method is `POST` unless `method:` says otherwise.
- Its settings are `spring.feign.client.config.supabase-functions.*`
  (`@EdgeFunctions(name:)` names another client). The call timeout is the
  client's, else `spring.supabase.functions.timeout`, else
  `spring.supabase.timeout`.
- It never follows a redirect, which could carry the token to another
  host. `spring.supabase.functions.region` is sent as `x-region`.
- Each call is an `Observation` named `supabase.functions`, with the
  function's name.

## Caches

With row-level security one call answers differently per user. A cache
key made of the arguments alone would hand one user's rows to another. So
with this starter every cache key carries who the call was made as
(`anon`, `user:<id>`, `service`), with nothing to write in `@Cacheable`:

```dart
@Cacheable('todos')                      // one entry per caller and list
Future<List<Todo>> open(String listId) => todos.findByListId(listId);

@Cacheable('todos', key: '#listId')      // an explicit key is kept apart per caller too
Future<List<Todo>> again(String listId) => todos.findByListId(listId);
```

- `SupabaseKeyGenerator` (the bean `supabaseKeyGenerator`) is the default
  `KeyGenerator`: who calls, plus the arguments.
- `SupabaseCacheResolver` (the bean `supabaseCacheResolver`) is the
  default `CacheResolver`: an explicit `key:` goes past any key
  generator, so the caches it gives add the caller to such a key. No key
  is scoped twice.
- A cache named in `spring.supabase.cache.shared` has the same entries
  for everyone.
- `clear` (`@CacheEvict(allEntries: true)`) empties a cache for every
  caller.

Both come from the starter's `CachingConfigurer`
(`supabaseCachingConfigurer`), which steps back for a `CachingConfigurer`
of the application; such an application names the generator where it
wants it (`keyGenerator: 'supabaseKeyGenerator'`).

## Tests

A test needs no project: the starter talks through the application's
`HttpTransport` and `WebSocketTransport` beans, and the test starter
has fakes of both (`MockHttpTransport`, `MockWebSocketTransport` in
`package:spring_boot_starter_test/spring_boot_starter_test.dart`).

```dart
final transport = MockHttpTransport();
final properties = SupabaseProperties()
  ..url = 'https://abcd.supabase.co'
  ..anonKey = 'anon-key';
final storage = StorageTemplate(
  http: SupabaseHttp(
    properties: properties,
    transport: transport,
    credentials: DefaultSupabaseCredentials(
      properties: properties,
      authentication: () => null,
    ),
  ),
  mapper: ObjectMapper(),
);

transport
    .when(HttpMethod.post, '/storage/v1/object/avatars/u1/a b.png')
    .respond(200, json: {'Key': 'avatars/u1/a b.png'});
await storage.upload('avatars', 'u1/a b.png', Uint8List.fromList([1, 2, 3]),
    contentType: 'image/png', upsert: true);

final request = transport.requests.single;
expect('${request.url}',
    'https://abcd.supabase.co/storage/v1/object/avatars/u1/a%20b.png');
expect(request.headers['apikey'], 'anon-key');
expect(request.headers['Authorization'], 'Bearer anon-key');
```

The package's own tests have levels, by the tags of its `dart_test.yaml`:

| Level | Tag | What | Needs |
|---|---|---|---|
| 1 | `supabase` (every test file has it) | filters, the Phoenix protocol against a fake server, Storage, Auth and functions against a fake HTTP transport, token checks, path segments, cache keys | nothing |
| 2, 3 | `supabase-docker` | the SQL path; the REST store against a real PostgREST | PostgreSQL (and PostgREST) in containers; skipped without Docker, a failure with `CONTAINERS_REQUIRED=true` |
| 4 | `supabase-stack` | what only the real services answer | the whole of Supabase, given by `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_DB_URL`; skipped without them |

```bash
dart test --exclude-tags "supabase-docker || supabase-stack"   # level 1
dart test --tags supabase-docker                               # levels 2 and 3
dart test --tags supabase-stack                                # level 4
```

The levels run in a pipeline of their own
(`.github/workflows/supabase.yml`), not in the main one: levels 1 to 3 in
the jobs `unit` and `containers`, level 4 (`test/stack_*_test.dart`, the
Supabase CLI's configuration in `test/stack/`) in the job `stack`, against
the Supabase CLI's local stack, and in `hosted`, against a hosted project
when its address and keys are in the repository's secrets.

## An example

[`example/supabase`](https://github.com/farum-azula/spring_core_dart/tree/main/example/supabase)
is a todo list on one project: a Flutter app (sign-in and sign-up, a live
list from a watched query, an avatar in Storage, an Edge Function) and a
server (the project's tokens as bearer tokens, SQL with transactions as
the caller, a role check, a signed URL), with the project for the
Supabase CLI and tests of both, without a project and against one.

## Not there yet

- **A `SupabaseContainer`** for an application's tests.
- **Streamed uploads** and resumable uploads (TUS): an upload is read
  whole before it is sent.
- **`resource(bucket, path)`**: no `Resource` of an object.
- **`@MappedCollection` on the REST store.**
- **SpEL in `@EdgeFunction` names.**
- **A warning in the build's log** for a key in a Flutter app: the
  warning is at startup only.
- **The data path in the actuator's `info`**, and Realtime channels in
  the task manager.
- **Entities checked against the project's schema** at build time.

## Differences from Supabase's own packages

| `supabase_flutter` | Here |
|---|---|
| `Supabase.initialize(url:, anonKey:)` | `spring.supabase.url`, `spring.supabase.anon-key` |
| `supabase.from('todos').select().eq('done', false)` | a repository method, `findByDone(false)`; there is no query builder |
| `supabase.rpc('name', params: …)` | a repository method with `@Procedure('name')` |
| `supabase.from('todos').stream(primaryKey: ['id'])` | a repository method `watch…By`, a `Stream<List<Todo>>` kept up to date |
| `supabase.auth.signInWithPassword(…)` | `SupabaseAuth.signInWithPassword(…)`; the user is Spring Security's `Authentication` |
| `supabase.auth.onAuthStateChange` | `LoginSession.authenticationChanges`, `AuthenticationSuccessEvent`, `LogoutSuccessEvent` |
| `supabase.storage.from('avatars').upload(…)` | `StorageTemplate`, or a `@StorageBucket` interface |
| `supabase.functions.invoke('name')` | an `@EdgeFunctions` interface (a Feign client) |
| `supabase.channel('room')…subscribe()` | `SupabaseRealtime.channel('room')` or a `@RealtimeChannel` interface: streams, joined while used, no `subscribe()` |
| `AuthException`, `PostgrestException`, `StorageException` | Spring Security's `AuthenticationException`s, the data starter's `DataAccessException`s, `StorageException` |

- **Its own client**: none of Supabase's packages; the HTTP transport,
  the WebSocket transport, the JSON mapper, the logs and the observations
  are the application's.
- **One session**: Spring Security's. `@PreAuthorize`, the security
  context and every call to Supabase see the same user.
- **On a server too**: a request's bearer token is passed on to the
  database, and the resource server's settings come with the starter.
- **Cache keys carry the caller**, by default.
