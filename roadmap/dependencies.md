# Dependencies of an application

**Rule:** an application lists the fewest packages possible — the ones it
chooses — and never one that only comes with them.

| The user wants | `dependencies` | `dev_dependencies` |
|---|---|---|
| Spring Boot | `spring_boot_starter_logging` (the base starter: `spring_boot_dart` with logging; `spring_boot_dart` alone has no log output) | `build_runner`, `spring_core_dart_generator` |
| Spring Boot with Feign (or cache, scheduling, ...) | the starter(s) only | `build_runner`, `spring_core_dart_generator` |
| A Flutter app | `spring_boot_starter_flutter` | `build_runner`, `spring_core_dart_generator` |
| Tests | — | `spring_boot_starter_test` (+ `test` / `flutter_test`) |
| Only the container, without Boot | `spring_core_dart` | `build_runner`, `spring_core_dart_generator` |

Like Spring Boot's starters (`spring-boot-starter-web` brings
`spring-boot-starter`, logging and Spring MVC): `spring_core_dart` comes
with `spring_boot_dart`, `spring_web_dart` with Feign, logging with every
starter. The user should not have to know they exist.

## Without the analyzer complaining

Dart's analyzer flags an import of a package the application does not list
(`depend_on_referenced_packages`). So "it comes with it" is not enough: the
code of such a package must be reachable through the package the
application does list.

- **Re-export.** A package re-exports the public libraries of what it
  builds on that its users write code against: `spring_boot_dart` exports
  `spring_core_dart`; each starter exports `spring_boot_starter_logging`
  (and through it `spring_boot_dart`); Feign and WebSocket export
  `spring_web_dart`. One import of the chosen package gives everything.
- **Every library, not only the main one.** A library outside the main one
  (`jakarta.dart`, `io.dart`) gets a re-exporting library of the same name
  in the package the user lists.
- **Test code only in the test starter.** Mocks and test helpers are never
  in a runtime starter: `spring_boot_starter_test` (a dev dependency)
  re-exports them, as `spring-test` holds `MockRestServiceServer`. It
  exports `package:spring_web_dart/testing.dart` (`MockHttpTransport`,
  `MockWebSocketTransport`).
- **Generated code** imports whatever it needs and carries
  `// ignore_for_file: type=lint`, so it never adds a warning; where it can,
  it imports through a library of a direct dependency that exports the
  declaration (`ModuleEmitter._exportingLibrary`).
- **Auto-configurations too.** A starter's `spring_auto_configuration.dart`
  re-exports those of what it builds on, so a test naming
  `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other
  dependency.
- **Checked in CI.** `tool/check_app_dependencies.dart` writes an
  application per starter that lists only that starter and uses what comes
  with it (core annotations, `@SpringBootApplication`, `@Log` and the log
  buffer, the auto-configurations by name, the starter's feature, the
  transport mocks, a test class), then runs the generator,
  `dart analyze --fatal-infos --fatal-warnings` and the tests;
  `tool/test/docs_dependencies_test.dart` checks the docs' install
  snippets.

## Done

- Each starter (cache, feign, scheduling, websocket, flutter) depends on and
  re-exports `spring_boot_starter_logging`, so it is the only dependency.
- Each starter's `spring_auto_configuration.dart` re-exports the
  auto-configurations it builds on (logging's, Boot's).
- `spring_boot_starter_test` re-exports the transport mocks
  (`MockHttpTransport`, `MockWebSocketTransport`); tests need no other
  dependency.
- The docs' setup blocks, the package examples, the guides (`example/`)
  and the project template (`dart_spring_lsp create`) list only the chosen
  packages.

## Gaps

1. **`spring_core_dart/jakarta.dart` through `spring_boot_dart`.** Its
   `Provider<T>`, `@Resource` and `@Priority` are not exported by the main
   library: an application on `spring_boot_dart` alone must list
   `spring_core_dart` to use them. Low priority: the Jakarta annotations
   may be removed altogether ([spring_core_dart.md](spring_core_dart.md),
   "Jakarta annotations"); add `package:spring_boot_dart/jakarta.dart` only
   if they stay.
2. **`spring_web_dart`'s platform libraries.** `io.dart` and `browser.dart`
   (`IoHttpTransport`, `IoWebSocketTransport`, the fetch transport) are not
   re-exported by Feign and WebSocket. Add `io.dart` / `browser.dart` to
   both starters (not into their main library: `dart:io` would break the
   web).
3. **`spring_boot_starter_test`** re-exports `spring_boot_dart` and the
   transport mocks, not the starter it tests: a test of a Feign app imports
   the Feign starter anyway (a dependency the app has), so nothing to add;
   check it in the analyzer test below.
4. **The analyzer test** — done (`tool/check_app_dependencies.dart`, in
   CI). Not yet for the Flutter starter (it needs the Flutter SDK).
5. **`example/server_guide`** lists `spring_core_dart`, `spring_boot_dart`,
   `spring_web_dart`, `spring_security_core` and the logging starter next
   to its starters, and imports them directly. Move its imports to the
   starters it uses and drop the packages that come with them.
