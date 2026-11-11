# Supabase, the Spring way

A todo list on a [Supabase](https://supabase.com) project, written with
[`spring_boot_starter_supabase`](../../spring_boot_starter_supabase/README.md):
a Flutter app, a server and an Edge Function written in Dart, all users
of one project. None holds a rule about who may see what: every call
reaches the project as the signed-in user, and the project's row-level
security decides.

| Folder | What |
|---|---|
| [`supabase/`](supabase) | The project, for the Supabase CLI: the table `todos` with its policy, the database function `close_all`, the bucket `avatars` with its policies, the rate limiter's function; its Edge Function `api` is built from `function/` |
| [`app/`](app) | The Flutter app: sign-in and sign-up, the live list of the user's todos, an avatar in Storage, a button that calls an Edge Function |
| [`function/`](function) | The Edge Function `api`, written in Dart with [`spring_boot_starter_edge`](../../spring_boot_starter_edge/README.md): the same kind of application as the server, compiled to JavaScript for Supabase's Edge Runtime |
| [`server/`](server) | The server: a REST API whose bearer tokens are the project's access tokens, over SQL with transactions, a role check, an Edge Function and a signed URL |

The app and the server do not call each other: each is a client of the
project. A todo the server writes shows up in the app by itself, since the
app's list is live.

## What each part shows

**The app** (`app/lib/src/`): the REST API of the project behind Spring
Data, Auth as Spring Security's login.

| | Where | With |
|---|---|---|
| Sign-in and sign-up with an email and a password | `account/login_page.dart` | `SupabaseAuth` behind the Flutter starter's `LoginForm`; the session is kept and refreshed by the starter |
| The screen follows the signed-in user | `app/home_page.dart` | `PrincipalView`: `SupabaseAuth` sets Spring Security's current user |
| A live list | `todos/todo.dart`, `todos/todo_list.dart` | a repository method, `Stream<List<Todo>> watchByListIdOrderByIdAsc(listId)`: the query runs again after each change Realtime tells |
| Add, tick, delete | `todos/todo_list.dart` | `save` and `deleteById` of the repository (`POST`, `PATCH`, `DELETE` of `/rest/v1/todos`) |
| An avatar | `profile/avatars.dart`, `profile/profile_card.dart` | a `@StorageBucket` interface with `@Upload` and `@Download`, the path `#{authentication.name}/avatar.png` |
| An Edge Function | `profile/functions.dart` | an `@EdgeFunctions` interface (a Feign client), called with the user's token |

**The server** (`server/lib/src/`): SQL over the project's database, the
project's tokens as bearer tokens.

| | Where | With |
|---|---|---|
| The project's access tokens as bearer tokens | `web/security_config.dart`, `application.yml` | `oauth2ResourceServer().jwt()`; the keys, issuer, audience and roles are the starter's defaults |
| A REST API over the todos, as the caller | `todos/` | `spring.supabase.db.url` and `spring.supabase.db.rls: user`: each statement runs with the role `authenticated` and the claims of the caller's token, so `auth.uid()` and the policies apply |
| Two writes, or none | `todos/todo_lists.dart` | `@Transactional` |
| A database function | `todos/todo.dart` | `@Procedure('close_all')` |
| A role | `account/account_controller.dart` | `@PreAuthorize("hasRole('ADMIN')")`, the role from `app_metadata.roles`; the report itself runs inside `SupabaseCredentials.asServiceRole` |
| An Edge Function as the caller | `project/functions.dart` | an `@EdgeFunctions` interface: the function gets the token of the request |
| A signed URL | `project/avatars.dart` | a `@StorageBucket` interface with `@SignedUrl` |

**The function** (`function/lib/src/`): a Spring Boot application behind
`/functions/v1/api`, over the project's REST API.

| | Where | With |
|---|---|---|
| A function instead of a server | `bin/main.dart` | `runFetchApplication`; `dart run bin/main.dart` still starts it as a server |
| The project without configuration | `application.yml` | in a function `spring.supabase.*` are the function's environment (`SUPABASE_URL`, ...) |
| The project's access tokens as bearer tokens | `web/security_config.dart` | the same resource server as the server's; `/health` is open, also to the anon key the Supabase clients send |
| The todos as the caller | `todos/` | a repository over the REST path: the token of the request goes on to the project, whose policy hides other users' rows |
| A database function | `todos/todo.dart` | `@Procedure('close_all')` |
| Ten todos a minute for each user | `todos/todo_controller.dart` | `@RateLimiter('10/1m', key: '#{authentication.name}')`, counted in the project's database (`rate_limit_acquire` of `supabase/migrations`), so every instance shares the count |
| A role | `account/account_controller.dart` | `@PreAuthorize("hasRole('ADMIN')")` |
| What the app and the server call | `project/project_controller.dart` | `POST /send-invite` and `GET /stats`; `@CrossOrigin` answers the pre-flight of the app in a browser |

The project has no function written in TypeScript: `send-invite` and
`stats`, which the app and the server call through their `@EdgeFunctions`
interfaces (`@EdgeFunction('api/send-invite')`,
`@EdgeFunction('api/stats')`), are endpoints of this one.

No transactions there: a function has no sockets, so no
`spring.supabase.db.url`.

No `@Json` column: the project has no `json` column to show it on (see
[the starter's README](../../spring_boot_starter_supabase/README.md#data)).

## The project

Docker must run, and the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started)
(written for 3.1.0) must be installed. From this directory
(`example/supabase`):

```bash
# 0. The function written in Dart, compiled to supabase/functions/api
#    (config.toml declares it, and the CLI wants it there at start).
(cd function && dart run spring_boot_starter_edge:build \
  --platform supabase --name api --output ../supabase/functions/api)

# 1. The stack, without what the example does not use.
supabase start -x studio,imgproxy,vector,logflare,postgres-meta,supavisor

# 2. Where it is, under the names the server and the tests read.
set -a
eval "$(supabase status -o env \
  --override-name api.url=SUPABASE_URL \
  --override-name auth.anon_key=SUPABASE_ANON_KEY \
  --override-name auth.service_role_key=SUPABASE_SERVICE_ROLE_KEY \
  --override-name db.url=SUPABASE_DB_URL \
  | grep '^SUPABASE_')"
set +a
```

```bash
supabase db reset          # the database again from the migration (users and rows gone)
supabase stop --no-backup  # stop, and forget the data
```

The stack takes the CLI's usual ports (54321 for the API, 54322 for the
database), as the stack of the starter's own tests does
(`spring_boot_starter_supabase/test/stack`): one of them at a time. That
one has everything this one has (the function `api` is built into it by
the tests), so the example runs against it too.

Its tokens are signed with the CLI's ES256 key, which the server checks
with the starter's defaults (the public key is read from
`/auth/v1/.well-known/jwks.json`).

