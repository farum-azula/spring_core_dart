# Level 4: the tests against the whole of Supabase

This directory is a Supabase CLI project: what the tests
`../stack_*_test.dart` (tag `supabase-stack`) need in a project.

| File | What |
|---|---|
| `supabase/config.toml` | Auth (sign-up without confirmation, the redirect list, refresh tokens refused at once after use, mail templates), the functions, no Studio |
| `supabase/migrations/*.sql` | `todos`, `notes`, `messages` with row-level security and written-out grants, `close_all`, the publication `supabase_realtime`, the bucket `avatars` with its policies |
| `supabase/functions/` | `send-invite`, `stats`, `reports` (the `Functions` interface of the test application), `events` (server-sent events), `download` (a file) |
| `supabase/templates/mail.html` | A mail a test can read: the code, the token hash and the link |

Written for the **Supabase CLI 3.1.0** (Auth v2.197.0, Realtime v2.154.0,
Storage v1.90.1, PostgREST v16.5, Edge Runtime v1.78.1, Mailpit v1.31.3,
PostgreSQL 17). Without a stack every test is skipped
(`SUPABASE_URL is not set`).

## On a laptop

Docker must run. From this directory (`spring_boot_starter_supabase/test/stack`):

```bash
# 0. The functions written in Dart (spring_boot_starter_edge), compiled
#    to supabase/functions: config.toml declares them, and the CLI wants
#    every declared function there at start. They are not in git.
(cd ../../../tool/edge_checks && dart run spring_boot_starter_edge:build \
  --platform supabase --name edge-test \
  --output ../../spring_boot_starter_supabase/test/stack/supabase/functions/edge-test)
(cd ../../../tool/edge_checks && dart run spring_boot_starter_edge:build \
  --platform supabase --name edge-test-wasm --target wasm \
  --output ../../spring_boot_starter_supabase/test/stack/supabase/functions/edge-test-wasm)
(cd ../../../example/supabase/function && dart run spring_boot_starter_edge:build \
  --platform supabase --name api \
  --output ../../../spring_boot_starter_supabase/test/stack/supabase/functions/api)

# 1. The stack, without what the tests do not use.
supabase start -x studio,imgproxy,vector,logflare,postgres-meta,supavisor

# 2. Where it is, under the names the tests read.
set -a
eval "$(supabase status -o env \
  --override-name api.url=SUPABASE_URL \
  --override-name auth.anon_key=SUPABASE_ANON_KEY \
  --override-name auth.service_role_key=SUPABASE_SERVICE_ROLE_KEY \
  --override-name auth.jwt_secret=SUPABASE_JWT_SECRET \
  --override-name db.url=SUPABASE_DB_URL \
  --override-name mailpit.url=SUPABASE_MAILPIT_URL \
  | grep '^SUPABASE_')"
set +a

# 3. The tests, from the package (one file at a time: the machine stays cool).
cd ../..
dart test -j 1 --tags supabase-stack --reporter expanded
```

```bash
supabase db reset          # the database again from the migration (users and rows gone)
supabase stop --no-backup  # stop, and forget the data
```

After a change of `config.toml` or of a mail template: `supabase stop`,
then `supabase start` again. The functions are served from
`supabase/functions` as they are, with hot reload.

## The variables

| Variable | From | For |
|---|---|---|
| `SUPABASE_URL` | `api.url` | the project; without it everything is skipped |
| `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` | `auth.anon_key`, `auth.service_role_key` | required with the address (the tests fail without them) |
| `SUPABASE_DB_URL` | `db.url` | the SQL path; its tests are skipped without it |
| `SUPABASE_MAILPIT_URL` | `mailpit.url` | the mails of Auth (codes, magic links, password reset, the redirect list); skipped without it |
| `SUPABASE_JWT_SECRET` | `auth.jwt_secret` | only for a stack that signs its users' tokens with HS256 |
| `SUPABASE_SITE_URL` | default `http://127.0.0.1:3000` | `site_url` of the project |
| `SUPABASE_REDIRECT_URL` | default `com.example.stack://login` | the address of the project's redirect list |
| `SUPABASE_REFRESH_TOKEN_REUSE_INTERVAL` | default `0` locally, `10` elsewhere | seconds a used refresh token is still taken |

## Signing keys

Without `auth.signing_keys_path` the CLI gives Auth its default ES256 key:
the users' tokens are signed with ES256 and the public key is at
`/auth/v1/.well-known/jwks.json`, which is what a server with the
starter's defaults checks them with. The first test of "the keys of the
tokens" prints what the stack really does (the algorithm, whether there is
a `kid`, the key set). For a key of your own:

```bash
supabase gen signing-key --algorithm ES256   # one JWK; put it into a JSON list
# supabase/signing_keys.json: [ { ...the key... } ]   (never into git)
# supabase/config.toml, [auth]: signing_keys_path = "./signing_keys.json"
supabase stop && supabase start
```

Should a stack sign with HS256 (an older CLI), the same test goes through
`spring.supabase.auth.jwt-secret` with `SUPABASE_JWT_SECRET`.

## A hosted project

The same tests, without the mail catcher (those cases are skipped). Once,
from this directory:

```bash
supabase link --project-ref <ref>
supabase db push                 # the migration
supabase functions deploy        # the five functions (verify_jwt as in config.toml)
```

In the project's dashboard: Auth without email confirmation, the redirect
URL `com.example.stack://login` in the list (or `SUPABASE_REDIRECT_URL`),
the site URL in `SUPABASE_SITE_URL`. Then `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (the JWT keys, not the
`sb_...` ones) and `SUPABASE_DB_URL` (the direct connection or the session
pooler, not port 6543), and the `dart test` line above. The tests make
their own users, rows and objects under random names and remove them.

In CI: the job `hosted` of `.github/workflows/supabase.yml`, nightly and by
hand, with the secrets `SUPABASE_STACK_URL`, `SUPABASE_STACK_ANON_KEY`,
`SUPABASE_STACK_SERVICE_ROLE_KEY`, `SUPABASE_STACK_DB_URL`
(`SUPABASE_STACK_JWT_SECRET` when needed); without them it does nothing.

## By hand: events and files through a declared interface

The test application declares no function that answers a stream of events
or bytes (it would need the generator), so the suite reads `events` and
`download` through `SupabaseHttp`. To check the declared way, add to an
application of your own and call it against the stack:

```dart
@EdgeFunctions()
abstract interface class Streams {
  @EdgeFunction('events', method: HttpMethod.get)
  EventStream<Map<String, Object?>> events();   // three events: {n: 1..3, user: <id>}

  @EdgeFunction('download', method: HttpMethod.get)
  Future<Uint8List> download();                 // 4096 bytes, byte i is i % 251
}
```
