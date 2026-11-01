# The release of 0.6.0 (prepared November 2026)

The minor release with the data starter. It is made with the *Release*
workflow on `main` (Actions → Release → Run workflow → `minor`; there is no
release branch, see [roadmap/README.md](README.md) and
`.github/workflows/release.yml`), after the branch `data-starter` is merged.

## What is in it

- **`spring_boot_starter_data`, a new package** ([spring_boot_starter_data.md](spring_boot_starter_data.md)):
  repositories on Spring Data JDBC's model, derived queries and `@Query`
  checked by the build, SQLite and PostgreSQL through the application's own
  driver (`sqlite3`, `postgres`, wired by the generator), `@Transactional`
  with Spring's propagations and isolation levels, `@Version` and `@Lock`,
  `JdbcTemplate` and `JdbcClient`, migrations, `@DataTest`.
- **Containers in tests** in `spring_boot_starter_test`: `@Container`,
  `@ServiceConnection`, `GenericContainer`, `PostgresContainer`,
  `KeycloakContainer`, a Docker client of its own, the reaper.
- **Breaking: renamed properties** named after Java libraries
  (`spring.jackson.*` → `spring.json.*`, `spring.cloud.openfeign.*` →
  `spring.feign.*`, `spring.servlet.multipart.*` → `spring.web.multipart.*`,
  `server.servlet.*` → `server.*`, `logging.logback.rollingpolicy.*` →
  `logging.file.rolling-policy.*`); an old name stops the start and names
  the new one. In the CHANGELOGs of `spring_boot_dart`, the web, Feign,
  OAuth2 client and logging starters.
- **Breaking: generated code** (`spring_core_dart_generator`): a class is
  described only for what the build sees used (`IntrospectionPartError`
  tells how to add `@Introspected()`); regenerate the `*.spring.dart` files.
- **Breaking: logging** (`spring_core_dart`): `info` is the default level
  also without the logging starter.
- **A total request deadline** (an extension of Spring):
  `RequestDeadline` in `spring_web_dart` (a time limit carried in the
  `Zone`, nested ones take the earlier end), `server.request-timeout` in
  the web starter (a 503 when the filters and handler do not answer in
  time; streams and WebSockets exempt) and
  `spring.feign.client.config.<name>.call-timeout` in the Feign starter (the
  total time of a call with its retries, capped by the enclosing request's
  deadline, never retried when it passes). In the CHANGELOGs of the three
  packages and in `docs/configuration.md` (sections 15 and 18).
- The web starter's `HandlerExceptionResolver`; SQLite's location and
  isolate in the Flutter starter; smaller generated code (proxies pruned for
  advisor beans, `annotationTypes` of the cache and Flutter pointcuts).
- Postponed, not in 0.6.0: Redis (indefinitely). Next: the generated-code
  release ([generated_code_performance.md](generated_code_performance.md)),
  then the Supabase starter ([spring_boot_starter_supabase.md](spring_boot_starter_supabase.md)).

## Verified

Checked while preparing the release (November 1, 2026, on the branch):

- Every package's `dart pub publish --dry-run`: 0 warnings, except the data
  starter's one expected warning (its CHANGELOG has `## Unreleased`, and
  the Release workflow turns it into `## 0.6.0`); the two Flutter packages
  show only the hint about `pubspec_overrides.yaml` (CI removes it before
  publishing).
- `dart run tool/version.dart --check` and `tool/check_dependencies.dart`
  (the data starter, `postgres` and `sqlite3` as dev-only exceptions,
  `path_provider` for the Flutter starter).
- `dart run tool/check_app_dependencies.dart data`: an application that
  lists the data starter alone gets its annotations, repositories and
  `@Transactional` (the check has an entry for it now).
- `dart analyze --fatal-infos` on the packages CI analyzes, and
  `dart format`: clean (the Wycheproof test files in progress aside).
- `tool/test` (version, release, publish tools), the documentation example
  tests of `docs/configuration.md`, `dart run tool/release.dart --bump=minor
  --dry-run` (0.6.0, nine commits since `v0.5.0`).
- The data starter's tests without containers and servers (1513, in memory
  and SQLite, the isolate mode included).
- `docs/configuration.md` section 20, `docs/testing.md` sections 19 and 20
  and the data starter's README against the code (every key and default,
  the anchors of every link).

Verified earlier, with its evidence in the repository and in CI (re-run in
CI on `main` before pressing the button):