## The function

```bash
cd function
dart run build_runner build        # after changing beans
dart run spring_boot_starter_edge:build \
  --platform supabase --name api --output ../supabase/functions/api
```

The stack serves what is in `supabase/functions/api` (hot reload: build
again, call again); `supabase functions deploy api` puts it on a hosted
project. `dart run bin/main.dart` runs the same application as a server on
port 8083, with `SUPABASE_URL`, `SUPABASE_ANON_KEY` and
`SUPABASE_SERVICE_ROLE_KEY` from the environment.

```bash
curl "$SUPABASE_URL/functions/v1/api/health"
curl "$SUPABASE_URL/functions/v1/api/todos?list=home" \
  -H "Authorization: Bearer <a user's access token>"
```

| | |
|---|---|
| `GET /health` | `{status, runtime}`; open to everyone |
| `GET /me` | `{id, roles}` of the caller |
| `GET /todos?list=` | the caller's todos of a list |
| `POST /todos` | `{title, listId}`; 201, or 429 after ten in a minute |
| `POST /todos/close-all?list=` | `{closed: n}` |
| `GET /admin` | 403 without the role `ADMIN` |
| `GET /stats?from=` | who called: `{from, method, user, role, verified, apikey}`; 422 for `from=fail` |
| `POST /send-invite` | `{email}`; `{id: "<the caller's id>|<the address>"}` |

`config.toml` turns the platform's own token check off for it
(`verify_jwt = false`: the application checks the tokens, and `/health`
is open) and, for the local stack only, names the issuer of the tokens
(`[edge_runtime.secrets]`: the functions reach the project at
`http://kong:8000` there, the clients at `http://127.0.0.1:54321`).

## The server

```bash
cd server
dart run bin/main.dart     # port 8082, the variables of step 2
```

Nothing of the project is in the repository: `server/lib/resources/application.yml`
reads `SUPABASE_URL` (the local stack when not set), `SUPABASE_ANON_KEY`,
`SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_DB_URL`, and the start fails
with the name of the one that is missing.

A user's access token is what the app holds after a sign-in. To try the
API without the app, sign up with curl:

```bash
TOKEN=$(curl -s "$SUPABASE_URL/auth/v1/signup" -H "apikey: $SUPABASE_ANON_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"email": "ada@example.com", "password": "correct horse"}' | jq -r .access_token)
api() { curl -s -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' "$@"; echo; }

api localhost:8082/api/me
api localhost:8082/api/todos -d '{"title": "Buy milk", "listId": "home"}'
api localhost:8082/api/todos/pair -d '{"listId": "home", "first": "Flour", "second": "Yeast"}'
api localhost:8082/api/todos/pair -d '{"listId": "home", "first": "Lost", "second": ""}'   # 400, and no "Lost"
api 'localhost:8082/api/todos?list=home'
api -X PUT localhost:8082/api/todos/1/done
api -X POST 'localhost:8082/api/todos/close?list=home'      # {"closed": 2}
api localhost:8082/api/stats                                 # the Edge Function saw the same user
api localhost:8082/api/avatar                                # 404 until the app has uploaded one
api localhost:8082/api/admin/report -i                       # 403: no role
```

