# spring_core_dart

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

Spring for Dart and Flutter: a family of packages that port Spring
Framework and Spring Boot, the Java frameworks, to Dart. You write plain
classes and mark them with annotations such as `@Service()` or
`@GetMapping('/books')`; the framework creates the objects, wires them
together, configures them from `application.properties` or
`application.yml`, and runs the application.

**The problem it solves.** A Dart program of some size ends up with a
`main` that builds every service by hand, in the right order, passing each
one what it needs. Each new constructor parameter means editing `main`
and every test that builds the class. Settings are parsed by hand, and
using a fake payment service in development means an `if` somewhere. With
this family a class declares what it needs in its constructor; the
container builds the whole graph, reads the settings, picks the right
implementation for the active profile (`dev`, `prod`, `test`), and lets a
test swap any piece for a fake.

**Who it is for.** Dart developers writing servers, command-line tools or
Flutter apps with more than a handful of services, and teams who know
Spring in Java and want the same structure, the same annotations and the
same configuration files in Dart. You do not need to know Spring to use
it: every package README explains its features from scratch, and shows
the Java version next to the Dart one for readers who do.

**How it works without reflection.** Flutter, AOT executables and the web
have no runtime reflection (`dart:mirrors`). So the annotations are read
at build time: `spring_core_dart_generator`, a `build_runner` builder,
writes plain Dart code (`*.spring.dart` files) that creates your beans,
routes your requests and applies your aspects. The same application runs
with `dart run`, as an AOT executable, in Flutter and on the web.

Repository: <https://github.com/farum-azula/spring_core_dart>. Full
documentation: [`docs/`](docs/README.md), starting with the
[configuration reference](docs/configuration.md) (every property, YAML
and `.properties` side by side).

