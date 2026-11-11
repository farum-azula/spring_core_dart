# The generator, one module per starter (planned, as soon as possible)

The owner, November 2026: to be done as soon as possible, before any new
starter (Supabase first) adds to the generator.

## Why

For an application the generator already behaves per starter: each
builder switches itself off without its starter or its settings
(`spring_flutter_keys` and `spring_flutter_page_loader` without
`spring_boot_starter_flutter`, `spring_search_index` without
`spring_search_dart`, SEO, deep links, prefetch and JSON Schemas without
their properties), and the data, web and Flutter code of the main builder
only acts on the annotations it finds. Nothing of the generator ships in
an application (a dev dependency); only what it writes does.

Its code is not organised that way:

- the 70 files of `lib/src/` sit in one folder: the core (beans, AOP,
  properties, SpEL), data (`repository_*`, `query_*`, `entity_*`,
  `data_schema`, `sql_lexer`, `schema_sources`), web, security and
  Flutter (`flutter_scanning`, `navigation_*`, `theme_*`, `typed_*_keys`,
  `web_page_*`, `seo_builder`, `deep_links_builder`) mixed;
- data, web, security and Flutter are wired into the core by direct calls
  (`bean_scanner.dart` 5,500 lines, `module_emitter.dart` 3,900,
  `bean_model.dart` 3,600, `spring_builder.dart` 2,300): a new starter
  means editing those files;
- one test suite, `spring_builder_test`, of about 33 minutes; CI cannot
  run only what a change touched.

## The shape

- **One published package, as now**: an application still lists one
  generator. No generator package per starter (each would have to be
  listed by the application and released with the others, and a runtime
  starter cannot bring its generator without putting the analyzer into the
  application's dependencies).
- **A folder per starter** under `lib/src/`: `core/`, `data/`, `web/`,
  `security/`, `flutter/`, `navigation/`, `search/`, `json_schemas/`,
  `test/`, later `supabase/` if it needs anything (the plan is that it
  needs nothing: its declared clients are `@InterfaceProxy` annotations,
  its store a `DataStore` at run time).
- **One interface for a starter's part of the application's module**
  (name to settle, for example `StarterGeneration`): the annotations it
  reads, what it adds to the bean module (definitions, introspections,
  proxies, resources), its build checks and its metadata. The core asks
  every registered part in turn (a chain of responsibility, as
  `docs/style.md` asks); built-in parts use the same interface a future
  one would.
- **A part runs only when the application depends on its starter**
  (read from the package config), so an application with the WebSocket
  starter alone runs none of the data, Flutter, SEO or search code.
- **Tests per part**: the big suite split along the folders; CI runs the
  parts a change touched (the `changes` job's filters), and the core's
  tests on every change of the core.
- **The builders of `build.yaml`** stay as they are for applications
  (same names, same outputs); new features come as builders of their own
  part, switched on by their starter or a property.

## How

1. The interface and the switch by dependency, with the core unchanged in
   behaviour.
2. Move one starter at a time, no change of behaviour: search and
   prefetch, JSON Schemas, Flutter, navigation, test, then the largest,
   data and web, then security. The generated code of every example and
   package must stay byte for byte the same (CI's "Generated code is up to
   date" checks it); a move that changes one byte is a bug of the move.
3. Split the tests and the CI filters along the parts.
4. Measure before and after: the time of `build_runner build` per builder
   on the server guide, the Flutter guide and the site, and the time of
   the generator's test suites in CI.

## Done when

- Every file of `lib/src/` is in the folder of its starter or of the
  core, and the core imports no starter's folder.
- Adding a starter's part means a new folder and one registration, no
  edit of the core.
- The generated code of the repository did not change.
- The generator's CI time per change is that of the parts it touched.