| Request | Answer |
|---|---|
| `GET /api/me` | the caller: `id`, `email`, `roles` |
| `GET /api/todos?list=` | the caller's todos of a list |
| `POST /api/todos` `{title, listId}` | 201, the todo |
| `POST /api/todos/pair` `{listId, first, second}` | 201, both; 400 and neither when `second` is empty |
| `PUT /api/todos/{id}/done?value=` | the todo; 404 when it is not the caller's |
| `POST /api/todos/close?list=` | `{closed: n}` (the database function) |
| `DELETE /api/todos/{id}` | 204 |
| `GET /api/admin/report` | `{todos: n}` of every user; 403 without the role `ADMIN` |
| `GET /api/stats?from=` | what `/stats` of the Edge Function `api` answers |
| `GET /api/avatar` | `{url}`, signed for five minutes; 404 without an avatar |

The role `ADMIN` is in `app_metadata.roles` of a user, which only the
project's admin API writes (`SupabaseAuthAdmin.updateUser(id, appMetadata:
{'roles': ['ADMIN']})` on a server, or the dashboard); a new token carries
it after the next sign-in.

## The app

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

The folder has the web target only; `flutter create --platforms=macos,ios,android .`
adds the others (macOS needs the entitlement `com.apple.security.network.client`,
Android cleartext traffic for a project on `http://`; a phone reaches the
stack of a laptop by the laptop's address, not `127.0.0.1`).

`app/lib/resources/application.yml` reads `SUPABASE_URL` (the local stack
when not set) and `SUPABASE_ANON_KEY` from the build (`--dart-define`): a
Flutter app has no environment. The anon key is meant to be public; no
other key belongs in an app, and the starter warns at startup about a
service role key, a database address or a JWT secret that ships in one.

On a device the session is kept in the Keychain or Keystore
(`spring_boot_starter_flutter_security`) and the user is signed in again
at the next start. On the web it is kept in memory: a reload signs the
user out.

## A hosted project

Once, from this directory:

```bash
supabase link --project-ref <ref>
supabase db push                 # the migration
supabase functions deploy        # the two functions (verify_jwt as in config.toml)
```

In the project's dashboard, Auth without email confirmation (with it, a
new user signs in after opening the link of the mail; the app says so).
Then the same two programs with the project's values:

```bash
export SUPABASE_URL=https://<ref>.supabase.co
export SUPABASE_ANON_KEY=...            # the JWT keys of the project, not the sb_... ones
export SUPABASE_SERVICE_ROLE_KEY=...
export SUPABASE_DB_URL=postgresql://postgres:<password>@db.<ref>.supabase.co:5432/postgres
export SUPABASE_DB_SSLMODE=require

(cd server && dart run bin/main.dart)
(cd app && flutter run --dart-define=SUPABASE_URL=$SUPABASE_URL --dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY)
```

`SUPABASE_DB_URL` is the direct connection or the session pooler, not the
transaction pooler (port 6543), which `spring.supabase.db.rls: user`
refuses. A project that still signs its tokens with HS256 also gives the
server its legacy secret: `SPRING_SUPABASE_AUTH_JWT_SECRET=...`.

## Tests

| | Run | Needs |
|---|---|---|
| `server/test/api_test.dart` | `dart test` in `server/` | nothing: the project is a `MockHttpTransport` and a fake database that keeps the statements |
| `server/test/stack_test.dart` (tag `supabase-stack`) | `dart test --tags supabase-stack` in `server/` | a project (the variables of step 2); skipped without `SUPABASE_URL` |
| `function/test/function_test.dart` | `dart test` in `function/` | nothing: the application behind `FetchApplication`, without a platform |
| `function/test/stack_test.dart` (tag `supabase-stack`) | `dart test --tags supabase-stack` in `function/` | a stack: it builds the function into `SUPABASE_FUNCTIONS` (by default the stack of the starter's tests) and calls it through the gateway as two users |
| `app/test/app_test.dart` | `flutter test` in `app/` | nothing: the project is played in memory (`test/support/fake_project.dart`: Auth, the REST API, Realtime, Storage, the function) |
| `app/test/stack_test.dart` (tag `supabase-stack`) | `flutter test --tags supabase-stack` in `app/` | a project; the app's beans without its screen |

The server's stack test starts the server on a free port and calls it
with the tokens of two users it makes: one signs up through
`SupabaseAuth`, as the app does, the other is created with the role
`ADMIN` through `SupabaseAuthAdmin`.

In CI the tests without a project run in the main pipeline, and the
stack tests of the server and of the function in the `stack` job of
`.github/workflows/supabase.yml`, on the stack of the starter's own tests.

## Dependencies

The app lists `spring_boot_starter_flutter_security` and
`spring_boot_starter_supabase`. The server lists the web, the security and
the Supabase starters, and for the SQL path `postgres`: the generator wires
a database driver for an application that lists the driver's package itself
(the data starter comes with the Supabase starter, and the web starter's
answers to data errors are wired for it too). See
[the packages an application lists](../../docs/packages.md).
