# The generator, one module per starter (in progress, November 2026)

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

## Progress (17 November 2026, uncommitted)

- Done: every file of `lib/src/` in the folder of its starter or of the
  core (`core/`, `data/`, `flutter/`, `navigation/`, `signals/`,
  `search/`, `json_schemas/`, `test/`); the interface,
  `StarterGeneration` (`core/starter_generation.dart`): scan hooks per
  class and mixin, a check after the scan, the module's parts, emission
  slots at the places the code was written before, the metadata, a model
  of its own in the module, the switch by dependency; the built-in parts
  listed once in `lib/src/starters.dart`; Flutter, navigation and signals
  moved into parts; the build-time reading of the configuration moved
  from the web dev config into `core/build_environment.dart`; data moved
  into two parts (`DataMetadataGeneration` first, `DataGeneration` last,
  so the metadata and the beans keep their order), with the interface's
  hooks it needed (`prepareModule`, `describeClass`, `claimClass`,
  `initialValueClasses`, `classes`, `beanCreation` with an open
  `StarterCreation`, `leadingDeclarations`). The core imports nothing of
  `flutter/`, `navigation/`, `signals/`, `data/`. Generated code byte for
  byte the same in all 40 directories CI checks; the generator's 2,022
  tests pass.
- Then: the web, WebSocket, scheduling, security, cache, JSON Schemas
  and actuator rules moved into parts of their own (`methodNeeds`,
  `expressionUse`, `checkProxy`, `jsonWriters`, `applicationResources`);
  the core names no other starter's URL and imports no starter folder. A
  part has a build key as a module has (`StarterBuild(property,
  whenMissing:)`, `core/build_inclusion.dart`, shared with the modules'):
  `false` runs nothing, `notInRelease` puts what can be guarded under
  `!dart.vm.product` (definitions, statements, introspections,
  resources; classes and declarations are dropped by the compiler when
  nothing uses them). The tests are split by part (`test/<part>/`,
  `test/support/`; 2,031 tests, the same names), and CI runs the tests of
  the parts a change touched (`tool/affected.dart` `test_paths`; a change
  of the core or of the shared files runs all).
- Measured: a clean `build_runner build` takes the same time (server
  guide 17 → 18 s, data starter 23 → 25 s, Flutter guide 20 → 21 s; the
  generator's own phase 1 s, 8 s, 1 s before and after: the time is the
  build script's compilation). The tests per part: core ~53 min, Flutter
  11, data 9, signals 8, navigation 3.5, the others 1-2 or less; a change
  of one part costs its folder instead of ~96 minutes.
- Left: the coverage run of the `quality` job still runs the whole
  generator suite on every push (a decision about the coverage gate).
- Deferred (the owner, 18 November 2026): a CI job per starter's tests
  and per generator part, so each shows its own progress (a matrix from
  the `changes` job, only the affected ones; the core's ~53 minutes in 2-3
  jobs by file); costs a setup per job (SDK, `pub get`, the generator's
  build) and the shards' shared generator build.
- Found by measuring (18 November 2026): `spring.main.startup-checks.enabled`
  is bound at run time (`MainProperties`), +3 KB of wasm in every app
  (`flutter_guide`: 5,062,110 → 5,065,210 bytes) for a key only the build
  reads; declare it for the editors only, without a binding. Done (19
  November 2026): `MainStartupChecksProperties`, abstract, outside the
  scanned `properties/` folder, read by the metadata only;
  `flutter_guide`'s wasm 5,065,477 → 5,064,212 bytes.

## The main modules: what only development needs

The owner, 17 November 2026: in this release too. Of about 38 modules, 19
are decided at build time already (the debug panel and its sections, the
scenes' and signals' tabs, QPS, `@Observed`, the server modules on the
web); the other 19 are the starters' main modules. Searched for beans
only development needs (schema creation, request logging, checks at
start), each a candidate with the code it would take out, split off
behind a build key only where it pays.

Done (17-18 November 2026, uncommitted):
- the checks at start (`transactionValidator`, `dataFailureAnalyzer`,
  `cacheOperationValidator`, `edgeWarnings`; about 650 lines) in modules
  of their own under `spring.main.startup-checks.enabled` (not set: debug
  and profile builds); `methodSecurityValidator` stays in every build, a
  safety net of security;
- the SQL statement logging (`show-sql`, `show-parameters`, `format-sql`)
  under `spring.data.jdbc.show-sql`; the slow-query log stays in the main
  module (`jdbcSlowQueryLogSettings`), production monitoring;
- `ModulePlatform.server` (native without Flutter, `!dart.library.ui`):
  Supabase's admin API (the service-role key) and its server module are
  in no app.

Not done, on purpose (the owner, 17 November 2026):
- the schema step of the data starter (`create`, `validate`; about 1,350
  lines): `validate` is the default and SQLite on a phone creates its
  tables in production, so it could only leave a build whose
  configuration says `schema: none`, which needs a build condition by a
  property's value read from every profile's file; later;
- the in-memory store: the build cannot know an app will have a database
  (its address often comes at start); at most an opt-out key, later.

Found on the way: `dart compile js` / `wasm` define no `dart.vm.product`,
so a deployed edge function keeps the `notInRelease` modules unless their
key is `false` (Flutter's release builds and AOT drop them).

## Next: the core by concern, introspection on its own (the owner, 19 November 2026)

Mostly a matter of structure, for the next release; found while
discussing equality through introspection, where "bean" in the
introspection's names confused us more than once.

- **The core by concern**, as `spring_core_dart/lib/src` is laid out:
  `core/beans/`, `core/aop/`, `core/introspection/` (with JSON and
  validation), `core/properties/`, `core/spel/`, `core/metadata/`,
  `core/build/` (the builder, the build-time configuration, the build
  keys). First the files moved (the generated code byte for byte the
  same), then the code split.
- **Introspection on its own:** its own scanner, model and emitter in
  `core/introspection/`. The bean scanner and the packages' parts (web,
  WebSocket, data) no longer build descriptions; they tell introspection
  what a class needs (`toJson` for a controller's result, a constructor
  for a `@RequestBody`, a method a SpEL expression calls) through a small
  internal interface. One pass over the classes may stay; the roles are
  apart.
- **Its own generated file:** `lib/spring_gen/<library>.spring.introspection.dart`,
  a library with the list of descriptions (`$appIntrospections`), which
  the module imports and hands to the context at start as today; a second
  output of the main builder in `build.yaml`. A unit test can then
  register the descriptions without starting a context, and the module's
  file holds beans only (the server guide's is about 5,000 lines today,
  most of them descriptions).
- **Names:** `BeanIntrospection`, `BeanIntrospector`, `BeanProperty`,
  `BeanMethod`, `BeanConstructor`, `BeanParameter` become `Introspection`,
  `Introspector`, `IntrospectedProperty`, `IntrospectedMethod`,
  `IntrospectedConstructor`, `IntrospectedParameter` (named from
  `@Introspected`, not from beans; "bean" stays the container's), the old
  names removed (pre-1.0: no deprecated aliases, the owner, 20 November
  2026). `BeanWrapper` stays, Spring's own name.
- **The parts are a package's, not a starter's:** `StarterGeneration`
  becomes `PackageGeneration` (`starters.dart` → `packages.dart`,
  `StarterBuild` → `PackageBuild`): several parts belong to libraries
  (`spring_web_dart`, `spring_security_core`, `spring_boot_actuator`), and
  `JsonSchemasGeneration` is `spring_core_dart`'s own, so it moves into the
  core (`core/introspection/`). The halves kept only for the order of the
  output (`ChangeNotifierGeneration`, `DataMetadataGeneration`) join their
  parts again once a slot has an explicit order.
- **The rest of the module's file by stereotype too** (the owner, 19
  November 2026): the AOP proxies in `<library>.spring.proxies.dart`, the binding
  of `@ConfigurationProperties` classes in `<library>.spring.properties.dart`;
  the module's `.spring.dart` keeps the bean definitions and the wiring.
  No change at run time; the files say what they hold.
- **Object methods on introspection, in the core** (the owner, 19 November
  2026; in place of the deferred generated mixins of the branch
  `feat/object-methods`, whose `SecretNames`, `deepEquals`/`deepHash`,
  `copyWith` generation and misuse checks are reused):
  - `@EqualsAndHashCode(include, exclude, callSuper)`,
    `@ToString(include, exclude, includeNames, callSuper, mask, reveal)`
    (secret-looking names masked by `SecretNames`, moved into the core and
    used by the data starter's logs too; `mask` adds fields, `reveal` shows
    one the rule would hide; the value of a masked field is never read);
    the class mixes in `IntrospectedObject` (the framework's, written by
    hand once), whose `==`, `hashCode` and `toString` call the typed
    functions the generator put into the class's description;
  - `@CopyWith(include, exclude, constructor)`: a typed `copyWith` (a
    function type, so `copyWith(x: null)` clears a field without a lint),
    written into `<library>.spring.introspection.dart`; where it is used, one
    import of that file; never an export or a part line;
  - two classes of one name in one library (different folders): the names
    nobody writes by hand (the `copyWith` extension and type) are made
    unique by the generator;
  - no `@Builder` (the owner, 20 November 2026: written once, then removed
    before any release; a constructor with named parameters and `copyWith`
    do its work in Dart);
  - no build key: runtime behaviour, not development code.

Done (19-20 November 2026, uncommitted):
- the core by concern (`core/beans/`, `aop/`, `introspection/`,
  `properties/`, `spel/`, `metadata/`, `builder/`), with introspection's
  own scanner, model and emitter; the bean scan and the packages' parts
  tell it what a class needs (`IntrospectionRequests`);
- `<library>.spring.introspection.dart` (`$<module>Introspections`; a unit test
  registers it with `Introspector.shared.registerAll`),
  `<library>.spring.properties.dart` and `<library>.spring.proxies.dart`; the
  `.spring.dart` keeps the bean definitions and the wiring;
- the names: `Introspection`, `Introspector`, `IntrospectedProperty`,
  `IntrospectedMethod`, `IntrospectedConstructor`, `IntrospectedParameter`
  (the old ones removed, the bean `introspector`; `BeanWrapper` stays);
- the parts are a package's: `PackageGeneration`, `PackageBuild`,
  `PackageCreation`, `packages.dart`; the JSON Schemas are the core's;
- the object methods (`@EqualsAndHashCode`, `@ToString`, `@CopyWith`,
  `IntrospectedObject`, `SecretNames`, `deepEquals`), with the misuse
  checks and the benchmark (`benchmark/object_methods_benchmark.dart`);
- the generated files named `<name>.spring.<kind>.dart`
  (`.spring.introspection.dart`, `.spring.properties.dart`,
  `.spring.proxies.dart`), as the typed keys and the JSON Schema classes;
- what only development needs in `<library>.spring.debug.dart` (the
  fingerprint, `reloadApplication`/`reloadApplicationAsync`), referred to
  under `!dart.vm.product`, so a release build drops it; the
  `hotReload:` callback stays (the isolates of `server.isolates.count`
  start the application through it);
- no "bean" in introspection: the describing functions take `object`,
  `Introspection.type` (was `beanType`);
- readable proxies: `_$invoker`, the invoker's named arguments
  (`proxy`, `target`, `methodIndex`, `arguments`, `original`; measured
  with `benchmark/proxy_invoker_benchmark.dart`), a `///` comment per
  proxy class and member with the advice the build found;
- every generated Dart file formatted as `dart format` formats its
  package (language version, `formatter:` options), its comments wrapped
  to the page, with a test.
