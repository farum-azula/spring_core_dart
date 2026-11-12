---
title: "The packages an application lists — Spring for Dart"
description: "Which packages of the family go into an application's pubspec.yaml, what each one brings and re-exports, and what it does not."
slug: /docs/packages
section: Getting started
order: 2
keywords: [pubspec, dependencies, starters, re-export, depend_on_referenced_packages, spring_boot_starter_web, spring_boot_starter_flutter]
---

# The packages an application lists

An application lists the starters it uses, and nothing they bring. A
starter depends on the packages it is built on and re-exports the ones you
write code against, so one import of the starter gives you its feature,
Spring's annotations, `@SpringBootApplication` and the logger. This is how
Spring Boot's starters work too: `spring-boot-starter-web` brings
`spring-boot-starter`, logging and Spring MVC.

```yaml
# A server with a REST API: the web starter alone.
dependencies:
  spring_boot_starter_web: ^0.7.4

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.7.4
  spring_boot_starter_test: ^0.7.4
  test: ^1.33.0
```

```dart
// bin/main.dart
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

import 'spring_gen/main.spring.dart';  // generated: runApplication

@SpringBootApplication()               // spring_boot_dart, through the starter
void main(List<String> args) => runApplication(args);
```

```dart
// lib/src/hello_controller.dart: one import for all of it.
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@RestController()                      // the web starter
class HelloController {
  HelloController(@Value(r'${greeting:Hello}') this.greeting); // spring_core_dart

  final String greeting;

  @GetMapping('/hello')
  String hello() => greeting;
}
```

## The rule

1. **List every starter whose feature your code uses**, even when another
   starter brings it. The security starter brings the web starter, but a
   server with controllers lists both: what a starter depends on is its own
   business and may change between versions.
2. **Never list a package only because a starter brings it.**
   `spring_core_dart`, `spring_boot_dart`, `spring_web_dart` and
   `spring_boot_starter_logging` come with every starter that needs them.
3. **List a library your code imports that none of your starters
   re-exports.** The table below shows which those are. With the starters
   that is rare: the libraries of one platform (`io.dart`, `browser.dart`)
   are the usual case, and the design library of a Flutter app
   (`material_ui` next to `spring_boot_starter_flutter_material`,
   `cupertino_ui` next to `spring_boot_starter_flutter_cupertino`).
4. **Tests take `spring_boot_starter_test`**, as a dev dependency. It
   re-exports `spring_boot_dart` and the fake transports
   (`MockHttpTransport`, `MockWebSocketTransport`).

The generated code (`lib/spring_gen/`, `*.spring.dart`) imports whatever
it needs, including packages the application does not list. That is
allowed: they are among the resolved dependencies, and the analyzer skips
generated files. So the generated code never adds a line to
`pubspec.yaml`.

Dart's analyzer checks rule 2 and 3 for you: importing a package that
`pubspec.yaml` does not list is the `depend_on_referenced_packages` lint.
Import the starter instead, and the lint is gone.

## What each package brings

The second column lists the packages a package re-exports whole: import its
main library and their main libraries come with it.