**Contents:** [Quick start](#quick-start) ·
[Packages](#packages) · [Installation](#installation) ·
[Editor: Zed](#editor-zed) · [Guide](#guide) ·
[Coming from Spring](#coming-from-spring-java) · [Roadmap](#roadmap) ·
[License](#license) · [Development](#development)

## Quick start

A command-line application with Spring Boot: one service, one group of
settings, a task that runs at start-up, and a test. The full example is
[`spring_boot_dart/example`](spring_boot_dart/example/example.dart).

**1. Dependencies** (`pubspec.yaml`). `spring_boot_starter_logging`
brings `spring_boot_dart` and `spring_core_dart` with it, and prints the
log lines; the generator and the test starter are only needed at build
and test time.

```yaml
dependencies:
  spring_boot_starter_logging: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
  spring_boot_starter_test: ^0.4.2
  test: ^1.25.0
```

**2. The beans** (`lib/greeting.dart`). Everything in `lib/` and in the
directory of `main` is scanned; there is no list of classes to keep up to
date.

```dart
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

// A logger for this file, logging as `greeting`.
const log = SpringLog('greeting');

// The `greeting.*` settings, bound from the config files, environment
// variables and the command line.
@ConfigurationProperties('greeting')
class GreetingProperties {
  String name = 'World';
  int times = 1;
}

// A service. The container creates it and passes the settings in.
@Service()
class Greeter {
  Greeter(this.properties);
  final GreetingProperties properties;

  String greeting() => 'Hello, ${properties.name}!';
}

// Runs once the application has started.
@Component()
class GreetOnStartup implements CommandLineRunner {
  GreetOnStartup(this.greeter, this.properties);
  final Greeter greeter;
  final GreetingProperties properties;

  @override
  void run(List<String> args) {
    for (var i = 0; i < properties.times; i++) {
      log.info(greeter.greeting());
    }
  }
}
```

**3. The settings** (`lib/resources/application.properties`). The
`lib/resources/` folder plays the role of Java's classpath: the generator
embeds its files, so they are found on every platform.

```properties
greeting.name=Ada
greeting.times=2
```

**4. The entry point** (`bin/main.dart`). This is the whole of `main`.

```dart
import 'package:spring_boot_starter_logging/spring_boot_starter_logging.dart';

import 'main.spring.dart'; // written by the generator, next to this file

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
```

**5. Generate and run.** Run the generator again after changing
annotations, or keep `watch` running.

```bash
dart run build_runner build      # or: dart run build_runner watch
dart run bin/main.dart           # logs Hello, Ada! (twice)
dart run bin/main.dart --greeting.name=Grace
GREETING_NAME=Grace dart run bin/main.dart
```

**6. A test** (`test/greeter_test.dart`). `springBootTest` starts the
real application with test settings, and `BeanOverride` replaces a bean
with a fake:

```dart
import 'package:my_app/greeting.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import '../bin/main.spring.dart'; // springApplication

class FakeGreeter implements Greeter {
  @override
  GreetingProperties get properties => GreetingProperties();
  @override
  String greeting() => 'fake';
}

void main() {
  final app = springBootTest(
    springApplication,
    profiles: ['test'],                      // also reads test/resources/application-test.properties
    properties: {'greeting.name': 'Test'},
    overrides: [BeanOverride<Greeter>(FakeGreeter())],
  );

  test('the fake replaces the real greeter', () {
    expect(app.getBean<Greeter>().greeting(), 'fake');
  });

  test('test properties win', () {
    expect(app.getBean<GreetingProperties>().name, 'Test');
  });
}
```

**Where to go next:**

- **A web server:** replace `spring_boot_dart` with
  `spring_boot_starter_web` and write `@RestController` classes: the
  [web starter](spring_boot_starter_web/README.md).
- **A Flutter app:** depend on `spring_boot_starter_flutter` and wrap the
  app in `SpringApplicationWidget`: the
  [Flutter starter](spring_boot_starter_flutter/README.md).
- **Without Spring Boot:** the container alone, started by hand, in the
  [core's quick start](spring_core_dart/README.md#quick-start).
- **A complete application, chapter by chapter:** the
  [server guide](example/server_guide/README.md) and the
  [Flutter guide](example/flutter_guide/README.md) below.

Starters are found automatically. Add a package that has a
`lib/spring_auto_configuration.dart` to `pubspec.yaml`, run
`build_runner` again, and its beans are part of the application. Anyone
can write one: see
[Writing your own starter](spring_boot_dart/README.md#writing-your-own-starter).

## Packages

Every package is published on pub.dev with one version for the whole
family. An application lists only the package it builds on: each one
brings and re-exports the packages below it, so a web server lists
`spring_boot_starter_web` alone (see
[what an application gets](docs/dependencies.md#5-what-an-application-gets)).

| Package | Path | What it is |
|---|---|---|
| `spring_core_dart` | [`spring_core_dart/`](spring_core_dart/README.md) | The core: the container that creates and wires your objects (beans), configuration and profiles, events, messages, resources, type conversion, SpEL (an expression language), validation, JSON and AOP (code that runs around other beans' methods). Depends only on the Dart team's `package:yaml`. |
| `spring_boot_dart` | [`spring_boot_dart/`](spring_boot_dart/README.md) | Starts an application from `@SpringBootApplication` on `main`: reads the config files, creates the container with the beans of your package and of the starters you depend on, binds `@ConfigurationProperties`, runs start-up tasks, and explains a failed start. A separate package that depends only on the core, so it can move to its own repository. |
| `spring_boot_starter_logging` | [`spring_boot_starter_logging/`](spring_boot_starter_logging/README.md) | Where log lines go: the console with patterns, log files with rollover, levels from `logging.*` properties, and an in-memory `LogBuffer` (filters, streams, export) for a log screen in an app. Add the dependency, nothing else. |
| `spring_boot_starter_scheduling` | [`spring_boot_starter_scheduling/`](spring_boot_starter_scheduling/README.md) | `@Scheduled` methods that run at a fixed rate, with a fixed delay or on a cron expression (taken from properties if you like), and a `TaskScheduler` bean; the tasks stop when the application closes. Add the dependency, nothing else. |
| `spring_boot_starter_cache` | [`spring_boot_starter_cache/`](spring_boot_starter_cache/README.md) | Caching of method results with `@Cacheable`, `@CachePut`, `@CacheEvict` and `@Caching` (sync and async methods, keys and conditions in SpEL); an in-memory `CacheManager` with time-to-live and size limits from `spring.cache.*`. |
| `spring_web_dart` | [`spring_web_dart/`](spring_web_dart/README.md) | The HTTP vocabulary shared by servers and clients: the mapping annotations (`@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`, `@RequestBody`, `@RestController`, `@ExceptionHandler`), `ResponseEntity`, `HttpHeaders`, `ProblemDetail`, HTTP and WebSocket client transports (`dart:io`; `fetch` and `WebSocket` on the web), server-sent events as `EventStream<T>`, multipart types (`MultipartFile`, `@RequestPart`), the server-side contracts (`ServerHttpRequest`, `ServerHttpResponse`, `HandlerMapping`, `PathPattern`) and mocks for tests. Applications get it through a starter. |
| `spring_boot_starter_feign` | [`spring_boot_starter_feign/`](spring_boot_starter_feign/README.md) | HTTP clients without HTTP code: an abstract class with `@FeignClient` and mapping annotations becomes an injectable client. JSON through the `ObjectMapper`, interceptors, retries, fallbacks, per-client settings in `spring.cloud.openfeign.client.config.*`. |
| `spring_boot_starter_websocket` | [`spring_boot_starter_websocket/`](spring_boot_starter_websocket/README.md) | WebSocket clients written the same way: an abstract class with `@WebSocketClient`, `@OnMessage` (a `Stream<T>`) and `@SendMessage` methods becomes an injectable socket, with JSON, one shared connection opened on demand, reconnection with backoff and handshake interceptors. Spring has no declarative WebSocket client; this one follows the `@FeignClient` style. Server side, together with the web starter: `@WebSocketEndpoint` beans (`@OnOpen`, `@OnMessage`, `@OnClose`, `@OnError`), Spring's `WebSocketHandler` and `WebSocketConfigurer`, origin checks, and a session registry for broadcasting. |
| `spring_boot_starter_web` | [`spring_boot_starter_web/`](spring_boot_starter_web/README.md) | A web server (Spring MVC): `@RestController` classes with `@GetMapping`, `@PostMapping`, ... served by `dart:io`'s `HttpServer` (behind a replaceable `WebServerFactory`; VM and Flutter mobile and desktop), JSON through the `ObjectMapper`, `@Valid` request bodies, errors as `ProblemDetail` with `@ExceptionHandler` and `@ControllerAdvice`, server-sent events (`EventStream`, `SseEmitter`), file uploads (`@RequestPart`, `MultipartFile`) and downloads (`Resource` with `Range`, byte streams), filters, interceptors, CORS, `server.*` properties and graceful shutdown. `MockMvc` for its tests is in the test starter. |
| `spring_security_core` | [`spring_security_core/`](spring_security_core/README.md) | The core of Spring Security, for servers and Flutter apps alike: who is logged in (`SecurityContextHolder`, one per `Zone`), users (`UserDetailsService`, `InMemoryUserDetailsManager`), password hashing (Argon2 by default, PBKDF2, scrypt, in Spring's formats, with Bouncy Castle's cryptography), `AuthenticationManager`, and method security: `@PreAuthorize`, `@PostAuthorize`, `@Secured`, `@PreFilter`, `@PostFilter` with SpEL, always on and checked at startup. |
| `spring_boot_starter_oauth2_client` | [`spring_boot_starter_oauth2_client/`](spring_boot_starter_oauth2_client/README.md) | Single sign-on with OAuth 2.0 and OpenID Connect from Spring Boot's `spring.security.oauth2.client.*` properties: registrations (Google, GitHub, Facebook, Okta built in; any provider by its issuer), the login of apps in the system browser (authorization code with PKCE, `state`, `nonce` and the ID token checked; `restore` and `logout` with revocation), tokens kept in a `TokenStore` and refreshed once before they expire, client credentials for servers, and the user's token on every Feign call. Pure Dart: the VM, Flutter, the web. |
| `spring_boot_starter_security` | [`spring_boot_starter_security/`](spring_boot_starter_security/README.md) | Security for the web starter, secure by default: the filter chain configured with `HttpSecurity` (request rules on the router's path patterns; a request no rule matches is denied), HTTP Basic, form login, single sign-on with OAuth 2.0 / OpenID Connect providers (`oauth2Login()`, ID tokens checked with the provider's keys), JWT resource servers (RS, PS, ES and HS algorithms, JWK sets, issuer discovery), sessions, CSRF, CORS, security headers and a strict firewall; `user()`, `jwt()` and `csrf()` for `MockMvc`. Compared with Spring Security 7 request by request in [docs/security.md](docs/security.md). |
| `spring_boot_starter_test` | [`spring_boot_starter_test/`](spring_boot_starter_test/README.md) | Tests: `springBootTest` (Spring's `@SpringBootTest`) starts the application, `BeanOverride` (`@MockitoBean`) replaces beans, `ApplicationContextRunner` tests auto-configuration, plus matchers, `captureLogs`, and `MockMvc` and `webEnvironment` (`@LocalServerPort`) for the web starter. Works with `package:test` and `flutter_test`. |
| `spring_boot_starter_flutter` | [`spring_boot_starter_flutter/`](spring_boot_starter_flutter/README.md) | Spring Boot in Flutter apps: `SpringApplicationWidget` starts the application and hands its beans to the widgets (`context.bean<T>()`, getters for `@BuildContextAccess` beans, `SpringStatelessWidget<(...)>`, `SpringStatefulWidget<(...)>`). It brings and exports the core and Boot, so an app depends on it alone. The app's lifecycle pauses and restarts the context, the platform is a profile (`android`, `ios`, `mobile`, `desktop`, `web`, ...), and `context.message` gives texts in the app's locale. |
| `spring_core_dart_generator` | [`spring_core_dart_generator/`](spring_core_dart_generator/README.md) | The `build_runner` builder that reads the annotations and writes the `*.spring.dart` files. A dev dependency of every application. |
| `neon_books_server` | [`example/server_guide/`](example/server_guide/README.md) | **The server guide.** NEON Books, a bookstore's server that uses everything a Dart server can: beans, configuration, a REST API with files and server-sent events, Spring Security (sessions, CSRF, roles, method security, single sign-on with Keycloak: `oauth2Login()` and bearer tokens), WebSocket, events and AOP, cache, scheduling, Feign, validation, logging and tests. Read it chapter by chapter; run it with `dart run bin/main.dart` in its folder. Not published. |
| `neon_books_app` | [`example/flutter_guide/`](example/flutter_guide/README.md) | **The Flutter guide.** The bookstore's app, a client of the server guide: state in beans, themes and texts from properties, assets, Feign clients and a WebSocket with a session, login and roles with Spring Security, single sign-on with Keycloak (the system browser on devices, the server on the web), cache, scheduling, validation, a log screen, widget tests, goldens and end-to-end tests against the server. Run it with `flutter run` in its folder. Not published. |

The core is split into libraries that follow Spring's modules. Import
one, or `package:spring_core_dart/spring_core_dart.dart` for all of them:

| Library | What it holds | Spring counterpart |
|---|---|---|
| `core.dart` | `Environment`, property sources, profiles, `ConversionService`, resources, `AntPathMatcher`, config data (`application.properties` and friends) | `spring-core`, Spring Boot's config data |
| `beans.dart` | `BeanDefinition`, `DefaultListableBeanFactory`, `FactoryBean`, post-processors, scopes, `BeanWrapper`, introspection | `spring-beans` |
| `context.dart` | The annotations, `ApplicationContext`, conditions, events, lifecycle, `MessageSource` | `spring-context` |
| `expression.dart` | SpEL | `spring-expression` |
| `validation.dart` | Constraints, `BeanValidator`, `DataBinder` | `org.springframework.validation` and Bean Validation |
| `aop.dart` | Aspects, advice, pointcut expressions, advisors | `spring-aop` |
| `json.dart` | `ObjectMapper` and its annotations | Jackson's `ObjectMapper` |
| `jakarta.dart` | `Provider<T>` and `@Resource` (names that clash with other libraries, so not exported by default) | JSR-330 and JSR-250 |

## Installation

An application on Spring Boot starts from the snippet of the
[quick start](#quick-start), or from the starter it needs (each package
README has its own snippet). For the core alone:

```yaml
dependencies:
  spring_core_dart: ^0.4.2

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.4.2
```

Versions not yet released can be used from git:
`git: {url: https://github.com/farum-azula/spring_core_dart.git, path: spring_core_dart}`
(and `path: spring_core_dart_generator` for the generator).

The generator has two options for AOP proxies, set in your `build.yaml`.
`aop_proxies` chooses which proxy classes are generated; `aop_prune`
skips the proxies of beans that no pointcut can match (details in the
[generator's README](spring_core_dart_generator/README.md)):

```yaml
targets:
  $default:
    builders:
      spring_core_dart_generator:spring_core_dart:
        options:
          aop_proxies: all   # all (default) | interfaces | none
          aop_prune: true    # all: skip proxies of beans no pointcut matches
```

## Editor: Zed

Use [Zed](https://zed.dev) with the extensions below. For now it is the
only editor with support for the framework: to other editors, Spring
annotations, SpEL, `${...}` placeholders and `.properties` files are
plain Dart strings and text.

| Extension | What it gives |
|---|---|
| [`dart_spring`](extensions/zed/dart_spring/README.md) (this repository) | Spring support as in IntelliJ IDEA: go from an injection point to its beans and from `@Value('${...}')` to the property; SpEL, pointcuts and placeholders highlighted and checked while you type (invalid expressions, unknown pointcuts, a `${key}` that no properties file defines, `'${key}'` written without `r`); the Properties language; snippets |
| [Flutter Tools](https://github.com/farum-azula/zed_editor_extensions/tree/main/flutter-extension) | Dart and Flutter as in VS Code: run and debug on every platform, hot reload on save, DevTools; `build_runner watch`, so the generated code follows your edits |
| [HTTP Client](https://github.com/farum-azula/zed_editor_extensions/tree/main/http-client-extension) | IntelliJ's HTTP client: a request for every `@GetMapping` of a controller or Feign client, run from the gutter |

They are installed as dev extensions:

```sh
git clone https://github.com/farum-azula/zed_editor_extensions.git
cd zed_editor_extensions && ./install.sh   # Flutter Tools and HTTP Client
```

For `dart_spring`: Zed's command palette → `zed: install dev extension`
→ the `extensions/zed/dart_spring` folder of this repository (setup
details in [its README](extensions/zed/dart_spring/README.md#setup)).

The recommended code style (formatting, analysis, how a widget names its
beans) is one file to copy: [docs/style.md](docs/style.md).

## Guide

A tour of what the core offers, one topic per section: what it is, when
you need it, a short example, and where to read more. The full reference
of each topic, with every rule and edge case, is in the
[`spring_core_dart` README](spring_core_dart/README.md#guide); the
starters' features are in their own READMEs (see [Packages](#packages)).
Each section also links to the chapters of the two guides that use it.

### Declaring beans

*In the guides:* [server, 1. The application](example/server_guide/README.md#1-the-application), [app, 2. State in beans](example/flutter_guide/README.md#2-state-in-beans).

A **bean** is an object the container creates, keeps and hands to the
objects that need it. You declare one with an annotation on its class
(`@Component()`, or `@Service()`, `@Repository()`, `@Controller()`,
which say the same with a hint of the role), or with a `@Bean()` method
in a `@Configuration()` class when you need to build the object yourself,
for example an object of another package. A bean is a singleton by
default: one instance, created at startup and shared.

A bean asks for the beans it needs in its constructor. The container
finds them by type, so the class never builds its own dependencies and a
test can pass fakes:

```dart
@Service()
class OrderService {
  OrderService(
    this.repository,                              // the one OrderRepository bean
    this.listeners,                               // every OrderListener bean, ordered
    @Value(r'${orders.limit:100}') this.limit,    // a setting, 100 when not set
  );

  final OrderRepository repository;
  final List<OrderListener> listeners;
  final int limit;
}

@Configuration()
class RandomConfig {
  // Random is not our class (dart:math): build it in a @Bean method.
  @Bean()
  Random random() => Random.secure();
}
```

When several beans fit, `@Primary()`, `@Qualifier('name')` or the
parameter's name choose one. A nullable parameter is optional,
`ObjectProvider<T>` gets a bean later, and `@Lazy()` on a parameter
breaks a cycle. The container checks the whole graph at startup: a
missing or ambiguous bean, a cycle or an unknown placeholder stops the
start with a message naming the bean and the parameter.

More: [declaring beans](spring_core_dart/README.md#declaring-beans),
[injection](spring_core_dart/README.md#injection),
[lifecycle](spring_core_dart/README.md#lifecycle) (`@PostConstruct`,
`@PreDestroy`, start and stop of background work),
[conditions](spring_core_dart/README.md#conditions) (`@Profile`,
`@Conditional`) and [modules](spring_core_dart/README.md#modules)
(`@ComponentScan`, `@Import`, registering beans in code).

### Configuration

*In the guides:* [server, 2. Configuration](example/server_guide/README.md#2-configuration), [app, 1. The application](example/flutter_guide/README.md#1-the-application).

Settings live in `application.properties` or `application.yml` in
`lib/resources/`, with one file per profile on top
(`application-prod.yml`). Environment variables and command-line
arguments override the files, so the same build runs in development and
in production. A bean reads one value with `@Value(r'${key:default}')`
(a raw string: `${...}` is Spring's placeholder, not Dart's
interpolation), or a whole group into a typed class with
`@ConfigurationProperties` (Spring Boot).

```yaml
# lib/resources/application.yml
orders:
  limit: 50
spring:
  profiles:
    active: dev
```

The locations, their order, profiles, imports, placeholders and every
property of the framework are in the
[configuration reference](docs/configuration.md). The core's side
(`Environment`, property sources, `@PropertySource`) is in
[environment and configuration](spring_core_dart/README.md#environment-and-configuration);
binding into classes in
[`@ConfigurationProperties`](spring_boot_dart/README.md#configurationproperties).

### Events

*In the guides:* [server, 6. Events and AOP](example/server_guide/README.md#6-events-and-aop).

An event lets one bean tell others that something happened without
knowing them. The order service publishes `OrderPlaced`; the mailer and
the stock keeper listen. Adding a third listener changes nothing in the
order service.

```dart
class OrderPlaced {
  const OrderPlaced(this.id);
  final String id;
}

@Service()
class Orders {
  Orders(this.events);
  final ApplicationEventPublisher events;

  void place(String id) {
    // ... save the order ...
    events.publishEvent(OrderPlaced(id));   // every listener of OrderPlaced runs
  }
}

@Component()
@Log()
class Mailer {
  @EventListener()
  void onPlaced(OrderPlaced order) => log.info('confirmation for ${order.id}');
}
```

Listeners can be ordered, filtered by a condition, run asynchronously
with `@Async()`, and receive the container's own events (started,
closed). More: [events](spring_core_dart/README.md#events).

### AOP

*In the guides:* [server, 6. Events and AOP](example/server_guide/README.md#6-events-and-aop).

AOP (aspect-oriented programming) runs your code before, after or around
the methods of other beans without editing them. Use it for concerns
that cut across many classes: logging, timing, auditing, permission
checks, retries. Caching (`@Cacheable`), method security
(`@PreAuthorize`) and method validation (`@Validated`) are built on it.

```dart
// An annotation is a plain class with a const constructor.
class Timed {
  const Timed();
}

// An aspect: a bean whose advice runs around every method marked @Timed().
@Aspect()
@Component()
@Log()
class TimingAspect {
  @Around('@annotation(Timed)')
  Object? time(ProceedingJoinPoint call) {
    final watch = Stopwatch()..start();
    try {
      return call.proceed(); // runs the real method
    } finally {
      log.info('${call.signature.name}: ${watch.elapsedMilliseconds} ms');
    }
  }
}

@Service()
class Search {
  @Timed()
  List<String> find(String text) => ['dart', 'spring'];
}
```

The generator writes a proxy class for each bean; at startup a bean that
some pointcut matches is replaced by its proxy, and other beans receive
the proxy. As in Spring, a call a bean makes to its own method
(`this.find(...)`) skips the advice. A bare named pointcut such as
`orders()` refers to a `@Pointcut` method of the same aspect (or one it
inherits); another aspect's is written with its class,
`AuditAspect.orders()`.

More, with the pointcut syntax, the kinds of advice, ordering and the
proxy rules: [AOP](spring_core_dart/README.md#aop).

### SpEL

*In the guides:* [server, 10. Validation and SpEL](example/server_guide/README.md#10-validation-and-spel).

SpEL (Spring Expression Language) is a small expression language for
values computed at run time: in `@Value('#{...}')`, in cache keys
(`@Cacheable(key: ...)`), in security rules (`@PreAuthorize(...)`), or
evaluated from your own code.

```dart
// A value computed from a setting at startup.
@Component()
class Storage {
  Storage(@Value(r"#{'${app.home}' + '/cache'}") this.cacheDir);
  final String cacheDir;
}

// An expression evaluated by hand, here on a map.
final parser = SpelExpressionParser();
parser
    .parseExpression('2 * (price + tax)')
    .getValue(StandardEvaluationContext(), {'price': 20, 'tax': 4}); // 48
```

Dart has no reflection, so expressions reach your classes through the
metadata the generator writes for `@Introspected()` classes. More, with
the operators, the number rules and the limits against hostile
expressions: [SpEL](spring_core_dart/README.md#spel).

### Validation and data binding

*In the guides:* [server, 10. Validation and SpEL](example/server_guide/README.md#10-validation-and-spel), [app, 9. Validation](example/flutter_guide/README.md#9-validation).

Constraint annotations on the fields of a class say what a valid value
is; a validator checks an object against them and reports every error
with a code that a `MessageSource` turns into a message. Data binding
fills an object from strings (a form, query parameters), converting
types and recording what could not be converted.

```dart
@Introspected()
class SignupForm {
  @NotBlank() @Size(max: 20) String name = '';
  @NotNull() @Email() String? email;
  @Min(18) int age = 0;
}

// The generated descriptions of the @Introspected classes.
final introspector = context.getBean<BeanIntrospector>();

final binder =
    DataBinder(SignupForm(), objectName: 'signup', introspector: introspector)
      ..validators.add(BeanValidator(introspector: introspector))
      ..bind({'name': 'Ada', 'age': '16'})   // e.g. the fields of a form
      ..validate();
binder.bindingResult.fieldError('age');   // code Min: must be greater than or equal to 18
```

The web starter validates `@Valid()` request bodies the same way, and
`@Validated()` beans have their method parameters checked. More:
[validation and data binding](spring_core_dart/README.md#validation-and-data-binding).

### JSON

*In the guides:* [server, 3. Web](example/server_guide/README.md#3-web), [app, 6. Server access](example/flutter_guide/README.md#6-server-access).

`ObjectMapper` turns objects into JSON and back, with Jackson's
annotations (`@JsonProperty`, `@JsonIgnore`, ...) and without writing
`fromJson` / `toJson`: one `@Introspected()` on a model is enough, and
the classes it uses from the same package are included. The web starter,
Feign and WebSocket clients use it for every body.

```dart
@Introspected()
class Book {
  const Book({required this.isbn, required this.title, this.tags = const []});
  final String isbn;
  final String title;
  final List<String> tags;
}

final mapper = context.getBean<ObjectMapper>();   // Spring Boot configures it
final json = mapper.writeValueAsString(book);     // {"isbn":"1","tags":[],"title":"Dune"}
final again = mapper.readValue<Book>(json);
```

More: [JSON](spring_core_dart/README.md#json-objectmapper), and its
`spring.jackson.*` settings in
[`spring_boot_dart`](spring_boot_dart/README.md#json-the-objectmapper-bean).

### Logging

*In the guides:* [server, 11. Logging](example/server_guide/README.md#11-logging), [app, 10. Logging](example/flutter_guide/README.md#10-logging).

`@Log()` on a class gives it a `log` getter, so a class logs without
creating its logger by hand. The framework, the starters and your code
all log through `SpringLog`; levels come from `logging.level.*`
properties, and `spring_boot_starter_logging` decides where the lines go
(console, files, an in-app log screen). Without it, warnings and errors
are printed.

```dart
// The getter is an extension in the generated file of the scan that
// covers this class (next to its @ComponentScan() declaration).
import 'package:my_shop/src/app.spring.dart';

@Service()
@Log()
class Checkout {
  void pay(Order order) {
    log.info('order placed', fields: {'order': order.id});
    log.debug(() => 'basket: ${order.dump()}'); // built only when enabled
  }
}
```

More: [logging](spring_core_dart/README.md#logging) and the
[logging starter](spring_boot_starter_logging/README.md).

### More in the core

- [Messages, resources, conversion](spring_core_dart/README.md#messages-resources-conversion):
  translated texts from `messages_*.properties`, files from
  `lib/resources/` and other locations, and conversion of strings into
  `int`, `Duration`, lists and enums.
  *In the guides:* [server, 2. Configuration](example/server_guide/README.md#2-configuration), [app, 4. Texts](example/flutter_guide/README.md#4-texts), [app, 5. Assets](example/flutter_guide/README.md#5-assets).
- [Other extension points](spring_core_dart/README.md#other-extension-points):
  post-processors that change beans or their definitions, custom scopes,
  `@InterfaceProxy()` for generated implementations of your own
  interfaces (how `@FeignClient` works), and `@BeanMethodAnnotation()`
  for your own method annotations (how `@Scheduled` works).
  *In the guides:* [server, 13. Advanced](example/server_guide/README.md#13-advanced).

## Coming from Spring (Java)

Names and behaviour are Spring's: Spring Framework 7, Spring Boot 4 and
Spring Security 7. Where the Dart port differs, each package README says
so in its *Differences from Spring* section. The quick start above in
Java:

```java
@ConfigurationProperties("greeting")
public class GreetingProperties {
  private String name = "World";
  private int times = 1;
  // getters and setters
}

@Service
public class Greeter {
  private final GreetingProperties properties;
  public Greeter(GreetingProperties properties) { this.properties = properties; }
  public String greeting() { return "Hello, " + properties.getName() + "!"; }
}

@SpringBootApplication
@ConfigurationPropertiesScan
public class Application {
  public static void main(String[] args) {
    SpringApplication.run(Application.class, args);
  }
}
```

What changes, and why:

| Spring (Java) | Here | Why |
|---|---|---|
| Reflection and classpath scanning at run time | `build_runner` reads the annotations and writes `*.spring.dart` files; run it after changing annotations | Flutter, AOT and the web have no reflection |
| `src/main/resources` | `lib/resources/`, embedded by the generator | `lib/` is the only part of a package that other packages and every platform see |
| `@SpringBootApplication` on a class with `main` | On the `main` function itself | Dart has top-level functions |
| `@Autowired` on private fields | Constructor parameters, or public fields and setters | Generated code is another library and cannot reach private members |
| CGLIB and JDK proxies, created at run time | Proxy classes written at build time (implementing the bean's class or interfaces, or a generated subclass) | No runtime bytecode generation |
| SpEL and Jackson read any object | They read classes marked `@Introspected()` | No reflection |
| `@Null`, `@Pattern`, `@Future` | `MustBeNull`, `Matches`, `FutureDate` (same error codes) | They clash with Dart's `Null`, `Pattern` and `Future` |
| Circular references can be allowed | Always an error | Spring Boot's default |
| Start-up and shutdown callbacks block until done | A callback may return a `Future`: `refreshAsync()` and `closeAsync()` wait for it; `refresh()` fails on it and `close()` goes on without waiting | Dart cannot block on a `Future` |

Every difference, with the reason, is listed per package:
[core](spring_core_dart/README.md#differences-from-spring),
[Boot](spring_boot_dart/README.md#differences-from-spring),
[web types](spring_web_dart/README.md#differences-from-spring),
[web starter](spring_boot_starter_web/README.md#differences-from-spring),
[Feign](spring_boot_starter_feign/README.md#differences-from-spring-cloud-openfeign),
[logging](spring_boot_starter_logging/README.md#differences-from-spring),
[scheduling](spring_boot_starter_scheduling/README.md#differences-from-spring),
[cache](spring_boot_starter_cache/README.md#differences-from-spring),
[security core](spring_security_core/README.md#differences-from-spring-security),
[OAuth2 client](spring_boot_starter_oauth2_client/README.md#differences-from-spring),
[security starter](spring_boot_starter_security/README.md#differences-from-spring-security),
[tests](spring_boot_starter_test/README.md#differences-from-spring).

## Roadmap

Plans and sketches of coming features are in [`roadmap/`](roadmap/README.md),
one file per package: Data, retry, an HTTP client, an MCP server, the
actuator, OAuth2 clients, the next steps of the existing starters and of
Security (the web starter's static files and Flutter isolates among
them), Flutter (signals, Flutter Scene and Rust), the editor extensions,
and the [fix plan](roadmap/fix_plan.md): open differences from Spring
found in reviews.

## License

Apache License 2.0, see [LICENSE](LICENSE). Spring is a trademark of
Broadcom Inc.; this project is an independent port and is not affiliated
with or endorsed by the Spring team.

## Development

```bash
dart pub get
dart run melos run check                 # versions, dependencies, generated code, analysis, format, tests
dart run tool/check_dependencies.dart    # only this repository, the Dart SDK and Dart-team packages
dart run tool/test_all.dart              # the tests of every package, from each package and from the root
dart run tool/test_all.dart --exclude-tags integration   # without the tests on real sockets and processes
dart run tool/test_all.dart --tags integration           # only those (CI: own job; the rest in 4 parts, --job i/4)
dart run tool/affected.dart --base origin/main           # the packages a change affects, with their dependents; CI tests only those
dart run melos run coverage
```

A release is made with the *Release* workflow on `main` (Actions →
Release → Run workflow, choosing `patch` or `minor`): it gives every
package the new version (`tool/release.dart`, `tool/version.dart`), runs
the tests, and pushes the commit and tag that start the publication to
pub.dev.

**Dependency policy.** The packages use only each other, the Dart SDK,
the Flutter SDK and packages published on pub.dev by the Dart and Google
teams (`dart.dev`, `tools.dart.dev`, `labs.dart.dev`, `google.dev`,
`flutter.dev`), transitive dependencies included. The packages that end
up in applications (`spring_core_dart`, `spring_boot_dart`,
`spring_web_dart` and every runtime starter) depend on nothing outside
this repository except the Dart team's `package:yaml` (for
`application.yml`), the Flutter SDK for the Flutter starter, and, for
the two security packages only and until it can be replaced,
`pointycastle` (Bouncy Castle's cryptography). CI enforces it with
`tool/check_dependencies.dart`; any other package needs an exception
there, with a reason and the packages allowed to use it. Every package,
its publisher, the exceptions and the full graph:
[docs/dependencies.md](docs/dependencies.md).

The Flutter packages (`spring_boot_starter_flutter` and the Flutter
guide) are outside the pub workspace on purpose: Flutter pins
`test_api`, which would keep `package:test` and `build_test` on an older
analyzer than `build_runner` and `source_gen` need. Applications are
unaffected.

The generated `*.spring.dart` files are committed. CI
(`.github/workflows/ci.yml`) also checks that the generated code is up to
date, that every starter works as an application's only dependency,
that the server guide runs (also as minified JavaScript, for the AOP
release check), the SpEL and JSON tests on Node.js, the Flutter app's
tests and golden screenshots, the security starter against Spring
Security itself, and known vulnerabilities of the dependencies.