- **PostgreSQL:** the driver, schema, migrations, locks and the suites that
  memory, SQLite and PostgreSQL share, tagged `postgres`; CI job
  "PostgreSQL (data starter)" on a `postgres:17` service.
- **The transactions against Spring:** `tool/data_reference` (Spring Boot
  4.1, Spring Data JDBC, real `@Transactional` services) and
  `spring_boot_starter_data/test/transaction_matrix` run the same 304
  scenarios on PostgreSQL; CI job "Data compared with Spring Data" compares
  the outcomes (the deliberate differences are listed in the starter's
  README, "Compared with Spring").
- **Containers:** the tests tagged `docker` (the Docker client, containers,
  wait strategies, the reaper, Keycloak and PostgreSQL modules, `@DataTest`
  on a PostgreSQL container); CI job "Containers (Docker)", with
  `CONTAINERS_REQUIRED=true`.
- The generated code of the examples and guides is committed; CI checks it
  is up to date.

The security check of the data starter (the stand, run outside the
repository, November 1, 2026) found six defects, all fixed in the starter
with a regression test each (the data starter's tests: unit, `postgres` and
`docker`; the generator's driver and web glue tests):

- **F1 (high)** driver settings given as environment variables were
  ignored, `sslmode=verify-full` included: now read through the environment.
- **F2** secret values of `save` and derived queries in the trace log (and
  at info with `show-parameters`): the statements carry column names, and
  values without a name are masked at info.
- **F3** a password in the URL's query string logged at info: masked.
- **F4** a sort property with a line break forged log lines and every
  invalid sort was a 500: escaped, `PropertyReferenceException`, a 400.
- **F5** the page offset overflowed 64 bits: `PageRequest.of` refuses it,
  a negative offset is an error. A `Pageable`/`Sort` argument resolver for
  controllers is on the data starter's "later" list.
- **F6** `@Version int? version = 0` counted as new: only `null` is new now.
- Also: a warning when `sslmode=prefer` falls back to plain text, and a
  synchronous `runApplication` with a data source says to use
  `runApplicationAsync`.

In progress, results to add here before the release:

- **Wycheproof test vectors** for the security packages (tests).

## Before pressing the button

1. Merge `data-starter` into `main` and let CI finish green there, the new
   jobs included (`postgres`, `docker`, `data-differential`): the Release
   workflow refuses a commit on which CI failed.
2. Wycheproof finished, its findings fixed or recorded, and its changes in
   the CHANGELOGs of the packages it touches (the security packages have no
   entry for them yet). The data starter's security check is done (above;
   its CHANGELOG has the entries).
3. Read the CHANGELOGs once more; they are written under `## Unreleased`,
   which `tool/release.dart` renames to `## 0.6.0`. Packages without such a
   section get the subjects of the commits that changed their folder (or
   "No changes of its own"); the cache, scheduling, Flutter and
   `spring_web_dart` CHANGELOGs have an entry of their own for this reason.
4. Run the *Release* workflow with `minor`. Its test step runs every
   package's tests from `tool/test_all.dart --packages` without excluding
   tags, so on GitHub's runners (which have Docker) the data starter's
   `postgres` tests start PostgreSQL containers and the `docker` tests run;
   the `differential` tests skip without the Spring jar. If a pulled image
   makes a run flaky, re-run it.

## After the button

- `publish.yml` publishes the packages in dependency order. **The data
  starter is new on pub.dev, and pub.dev lets only a person publish a
  package's first version**: its job is skipped with a warning. From your
  machine, after `dart pub login`:

  ```sh
  git fetch --tags && git checkout v0.6.0
  dart run tool/publish.dart      # publishes what is missing, in order
  ```

  Then enable automated publishing on
  <https://pub.dev/packages/spring_boot_starter_data/admin> (repository
  `farum-azula/spring_core_dart`, tag pattern `v{{version}}`). The packages
  it needs (`spring_boot_dart`, `spring_boot_starter_logging`) are
  published by the workflow first.
- Open the data starter's page on pub.dev: the README's links and images,
  the example, the topics, the score.
- The Flutter packages are published after the others, tested against the
  versions just published (retrying while pub.dev's cache catches up).

## Left open

- The two guides (`example/server_guide`, `example/flutter_guide`) do not
  use the data starter yet; the starter has its own
  [example](../spring_boot_starter_data/example/example.dart).
- `docs/` has no page of its own on data (repositories, transactions,
  migrations): it is in the starter's README, `docs/configuration.md`
  section 20 and `docs/testing.md` section 19 ([docs/ROADMAP.md](../docs/ROADMAP.md)).