| Package | Re-exports | Notes |
|---|---|---|
| `spring_core_dart` | — | The container: beans, configuration, profiles, events, SpEL, validation, AOP. `jakarta.dart` (`Provider`, `@Resource`, `@Priority`) is a library of its own |
| `spring_web_dart` | — | The HTTP model and clients. It exports the part of `spring_core_dart` its types use (`core.dart`). `io.dart` and `browser.dart` (the platform transports) and `testing.dart` (the fake transports) are libraries of their own |
| `spring_boot_dart` | `spring_core_dart` | `@SpringBootApplication`, auto-configuration |
| `spring_search_dart` | — | Full-text search: `SearchService`, documents from beans and Markdown, analyzers per language. Not on pub.dev yet: a git dependency. Apps import `spring_boot_dart` (or a starter) for the annotations |
| `spring_boot_starter_logging` | `spring_boot_dart`, `spring_core_dart` | The base starter: Spring Boot with log output |
| `spring_boot_starter_cache` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart` | `@Cacheable` and the cache manager |
| `spring_boot_starter_scheduling` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart` | `@Scheduled` |
| `spring_boot_starter_data` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart` | Repositories and SQL databases. `testing.dart` is a library of its own |
| `spring_security_core` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart` | Users, password encoders, method security. `testing.dart` is a library of its own |
| `spring_boot_starter_feign` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | `@FeignClient` |
| `spring_boot_starter_websocket` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | `@WebSocketClient`, `@WebSocketEndpoint` |
| `spring_boot_starter_supabase` | `spring_boot_dart`, `spring_boot_starter_cache`, `spring_boot_starter_data`, `spring_boot_starter_feign`, `spring_boot_starter_logging`, `spring_boot_starter_websocket`, `spring_core_dart`, `spring_security_core`, `spring_web_dart` | Supabase: repositories over its REST API or SQL, `SupabaseAuth`, `StorageTemplate`, `@StorageBucket`, `@EdgeFunctions`, `@RealtimeChannel` |
| `spring_boot_starter_web` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | The server. `io.dart` (the `dart:io` server factory) is a library of its own |
| `spring_boot_starter_edge` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_boot_starter_web`, `spring_core_dart`, `spring_web_dart` | The application as a function: Supabase Edge Functions, Cloudflare Workers, AWS Lambda. `build.dart` (the build, `dart:io`) is a library of its own |
| `spring_boot_actuator` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | The actuator's endpoints, without HTTP |
| `spring_boot_starter_actuator` | `spring_boot_actuator`, `spring_boot_dart`, `spring_boot_starter_logging`, `spring_boot_starter_web`, `spring_core_dart`, `spring_web_dart` | The endpoints over HTTP |
| `spring_boot_starter_oauth2_client` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_security_core`, `spring_web_dart` | OAuth 2.0 and OpenID Connect clients. Not the Feign starter: the access token on Feign calls (`OAuth2AccessTokenInterceptor`) is for apps with Feign clients, which list Feign |
| `spring_boot_starter_security` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_boot_starter_oauth2_client`, `spring_boot_starter_web`, `spring_core_dart`, `spring_security_core`, `spring_web_dart` | The security filter chain. Its `testing.dart` re-exports `spring_security_core`'s, with `user()` and `csrf()` for MockMvc |
| `spring_boot_starter_flutter` | `spring_boot_dart`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | Flutter apps, with no design library: `spring.flutter.app.type`, when not set, is the type of the one design starter listed, else `widgets` (a `WidgetsApp`), and must be set when both are; `spring_web_dart` because the starter's API takes an `HttpTransport` (`RemoteCache`, the theme's network images) |
| `spring_boot_starter_flutter_material` | `spring_boot_dart`, `spring_boot_starter_flutter`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | Material Design: the `MaterialApp` of `spring.flutter.app.type: material`, the themes as `ThemeData`. Not `material_ui`: an app lists it for the widgets it uses |
| `spring_boot_starter_flutter_cupertino` | `spring_boot_dart`, `spring_boot_starter_flutter`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | Cupertino: the `CupertinoApp` of `spring.flutter.app.type: cupertino`, the themes as `CupertinoThemeData`. Not `cupertino_ui`: an app lists it for the widgets it uses |
| `spring_boot_starter_flutter_navigation` | `spring_boot_dart`, `spring_boot_starter_flutter`, `spring_boot_starter_logging`, `spring_core_dart`, `spring_web_dart` | Screens, routes, the browser's addresses |
| `spring_boot_starter_flutter_security` | `spring_boot_dart`, `spring_boot_starter_flutter`, `spring_boot_starter_flutter_navigation`, `spring_boot_starter_logging`, `spring_boot_starter_oauth2_client`, `spring_core_dart`, `spring_security_core`, `spring_web_dart` | The app's login and its secrets. Its `testing.dart` re-exports `spring_security_core`'s (`withMockUser`) |
| `spring_boot_starter_test` | `spring_boot_dart`, `spring_core_dart` | Dev dependency. It also re-exports `spring_web_dart`'s `testing.dart` (the fake transports) |

A test in the repository (`tool/test/docs_packages_test.dart`) checks this
table against the `export` directives of the packages.

## Libraries that come with no starter

Some libraries stay out of every main library on purpose. Import them from
their own package, and list that package:

| Library | What it holds | Why it is separate |
|---|---|---|
| `package:spring_web_dart/io.dart`, `browser.dart` | The transports of one platform: `IoHttpTransport`, `IoWebSocketTransport`, the `fetch` transport | `dart:io` would break the web build, `dart:js_interop` the VM. `platformHttpTransport()` from the main library picks the right one, so most applications never import them |
| `package:spring_boot_starter_web/io.dart` | `IoWebServerFactory`, `IoWebServer` | The same: the main library compiles for the browser |
| `package:spring_core_dart/jakarta.dart` | `Provider<T>`, `@Resource`, `@Priority` | The Jakarta annotations, kept apart from Spring's |
| `package:spring_security_core/testing.dart` | `withMockUser`, `withAuthentication`, `withAnonymousUser` | Test code never goes into a runtime library. An app gets it through its security starter's `testing.dart`: `package:spring_boot_starter_security/testing.dart` (with `user()` and `csrf()` for MockMvc) or `package:spring_boot_starter_flutter_security/testing.dart` |

## Which packages re-export what

The rules the packages follow:

- **Down the stack.** A package re-exports what its own API is built on
  and what its users write code against: `spring_boot_dart` exports
  `spring_core_dart`, the logging starter exports `spring_boot_dart`, every
  starter exports the logging starter.
- **The types of its API.** A package whose public API takes or returns
  another package's types re-exports that package: web, Feign, WebSocket,
  the actuator, the OAuth2 client and the Flutter starter export
  `spring_web_dart` (`HttpRequest`, `ResponseEntity`, `HttpTransport`).
- **Another starter only when its API is built on it.** The security
  starter re-exports the web starter (`HttpSecurity` secures its requests)
  and the OAuth2 client (`oauth2Login()` takes its registrations); the
  Flutter security starter the Flutter and navigation starters (its
  widgets and route guards) and the OAuth2 client; the Material and
  Cupertino starters the Flutter starter (their themes and app widgets
  are its `SpringThemes` and `SpringApplicationWidget`). An optional integration
  does not count: the OAuth2 client works with Feign clients when there
  are some, but does not re-export Feign. An application that writes
  Feign clients lists the Feign starter, whatever else brings it (rule 1),
  so it does not break the day a starter stops using Feign.
- **Test code apart.** Fakes and test helpers live in a `testing.dart`
  library, re-exported by `spring_boot_starter_test` or by the starter's
  own `testing.dart`, never by a main library.
- **One platform apart.** Code for `dart:io` or the browser lives in
  `io.dart` / `browser.dart`, never in a main library.

Two checks keep it so: `tool/test/docs_packages_test.dart` compares the
table above with the `export` directives, and
`tool/check_app_dependencies.dart` writes an application per starter (Dart
and Flutter) that lists that starter alone, uses what comes with it, and
must pass `analyze --fatal-infos` and its tests.
