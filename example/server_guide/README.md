# NEON Books server — a guide to Spring Boot in Dart

The server of NEON Books, a small bookstore: a catalog with covers, a
basket, orders, live stock, a support chat, a supplier it restocks from,
and an admin's view of the logs. It is a real application, and it is the
guide to this repository's server side: read the chapters below in order
and open the files they point to. Every chapter has tests that check what
it says.

Its client is the Flutter app of [`../flutter_guide/`](../flutter_guide/README.md);
the two share no code, only the [API](#api) below.

## Run it

```bash
cd example/server_guide
dart run build_runner build          # after changing beans (the generated *.spring.dart are committed)
dart run bin/main.dart               # dev: sample data, a local supplier, port 8080
dart run bin/main.dart --spring.profiles.active=prod
dart run bin/advanced.dart           # chapter 13
dart test                            # everything (unit and integration)
dart test --exclude-tags integration # without real sockets
```

Try it with curl (the cookie jar plays the app; `x` reads the CSRF token
from it):

```bash
J=/tmp/neon.txt; x() { grep XSRF-TOKEN $J | awk '{print $7}'; }
curl -c $J -b $J 'localhost:8080/api/books?q=dune'
curl -c $J -b $J -X POST -H "X-XSRF-TOKEN: $(x)" -d 'username=ada&password=ada-secret' localhost:8080/api/login -i
curl -c $J -b $J localhost:8080/api/me
curl -c $J -b $J -X PUT -H "X-XSRF-TOKEN: $(x)" -H 'Content-Type: application/json' \
     -d '{"quantity": 2}' localhost:8080/api/basket/items/9780441013593
curl -c $J -b $J -X POST -H "X-XSRF-TOKEN: $(x)" localhost:8080/api/orders -i
curl -N localhost:8080/api/stock/events          # live stock (orders and restocking change it)
curl localhost:8080/api/books/9780000000000      # 404 application/problem+json
```

Everything lives in a few places:

```text
bin/main.dart                 @SpringBootApplication — the whole entry point
bin/advanced.dart             chapter 13, runnable
lib/src/app.dart              @ComponentScan of lib/src/ (the `log` getters of @Log go there)
lib/src/<area>/               shop, catalog, stock, orders, security, web, support, supplier, aop, admin
lib/src/advanced/             chapter 13 (active only with the `advanced` profile)
lib/resources/                the classpath: configuration, messages, sample data, covers, templates
test/                         one or more test files per chapter; test/resources/ is the test classpath
tool/                         release_check.dart (chapter 14), hash_password.dart (chapter 4)
```

The [root README's Guide](../../README.md#guide) explains each feature in
general; the package READMEs go into every detail. This guide shows them
working together.

## API

The contract between this server and the Flutter app:

Base URL `http://localhost:8080` (property `server.port`). JSON everywhere, errors as
`application/problem+json`.

Users (in memory, passwords stored as `{argon2}` hashes, generated once and written into
application.properties, never plain text): `ada` / `ada-secret` role USER, `root` / `root-secret`
roles USER and ADMIN.

Security (spring_boot_starter_security): one chain for the API, sessions, CSRF with
`CookieCsrfTokenRepository.withHttpOnlyFalse()` (the app reads cookie `XSRF-TOKEN` and sends
header `X-XSRF-TOKEN` on POST/PUT/DELETE, as Spring's SPA recipe), CORS from properties (for the
Flutter web build), form login at `POST /api/login` (fields `username`, `password`) answering
`204` on success and `401` on failure (custom success/failure handlers: no redirects, an API
client logs in), logout at `POST /api/logout` → `204`. Anonymous GETs of the catalog are allowed.

| Method | Path | Who | What |
|---|---|---|---|
| GET | `/api/books?q=&page=` | anyone | catalog page (`Page`-like JSON: items, page, total), `@RequestParam`s, cached |
| GET | `/api/books/{isbn}` | anyone | one book, 404 ProblemDetail if unknown |
| GET | `/api/books/{isbn}/cover` | anyone | the cover image (`Resource`, `Range`, `Cache-Control`) |
| POST | `/api/books` | ADMIN | add a book, `@Valid` body (400 with field errors), 201 + `Location` |
| PUT | `/api/books/{isbn}/cover` | ADMIN | upload a cover (multipart `@RequestPart MultipartFile`) |
| DELETE | `/api/books/{isbn}` | ADMIN | remove (method security `@PreAuthorize` on the service) |
| GET | `/api/stock/events` | anyone | server-sent events `StockChanged {isbn, available}` (`EventStream` or `SseEmitter`), `Last-Event-ID` resume |
| GET | `/api/me` | logged in | `{name, roles}` (`@AuthenticationPrincipal`) |
| GET | `/api/basket` | logged in | the user's basket (kept in the `HttpSession`) |
| PUT | `/api/basket/items/{isbn}` | logged in | set a quantity `{quantity}` |
| POST | `/api/orders` | logged in | order the basket: 201 `Order`; publishes `OrderPlaced` |
| GET | `/api/orders` | logged in | the user's orders (`@PostFilter` on the service: own orders; ADMIN sees all) |
| WS | `/ws/support` | logged in | support chat: JSON `ChatMessage {from, text, at}`; the handshake passes the security chain (session cookie); the server answers with a bot and broadcasts to admins |
| GET | `/actuator`-like `/api/admin/logs` | ADMIN | the last log lines from `LogBuffer` |

The app and the server share no Dart package (they are separate apps); the app has its own model
classes matching this JSON.

### The JSON, as this server writes it

Properties are written sorted by name and `null`s are left out
(`spring.jackson.default-property-inclusion=non_null`); unknown
properties in requests are ignored.

| What | JSON |
|---|---|
| Book | `{"isbn": "9780441013593", "title": "Dune", "author": "Frank Herbert", "price": 9.99, "year": 1965, "tags": ["fiction"], "format": "PAPERBACK", "available": 5}` (`format`: `PAPERBACK`, `HARDCOVER`, `EBOOK`) |
| Page | `{"items": [Book, ...], "page": 0, "size": 10, "total": 8}` (`page` from 0; `?page=` too) |
| New book (`POST /api/books`) | `{"isbn": "9780261102385", "title": "...", "author": "...", "price": 25.0, "year": 1954, "tags": [], "format": "HARDCOVER", "stock": 2}`: `isbn` 13 digits starting with 978/979, `title` and `author` not blank, `price` > 0; the rest optional |
| Cover upload | `multipart/form-data`, the image (PNG or JPEG, at most `neon.shop.max-cover-size`) in the part `file`; 204 |
| Basket | `{"items": [Line, ...], "count": 3, "total": 26.97}` |
| Line | `{"isbn": "...", "title": "Dune", "price": 9.99, "quantity": 3, "discount": 10, "total": 26.97}` (`discount` in percent) |
| Quantity (`PUT /api/basket/items/{isbn}`) | `{"quantity": 2}` (0 removes the book; 0-10; 409 above the stock or the basket limit); answers the Basket |
| Order | `{"id": 1, "user": "ada", "lines": [Line, ...], "total": 26.97, "status": "PLACED", "placedAt": "2026-10-27T17:27:03.382Z", "payment": "sandbox-1"}` (`status`: `PLACED`, then `SHIPPED`); 409 for an empty basket |
| Me | `{"name": "root", "roles": ["ADMIN", "USER"]}` |
| StockChanged event | `id: 7`, `event: stock`, `data: {"isbn": "...", "available": 4}` |
| ChatMessage | `{"from": "ada", "text": "Hi", "at": "2026-10-27T17:27:03.382Z"}`; clients may send only `{"text": "..."}` |
| Log line | `{"time": "...", "level": "WARN", "logger": "neon.audit", "message": "...", "fields": {"request": "8f3a..."}}`; `?level=warn&logger=neon&q=text&limit=100` |
| Problem | `{"type": "about:blank", "title": "Not Found", "status": 404, "detail": "...", "instance": "/api/books/..."}`; a 400 of `@Valid` adds `"errors": [{"field": "isbn", "message": "...", "rejectedValue": "12"}]`, the messages in the language of `Accept-Language` (English, Japanese) |

Also served: `GET /api/books/recent` (the books of the `neon-recent`
cookie that `GET /api/books/{isbn}` sets), `GET /api/orders/{id}` (the
order's customer and admins; the `Location` of a new order),
`GET /api/admin/orders/live` (admins: orders placed and shipped, and
low stock, as server-sent events), `GET /supplier/**` (dev: the
supplier stub, chapter 9).

**CSRF in practice:** every response carries the `XSRF-TOKEN` cookie
when the client has none; send it back in `X-XSRF-TOKEN` with POST, PUT
and DELETE (`/api/login` included). The token changes at login (the
login response removes it): the next response, e.g. `GET /api/me`,
brings the new one.

## 1. The application

One annotation on `main`, one generated import: the generator scans
`lib/` and `bin/`, finds the starters in `pubspec.yaml` and writes
`bin/main.spring.dart` with `runApplication`. `lib/src/app.dart` is the
`@ComponentScan` of `lib/src/`, so its generated file can hold the `log`
getters of the `@Log` classes.

| Feature | Where |
|---|---|
| `@SpringBootApplication`, `runApplication(args)` | `bin/main.dart` |
| stereotypes: `@Service`, `@Repository`, `@Component`, `@RestController`, `@Configuration` | `lib/src/catalog/`, `lib/src/orders/`, ... |
| `@Bean`: lazy, an alias, `initMethod`, an inferred destroy method (`close`), a prototype, an inter-bean call; `@ConditionalOnMissingBean` | `lib/src/shop/shop_config.dart` (`CoverStore`: `lib/src/catalog/cover_store.dart`) |
| a static `@Bean` method | `SecurityConfig.roleHierarchy` |
| one bean name in two profile configurations, the type inferred from the body | `lib/src/orders/mail.dart` |
| constructor injection everywhere; field (`checkout`) and setter (`clock`) injection | `lib/src/orders/order_service.dart` |
| method injection (`@Autowired void configure(...)`), `@Value` with SpEL | `StartupAnnouncement`, `lib/src/shop/startup.dart` |
| a Dart default value kept (`recentLimit`), a primary constructor (`class StockReport(this._stock)`) | `BookController`, `lib/src/stock/restock_job.dart` |
| `List` and `Map` injection in `@Order`, a `@Primary` composite getting the *other* beans | `lib/src/shop/pricing.dart` |
| an empty `List` when no bean exists (`ChatFilter`) | `lib/src/support/support_endpoint.dart` |
| `@Profile`, `@Fallback`, `@Qualifier` | `lib/src/shop/payments.dart` |
| `ObjectProvider` (a lazy bean on demand), `@Lookup` (a prototype per call) | `BookController.covers`, `OrderMailer.newReceipt` |
| `@Lazy` reference to itself: calls through the proxy (cached) | `CatalogService._self`, `lib/src/catalog/catalog_service.dart` |
| `@PostConstruct`, `@PreDestroy`, `SmartLifecycle`, `SmartInitializingSingleton` | `InMemoryBookRepository`, `OrderRepository`, `StockFeed`, `CatalogStatistics` |
| `ApplicationRunner` / `CommandLineRunner` in `@Order` | `SampleData`, `StartupAnnouncement` (`lib/src/shop/startup.dart`) |
| `@Log` (`log` getter, `topic:`, `fieldName:`) | almost every class |

Try: `dart run bin/main.dart` and read the startup lines (sample data,
then the announcement); Ctrl+C closes the context (`@PreDestroy` of
`OrderRepository`, graceful shutdown).

Tests: `test/application_test.dart`. More: [`spring_boot_dart`](../../spring_boot_dart/README.md),
[the root Guide](../../README.md#declaring-beans).

## 2. Configuration

`lib/resources/` is the classpath; the generator embeds it.

| Feature | Where |
|---|---|
| `application.properties`, a profile file in `.properties` (dev) and in YAML (prod) | `lib/resources/application*.{properties,yml}` |
| `spring.profiles.active=dev`, a profile group (`dev` → `supplier-stub`), a profile expression (`supplier-stub & !prod`) | `application.properties`, `lib/src/supplier/supplier_stub.dart` |
| a second document (`#---`) for every profile but prod (`on-profile=!prod`) | end of `application.properties` |
| `spring.config.import` with its `-{profile}` variant; `${SUPPLIER_API_KEY:}` from the environment | `lib/resources/config/supplier*.properties` |
| `@ConfigurationProperties` validated at startup (`@Validated`, constraints, a class-level constraint), `Duration` and `DataSize` | `lib/src/shop/shop_properties.dart` |
| maps of nested objects with a `@Valid` cascade | `lib/src/security/users.dart` |
| `@Value` with placeholders and defaults, SpEL, conversion | `CatalogService.pageSize`, `OrderService.shippingDelay`, `StartupAnnouncement.banner` |
| relaxed binding: `NEON_SHOP_NAME=...`, `--neon.shop.max-basket-size=5` | any `neon.*` property |
| `@ConditionalOnProperty`, `@ConditionalOnMissingBean`, `@Conditional` with our own `Condition` | `SupportBot`, `ShopConfig.clock`, `SupplierConfigured` + `RestockJob` |
| `@PropertySource` | `SupportBot` (`lib/resources/support/bot.properties`) |
| `classpath:` resources (`Resource`), text and binary | `SampleData` (`data/books.json`), `OrderMailer` (`templates/`), `CoverStore` (`covers/`) |
| `messages*.properties` (English, Japanese) through `MessageSource` | `lib/resources/messages/`, `SupportBot`, `ApiErrors`, `OrderMailer` |

Try: `NEON_SHOP_NAME="Night Books" dart run bin/main.dart`;
`dart run bin/main.dart --neon.shop.opens-at=22` (the failure report of
the class-level constraint); `--spring.profiles.active=prod` (no sample
data, no restocking without `SUPPLIER_API_KEY`).

Tests: `test/configuration_test.dart`. More: [configuration reference](../../docs/configuration.md),
[`spring_boot_dart`](../../spring_boot_dart/README.md#configurationproperties).

## 3. Web

| Feature | Where |
|---|---|
| `@RestController`, `@RequestMapping`, `@GetMapping` ... | `lib/src/catalog/book_controller.dart` and the other `*_controller.dart` |
| path variables, request parameters with defaults, a header (`Last-Event-ID`), a cookie (`neon-recent`) | `BookController`, `StockController` |
| `@RequestBody @Valid`, `ResponseEntity` (201 + `Location`), `@ResponseStatus` | `BookController.add`, `OrderController.place` |
| `ProblemDetail`, `@ExceptionHandler`, `@RestControllerAdvice`, `ResponseStatusException`; validation messages in the request's language | `lib/src/web/api_errors.dart` |
| JSON through the `ObjectMapper`: `spring.jackson.*`, `@JsonProperty` (`user`), enums with `@JsonValue`, nested immutable classes | `lib/src/catalog/book.dart`, `lib/src/orders/order.dart` |
| files: a `Resource` download with `Range` and `Cache-Control`, a multipart upload (`@RequestPart MultipartFile`) | `BookController.cover`, `BookController.uploadCover` |
| server-sent events: an `EventStream` with replay after `Last-Event-ID`; an `SseEmitter` fed by event listeners | `lib/src/stock/stock_feed.dart`, `lib/src/admin/order_feed.dart` |
| `OncePerRequestFilter` (request id, log fields), `WebFilter` (access log) | `lib/src/web/request_id_filter.dart` |
| `HandlerInterceptor` registered by a `WebMvcConfigurer` (`Server-Timing`) | `lib/src/web/web_config.dart` |
| CORS from properties (`neon.cors.*`) | `SecurityConfig.corsConfigurationSource` |
| `HttpSession` (the basket) | `lib/src/orders/basket_service.dart` |
| `server.*`, `spring.servlet.multipart.*`, graceful shutdown, `spring.mvc.sse.heartbeat-interval` | `application.properties` |

Try: `curl -i -H 'Range: bytes=0-15' localhost:8080/api/books/9780441013593/cover`;
`curl -N localhost:8080/api/stock/events` and order a book in another
terminal; `curl -N -H 'Last-Event-ID: 1' localhost:8080/api/stock/events`.

Tests: `test/web_test.dart` (MockMvc), `test/server_integration_test.dart`
(real sockets). More: [`spring_boot_starter_web`](../../spring_boot_starter_web/README.md).

## 4. Security

| Feature | Where |
|---|---|
| two `SecurityFilterChain`s: the supplier stub (`securityMatcher`, stateless, no CSRF) and the API | `lib/src/security/security_config.dart` |
| request rules on path patterns; the first match decides, no match is denied | `SecurityConfig.apiChain` |
| form login at `/api/login` with our own success and failure handlers (204 / 401), logout (204), 401 instead of a login page | `lib/src/security/api_login.dart` |
| CSRF in a cookie for the app (`CookieCsrfTokenRepository.withHttpOnlyFalse()`), sent with every response by a filter | `CsrfCookieFilter` |
| users from properties with `{argon2}` hashes, `DelegatingPasswordEncoder`, `UserDetailsService` | `lib/src/security/users.dart`, `tool/hash_password.dart` |
| `@PreAuthorize`, `@PostAuthorize`, `@PostFilter`, `@Secured` | `CatalogService`, `OrderService`, `LogService` |
| `hasPermission` with a `PermissionEvaluator`; `RoleHierarchy` (ADMIN > USER) | `OrderPermissionEvaluator`, `SecurityConfig.roleHierarchy` |
| authentication events (failed logins logged and counted) | `lib/src/security/login_audit.dart` |
| security headers (with a Content-Security-Policy), the firewall | `SecurityConfig.apiChain`; the starter |
| `@AuthenticationPrincipal`, `Authentication` and `Principal` arguments | `MeController`, `OrderController`, `SupportEndpoint` |

The request rules let any logged-in user send `DELETE
/api/books/{isbn}`; the service's `@PreAuthorize` answers 403 unless the
user is an admin. The app hides admin screens from users — a
convenience: the server checks every call again.

Try the curl session above; then `curl -i localhost:8080/api/books\;x`
(400, the firewall). In prod, replace a password without touching the
files: `NEON_SECURITY_USERS_ROOT_PASSWORD="$(dart run tool/hash_password.dart s3cret)"`.

Tests: `test/security_test.dart` (with `user()` / `csrf()` of
`package:spring_boot_starter_security/testing.dart` and `withMockUser`).
More: [`spring_boot_starter_security`](../../spring_boot_starter_security/README.md),
[`spring_security_core`](../../spring_security_core/README.md).

## 5. WebSocket

The support chat is a `@WebSocketEndpoint` (`@OnOpen`, `@OnMessage`,
`@OnClose`, `@OnError`) on the web server's port. The handshake goes
through the security chain (the session cookie), so the methods get the
user (`Principal`). What customers write goes to every admin in the chat
(`WebSocketSessionRegistry`); admins answer one customer with
`@ada text`; the bot answers at once (in Japanese with
`Accept-Language: ja`); a shipped order is announced in the customer's
chat.

Files: `lib/src/support/`. Tests: `test/websocket_test.dart`
(`MockMvc.webSocket`), `test/server_integration_test.dart` (a real
socket with the session cookie). More:
[`spring_boot_starter_websocket`](../../spring_boot_starter_websocket/README.md#server-endpoints).

## 6. Events and AOP

| Feature | Where |
|---|---|
| a payload event (`OrderPlaced`), an `ApplicationEvent` (`OrderShipped`) | `lib/src/orders/order.dart`, `OrderService` |
| `@EventListener` with `@Order` and a `condition`, `@Async`, a returned event (`LowStock`), `classes:` | `StockService`, `lib/src/orders/order_listeners.dart`, `ServerAnnouncer` |
| an `ApplicationListener` bean | `ShippingNotifier` |
| Spring Boot and web server events (`ApplicationReadyEvent`, `WebServerInitializedEvent`) | `ServerAnnouncer` |
| `@Aspect` with a named `@Pointcut`, `within()` and `bean()`, `@Before` with `args()`, `@AfterReturning`, `@AfterThrowing`, `@After` (on Feign clients), `@Around` for `@Timed`; aspect order | `lib/src/aop/aspects.dart` |
| a `PointcutAdvisor` bean with a `MethodInterceptor` | `lib/src/aop/handler_metrics.dart` |

`@EventListener(condition:)` takes a function here, not a SpEL string
(no reflection to evaluate one on the event).

Tests: `test/events_aop_test.dart`. More: [the root Guide](../../README.md#events),
[AOP](../../README.md#aop).

## 7. Data access

There is no database package yet: the repositories are in-memory beans
behind interfaces (`BookRepository`, `OrderRepository`), where Spring Data
repositories would be. `@Transactional` does not exist (and is not
invented here).

Files: `lib/src/catalog/book_repository.dart`,
`lib/src/orders/order_repository.dart`. Tests:
`test/data_access_test.dart` (another implementation swapped in with
`BeanOverride`).

## 8. Cache and scheduling

| Feature | Where |
|---|---|
| `@Cacheable` with SpEL keys and `unless`, `@CachePut`, `@CacheEvict` (`@Caching`) | `lib/src/catalog/catalog_service.dart` |
| `@Cacheable` on a Feign client method (async: the value is cached) | `SupplierOffers.offer` |
| `spring.cache.simple.*`: size and time limits, per cache | `application.properties` |
| `@Scheduled` with a fixed delay and initial delay from properties, and a cron | `lib/src/stock/restock_job.dart` |
| `TaskScheduler` in code (an order ships after `neon.orders.shipping-delay`) | `OrderService.place` |

Try: `dart run bin/main.dart` and watch the restock job after 10 s
(`neon.stock.restock-initial-delay`), then every 20 s in dev.

Tests: `test/cache_scheduling_test.dart`. More:
[`spring_boot_starter_cache`](../../spring_boot_starter_cache/README.md),
[`spring_boot_starter_scheduling`](../../spring_boot_starter_scheduling/README.md).

## 9. Feign

The supplier is another service, called through two `@FeignClient`s:
offers (a path variable, a query parameter, `@Cacheable`, `FeignNotFound`
for unknown books) and deliveries (a POST answering a `ResponseEntity`, a
header from a placeholder, a fallback when the supplier is down). A
`RequestInterceptor` adds the API key, a `Retryer` retries failed
connections, `spring.cloud.openfeign.client.config.*` sets timeouts and
the request log. In dev the supplier is a stub controller of this same
server under `/supplier/**`, so everything runs without internet.

Files: `lib/src/supplier/`, the job using them: `lib/src/stock/restock_job.dart`.
Tests: `test/supplier_test.dart` (`MockHttpTransport`). More:
[`spring_boot_starter_feign`](../../spring_boot_starter_feign/README.md).
Feign's client side of server-sent events (`EventStream<T>`) and the
declarative `@WebSocketClient` are in the [Flutter guide](../flutter_guide/README.md).

## 10. Validation and SpEL

| Feature | Where |
|---|---|
| constraints on request bodies (`NewBook`, `QuantityRequest`) and on `@ConfigurationProperties` | `lib/src/catalog/book.dart`, `lib/src/orders/order.dart`, `lib/src/shop/shop_properties.dart` |
| a class-level constraint | `ValidOpeningHours` |
| groups (`Catalogued`: what the supplier's books must have) | `NewBook`, `lib/src/advanced/import_batch.dart` |
| messages by Spring's codes (`NotBlank.newBook.title`), English and Japanese | `lib/resources/messages/` |
| SpEL in `@Value`, `@PreAuthorize` / `@PostFilter` / `@PostAuthorize`, cache keys | `StartupAnnouncement`, `OrderService`, `CatalogService` |

Tests: `test/validation_spel_test.dart`, the 400s of `test/web_test.dart`.
More: [the root Guide](../../README.md#validation-and-data-binding),
[SpEL](../../README.md#spel).

## 11. Logging

| Feature | Where |
|---|---|
| `logging.level.*`, a log group (`shop`), the console pattern | `application.properties` |
| a log file in prod (`logging.file.name`, rollover) | `application-prod.yml` |
| fields on every line of a request / an order (`SpringLog.withFields`) | `RequestIdFilter`, `OrderService.place` |
| the `LogBuffer` behind `/api/admin/logs` (filters by level, logger, text) | `lib/src/admin/log_service.dart` |

Try: `LOGGING_LEVEL_FEIGN=info dart run bin/main.dart` (no request log);
`curl -b $J 'localhost:8080/api/admin/logs?level=warn'` as root.

Tests: `test/logging_test.dart`. More:
[`spring_boot_starter_logging`](../../spring_boot_starter_logging/README.md).

## 12. Testing

| Feature | Where |
|---|---|
| `springBootTest` with the `test` profile (`test/resources/application-test.properties`) | `test/support/app.dart`, every test |
| `@SpringBootTest` test classes (`@ActiveProfiles`, `@TestEnvironment`, `@TestBean`, `@Autowired`, `@Value`, `@CapturedOutput`, `@Nested`, `@Tag`) | `test/shop_class_test.dart` |
| the order of a test class's annotations (`@BeforeAll`, `@DynamicPropertySource`, `@ContextInitializer`, `@TestPropertySource`, `@DirtiesContext`, `@Disabled`, `@TestOptions`) | `test/lifecycle_class_test.dart` |
| `MockMvc` with `user()` / `csrf()`, and a client keeping cookies like the app | `test/web_test.dart`, `test/security_test.dart`, `ApiClient` |
| `webEnvironment: randomPort` over real sockets (tag `integration`) | `test/server_integration_test.dart` |
| `BeanOverride` | `test/supplier_test.dart`, `test/cache_scheduling_test.dart`, `test/data_access_test.dart` |
| `ApplicationContextRunner` | `test/configuration_test.dart` |
| `captureLogs` | `test/events_aop_test.dart`, `test/security_test.dart` |
| `MockHttpTransport` for Feign | `test/supplier_test.dart` |
| `MockMvc.webSocket` | `test/websocket_test.dart` |

More: [`spring_boot_starter_test`](../../spring_boot_starter_test/README.md),
[docs/testing.md](../../docs/testing.md).

## 13. Advanced

Extension points a bookstore does not need every day, in
`lib/src/advanced/`. Their beans carry `@AdvancedTour()` (a subclass of
`@Profile`: the `advanced` profile, which the server never activates);
`bin/advanced.dart` starts the application's beans with it, without the
web server, and prints what each one did.

| Feature | Where |
|---|---|
| a `BeanPostProcessor` (initialization times) | `bean_init_timer.dart` |
| a `BeanFactoryPostProcessor` registering a custom scope, a scoped bean through `ObjectProvider` | `import_batch.dart` |
| a registry post-processor with a hand-written `BeanDefinition` | `alarm_registrar.dart` |
| every lifecycle callback in order (Aware interfaces, `InitializingBean`, `DisposableBean`, init/destroy methods), a `DestructionAwareBeanPostProcessor`, `stop()` / `start()` | `lifecycle_probe.dart` |
| `@Configurable` + `autowireBean` | `stock_report_printer.dart` |
| parent and child contexts, the startup failure report (a missing bean, a cycle), `SpelExpressionParser` and `SimpleEvaluationContext`, `DataBinder` and `BeanWrapper` | `demos.dart` |

Try: `dart run bin/advanced.dart`. Tests: `test/advanced_test.dart`.

## 14. Release builds

`tool/release_check.dart` starts the whole application compiled to
minified JavaScript and checks what depends on generated metadata rather
than names: the sample data read by the `ObjectMapper`, `@Cacheable`,
`@PreAuthorize`, the `@Timed` advice, the `@Scheduled` methods, a JSON
round trip with `@JsonValue` enums and `@JsonProperty`, messages, SpEL's
arithmetic.

```bash
dart compile js -O4 -o /tmp/release_check.js tool/release_check.dart
node -e 'globalThis.self = globalThis; require("/tmp/release_check.js")'
```

Code that needs `dart:io` (creating the covers' directory) sits behind a
conditional import (`lib/src/catalog/directories.dart`), as the
framework's own packages do it.
