# Generated code: speed, size, platforms

A release of its own (the owner's decision, November 2026), after the data
starter: make the code the generator writes faster and smaller on every
platform, and let the Dart compilers drop what an application never runs.
The generator already writes only what runs (no proxy for a bean nothing
advises, repositories compiled, introspection only of the parts a class is
used for); this release is about *how* that code is written, and about
writing it in pieces so a change regenerates only what depends on it.

Measure first, then change, then measure again: every item below is kept
only if the numbers show it.

## Baseline (November 2026, release builds)

| Artifact | Size |
|---|---|
| Server guide, `dart compile exe` | 13.7 MB (AOT snapshot 9.1 MB; ~5–6 MB is the Dart runtime) |
| Data starter example with SQLite inside, `dart build cli` | 9.9 MB |
| Flutter guide, macOS `.app` | 52 MB; Dart code (`App.framework`) 20.8 MB, of which `package:flutter` 3.2 MB, `dart:*` 2.1 MB, the 12 `spring_*` packages 2.0 MB |
| Flutter guide, web `main.dart.js` | 4.4 MB (1.3 MB gzip) |
| Generated example of the data starter | 9008 → 4121 (proxies pruned) → 1795 lines (repositories compiled, entity descriptions) |

To add before starting: cold start of the Flutter guide (macOS, Android,
web: time to first frame), server start time, the cost of one controller
call and of one call through an AOP proxy (a micro benchmark), an Android
arm64 APK with `--analyze-size`.

## Everywhere

1. **No `Function.apply` in generated code.** Controller handlers are
   called as `Function.apply(bean.recentLogs, arguments)` on every request
   (66 places in the server guide, 20 in the Flutter guide): a dynamic call
   the compiler cannot inline, type or tree-shake, and slow on the web.
   The generator knows the signature: write the direct call
   (`bean.recentLogs(level: a[0] as String, limit: a[1] as int)`), as the
   AOP proxies already do. The same for `BeanMethod.invoke/invokeNamed`
   and `BeanConstructor.create` everywhere they are generated.
2. **Direct AOP when the chain is known.** A proxy builds an argument list
   and a closure per call and goes through the generic `ProxyInvoker`, so
   that advisors added at run time still apply. When the build knows the
   whole chain (`@Transactional`, `@Cacheable`, `@Validated`,
   `@PreAuthorize`, an aspect of the application), write it directly
   ("open the transaction, call the method"), Micronaut's compile-time
   AOP; keep the generic path for advisors added at run time. Fewer
   allocations per call on a busy server.
3. **Conditions decided by the build** (Spring AOT's idea). Conditional
   beans (25 in the server guide) are decided at startup, so the code of
   every variant stays in the binary. Conditions on the application's
   dependencies (`@ConditionalOnClass`-like) can be decided by the build:
   a bean that can never exist is not written, and the compiler drops its
   code. Conditions on properties only in an explicit "frozen" mode
   (environment variables and arguments override properties at run
   time; Spring AOT has the same limit).
4. **Bean order computed by the build.** The creation order of the beans
   (the dependency graph) worked out at build time instead of at startup:
   a faster cold start, mostly for Flutter.
5. **Types the compiler can follow.** No `dynamic`, as few `Object?`
   lists and casts as possible in generated code, no maps keyed by `Type`
   on hot paths, no `runtimeType.toString()` (it keeps class names and
   hurts minification): the compilers' type-flow analysis then inlines,
   devirtualizes and tree-shakes more.
6. **Smaller generated descriptions** (code size, mostly on the web):
   - an entity property in one line for the common case (a mutable field
     the constructor takes) instead of named `parameter: true,
     writable: true` flags, which the formatter spreads over 5–6 lines
     (the example's entity descriptions: ~488 → ~250 lines);
   - `PartTree.and(name, [Part('title'), Part('year')])` for a derived
     query without `Or`, instead of `[OrPart([...])]`.
7. **`@pragma` where it pays:**
   - `vm:isolate-unsendable` on objects that must not cross isolates
     (SQLite connections, the application context, transactions): a
     clear error instead of odd behaviour now that SQLite has a worker
     isolate;
   - `vm:platform-const` on the starters' own platform getters (the
     Flutter starter's database directory): each platform's binary drops
     the other platforms' branches;
   - `vm:never-inline` on cold paths (building long error messages) in
     hot code.
   Not used: `vm:prefer-inline` on generated forwarders (AOT inlines
   small methods anyway), `vm:entry-point` (it disables tree shaking;
   the whole point of generation is not to need it), the
   `vm:unsafe:*` pragmas, `dart2js:as:trust` (a wrong type would go on
   silently). `vm:deeply-immutable` (sharing metadata between isolates
   without copies) needs no list fields; it matters only with the server
   isolate pool (later).

## Incremental output per library

(Moved here from [spring_core_dart.md](spring_core_dart.md).) Today one
`@ComponentScan` / `@SpringBootApplication` root produces one
`<name>.spring.dart` with everything under it, so changing one class (a
Feign client, say) re-runs the whole scan and rewrites the whole file; on a
large project each change costs seconds.

Plan: split the work like source_gen's `SharedPartBuilder` +
`CombiningBuilder`:

- a per-library step writes a small intermediate output for each library
  with annotations (its bean definitions, proxies, repositories, entity
  descriptions, metadata), depending only on that library and the types it
  uses;
- the root step only combines the per-library pieces (imports and module
  lists) into `<name>.spring.dart`, cheap and with no analysis of unchanged
  libraries;
- optionally, one generated file per starter / feature folder
  (`feign.spring.dart`, `data.spring.dart`, ...) next to the root one, so a
  change in the Feign clients rewrites only the Feign file.

Goal: editing one class regenerates only what depends on it; build_runner's
own invalidation then does the rest. It goes with the items above: the
decisions that need the whole application (which beans an advisor can
match, conditions decided by the build, bean order, introspection needs
merged from every use) stay in the root step, and the per-library pieces
must not depend on them, or a change anywhere rewrites everything again.

## Per platform

One generated file for every platform: branches on compile-time
constants (`kIsWeb`, `bool.fromEnvironment('dart.library.js_interop')`,
`dart.tool.dart2wasm`) and conditional imports, and each compiler keeps
only its own branch.

- **Web (dart2js, dart2wasm): size first** (the code is downloaded on
  every visit).
  - Deferred loading: `@Lazy` beans and the modules only they use (an
    admin area, heavy auto-configurations) behind `deferred as` imports
    the generator writes, loaded on first use; a smaller first bundle.
  - Where measurements show it: table-driven code (compact const data
    and one shared function) on the web, specialized functions on native
    platforms, through the compile-time branches above.
  - `int` is a JavaScript number in dart2js (53 bits): generated casts
    and checks must keep the same behaviour on every compiler.
  - No isolates: the SQLite worker isolate does not apply; the web build
    of SQLite (WASM) is its own branch (data starter, later).
- **Mobile and desktop: cold start.** Items 3 and 4; deferred components
  on Android (Flutter's equivalent of deferred loading) for large apps.
- **Server: throughput.** Items 1 and 2.

## Documentation of the generation

`docs/codegen.md`: one section per kind of generated code (beans and
`@Bean` methods, `@ConfigurationProperties`, AOP proxies and their
pruning, interface proxies (Feign, WebSocket clients), data repositories
and `PartTree`, entities and `@Query` DTOs, `@Query` checks and compiled
SpEL, introspection by use, controllers and WebSocket endpoints,
`@Scheduled` and event listeners, Flutter widgets, `@Log`, resources and
dart-defines, glue code (sqlite3, web + data), the test builder
(`@SpringBootTest`, `@DataTest`)): what in the source triggers it, what is
written (a short "source → generated" example), which runtime type uses
it, which mistakes the build catches. Written with this release, so it
describes the optimized output.
