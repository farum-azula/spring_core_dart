# spring_boot_starter_restclient

> **No backward compatibility before 1.0.** Any release may rename or
> change APIs, properties and behaviour; the breaking changes are listed
> in each package's CHANGELOG.

**Documentation:** [farum-azula.org/components/spring-boot-starter-restclient](https://farum-azula.org/components/spring-boot-starter-restclient)

Calls other HTTP services from
[`spring_boot_dart`](https://pub.dev/packages/spring_boot_dart)
applications with `RestClient`: inject a `RestClientBuilder`, set a base
URL, build a client, and call the API with objects in and objects out.
On a server or in a Flutter app alike.

Without this starter you would create a transport, keep it, set its
timeouts, encode JSON and check statuses by hand in every client. With it
the `RestClientBuilder` bean comes set up from `spring.http.clients.*`
(timeouts, redirects), with the application's `ObjectMapper` and your
`RestClientCustomizer` beans; HTTP service groups give each remote
service its own client from `spring.http.serviceclient.<group>.*`. And
every outgoing address is **denied until you allow it**: a URL that comes
from outside cannot make your server call into its own network or its
cloud's metadata service.

It is the Dart counterpart of Spring Boot's
`spring-boot-starter-restclient`. `RestClient` itself (its requests,
URI templates, exceptions, interceptors) is in
[`spring_web_dart`](https://pub.dev/packages/spring_web_dart#restclient).

## Installation

```yaml
dependencies:
  spring_boot_starter_restclient: ^0.10.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.10.0   # required: reads your beans and properties
```

```bash
dart run build_runner build
```

That is all: the starter is found automatically. The starter is the only
dependency an application needs: it brings `spring_web_dart`,
`spring_boot_dart` and `spring_boot_starter_logging` and re-exports them,
as every Spring Boot starter does.

## Quick example

```dart
import 'package:spring_boot_starter_restclient/spring_boot_starter_restclient.dart';

@Service()
class Catalog {
  // A new builder for this bean, already set up from spring.http.clients.*.
  Catalog(RestClientBuilder builder)
    : _rest = builder.baseUrl('https://catalog.neon.books').build();

  final RestClient _rest;

  Future<Book> find(String isbn) =>
      _rest.get().uri('/books/{isbn}', isbn).retrieve().body<Book>();

  Future<Book> add(Book book) =>
      _rest.post().uri('/books').body(book).retrieve().body<Book>();
}
```

```yaml
spring:
  http:
    clients:
      allowed-addresses: catalog.neon.books   # every other address is denied
      read-timeout: 10s
```

The same in Spring (Java):

```java
@Service
class Catalog {
  private final RestClient rest;

  Catalog(RestClient.Builder builder) {
    this.rest = builder.baseUrl("https://catalog.neon.books").build();
  }

  Book find(String isbn) {
    return rest.get().uri("/books/{isbn}", isbn).retrieve().body(Book.class);
  }
}
```

A 4xx answer throws an `HttpClientErrorException`, a 5xx an
`HttpServerErrorException`, no answer a `ResourceAccessException`; see
[RestClient](https://pub.dev/packages/spring_web_dart#restclient) for
URI templates, bodies, `onStatus`, interceptors, `exchange` and
server-sent events.

## HTTP service groups

A group is one remote service: its base URL, headers and timeouts in
properties, and one `RestClient` for it.

```yaml
spring:
  http:
    serviceclient:
      catalog:
        base-url: https://catalog.neon.books
        default-header:
          X-Api-Version: 2
      payments:
        base-url: https://pay.neon.books
        read-timeout: 5s
        redirects: dont-follow
```

```dart
@Service()
class Checkout {
  Checkout(HttpServiceGroups groups)
    : _payments = groups.restClient('payments');
  final RestClient _payments;
}
```

A group's base URL is allowed by itself. A group that is not configured
is an error naming the property to set. `RestClientHttpServiceGroupConfigurer`
beans change the groups' builders after the properties (an interceptor
for one group, a header for all):

```dart
@Bean()
RestClientHttpServiceGroupConfigurer paymentsAuth(TokenSource tokens) =>
    RestClientHttpServiceGroupConfigurer.of(
      (groups) => groups.filterByName(['payments']).forEachClient(
        (group, builder) => builder.requestInterceptor(BearerInterceptor(tokens)),
      ),
    );
```

The groups are what `@ImportHttpServices(group: ..., types: [...])`
puts `@HttpExchange` interfaces into (see
[HTTP service clients](#http-service-clients)).

## Customizing every builder

`RestClientCustomizer` beans run on every builder the starter makes (the
injected ones and the groups'), in their `@Order`:

```dart
@Configuration()
class HttpSetup {
  @Bean()
  RestClientCustomizer tracing(Tracer tracer) => RestClientCustomizer.of(
    (builder) => builder.requestInterceptor(TracingInterceptor(tracer)),
  );
}
```

`RestClient.create()` stays outside all of this: no customizers, no
allowed addresses, a transport of its own.

## Outgoing addresses: denied until allowed

The `httpTransport` bean calls only:

- the entries of `spring.http.clients.allowed-addresses`: host names
  (`api.neon.books`), subdomains (`*.neon.books`), address literals
  (`203.0.113.7`), CIDR blocks (`10.20.0.0/16`), or `*` for any host with
  a public address;
- the hosts of the groups' `base-url` values;
- what other starters were given by hand in their own properties, through
  `AllowedAddressesContributor` beans: the OAuth2 client's provider
  endpoints (`token-uri`, `issuer-uri`, ...).

A host name opens only its public addresses. Loopback, private networks,
link-local addresses and cloud metadata are denied unless an address or a
block within their own block is listed: `10.20.0.0/16` opens that
network, `0.0.0.0/0` opens no private address, `169.254.169.254` needs an
entry of its own, and `localhost` may resolve to loopback.

```yaml
spring:
  http:
    clients:
      allowed-addresses:
        - api.neon.books
        - inventory.internal
        - 10.20.0.0/16        # where inventory.internal resolves
        - localhost
```

On `dart:io` (servers, Flutter on mobile and desktop) the transport
resolves the name itself, checks every address and connects to an
address it checked, so DNS rebinding cannot swap the address after the
check; every redirect is checked again. In a browser (Flutter web) names
cannot be resolved: only the host of the URL is checked. A denied call
fails with a `ResourceAccessException` whose cause, a
`FilteredHostException`, names the host, the reason and the property to
set; nothing is sent.

An `InetAddressFilter` bean (Spring Boot 4.1's) narrows the list further;
an `AllowedAddressesContributor` bean adds entries of your own
(`AllowedAddressesContributor.of([inventory.url])`, for an address in
your own properties); an `AllowedAddresses` bean of your own replaces
the list; an `HttpTransport`
bean of your own (a mock in tests) replaces the transport, and its
addresses are then yours to check. The check cannot be switched off.

## Properties

| Property | Default | |
|---|---|---|
| `spring.http.clients.connect-timeout` | `10s` | the longest wait for a connection (`0`: none) |
| `spring.http.clients.read-timeout` | `60s` | the longest wait for data (`0`: none) |
| `spring.http.clients.redirects` | `follow-when-possible` | or `follow`, `dont-follow` |
| `spring.http.clients.allowed-addresses` | empty | the hosts and addresses the clients may call |
| `spring.http.serviceclient.<group>.base-url` | none | the group's base URL, allowed by itself |
| `spring.http.serviceclient.<group>.default-header.<name>` | none | headers of every call of the group |
| `spring.http.serviceclient.<group>.apiversion.default` | none | the API version of the calls that give none |
| `spring.http.serviceclient.<group>.apiversion.insert.header` | none | the header that holds the version |
| `spring.http.serviceclient.<group>.apiversion.insert.query-parameter` | none | the query parameter that holds it |
| `spring.http.serviceclient.<group>.apiversion.insert.path-segment` | none | the index of the path segment it is inserted as |
| `spring.http.serviceclient.<group>.apiversion.insert.media-type-parameter` | none | the `Content-Type` parameter that holds it |
| `spring.http.serviceclient.<group>.connect-timeout` | the clients' | |
| `spring.http.serviceclient.<group>.read-timeout` | the clients' | |
| `spring.http.serviceclient.<group>.redirects` | the clients' | |

## Beans

| Bean | Type | |
|---|---|---|
| `httpClientAllowedAddresses` | `AllowedAddresses` | unless the application has one |
| `httpTransport` | `HttpTransport` | `platformHttpTransport()` with those addresses, closed with the context; unless the application has one |
| `restClientBuilderConfigurer` | `RestClientBuilderConfigurer` | sets a builder up as the starter does |
| `restClientBuilder` | `RestClientBuilder` | prototype: a new builder for each injection |
| `httpServiceGroups` | `HttpServiceGroups` | the client of each group |
| `eventStreamRetryAdapter` | `EventStreamRetryAdapter` (`RetryStreamAdapter`) | with `spring.resilience.enabled: true` only: a `@Retryable` method that returns an `EventStream` stays an `EventStream` when retried |

## Testing

Replace the transport with the test starter's `MockHttpTransport`:

```dart
final server = MockHttpTransport()
  ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'});
final app = springBootTest(
  springApplication,
  overrides: [BeanOverride<HttpTransport>(server)],
);
```

The same in a test class, declared with annotations:

```dart
@SpringBootTest()
class CatalogTest {
  @TestBean(type: HttpTransport)
  final server = MockHttpTransport()
    ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'});

  @Autowired()
  late Catalog catalog;
}
```

## Differences from Spring Boot

- `RestClient.Builder` is `RestClientBuilder`; its request factory is
  the `httpTransport` bean, shared with the family's other clients.
- **Outgoing addresses are denied until allowed**
  (`spring.http.clients.allowed-addresses`); Spring Boot 4.1 allows
  every address until an `InetAddressFilter` bean is declared.
- A group's `connect-timeout` longer than the clients' raises the
  transport's own (on `dart:io` one `HttpClient` serves every group);
  each request still waits only as long as its group says.
- API versions are set per group (`apiversion.*`), as in Spring Boot 4,
  which has no `spring.http.clients.apiversion`. A group with
  `apiversion` properties and no `insert.*` keeps its builder's inserter
  (a `RestClientCustomizer`'s), where Spring Boot sets one that inserts
  nothing; a default version with no inserter fails the start.
- No SSL bundles, cookie handling or `RestClientSsl` yet.
- HTTP service interfaces are implemented by the build, not by a proxy
  made when the application starts (see
  [HTTP service clients](#http-service-clients)).

## HTTP service clients

Declare the calls of a remote service as an interface, and import it into
a group: the generator writes the class that makes each call with the
group's `RestClient`, and registers it as a bean. As Spring's HTTP
service clients (`@HttpExchange` with `@ImportHttpServices`), with the
implementation written by the build: no proxy is made when the
application starts and no annotation is read then.

```dart
@HttpExchange('/books')
abstract interface class BookService {
  @GetExchange('/{isbn}')
  Future<Book> find(@PathVariable() String isbn);

  @GetExchange()
  Future<List<Book>> search(@RequestParam() String q, {@RequestParam() int? year});

  @PostExchange()
  Future<ResponseEntity<Book>> create(@RequestBody() Book book);

  @DeleteExchange('/{isbn}')
  Future<void> remove(@PathVariable() String isbn);
}

@SpringBootApplication()
@ImportHttpServices(group: 'catalog', types: [BookService])
void main(List<String> args) => runApplication(args);
```

```yaml
spring:
  http:
    serviceclient:
      catalog:
        base-url: https://catalog.neon.books
        read-timeout: 5s
```

Inject `BookService` as any bean. Its calls go through the client of the
`catalog` group: the base URL, default headers and timeouts of
`spring.http.serviceclient.catalog.*`, the `RestClientCustomizer` and
`RestClientHttpServiceGroupConfigurer` beans, the `httpTransport` (and its
allowed addresses, which the group's host joins). A 4xx or 5xx answer
throws a `RestClientResponseException`, as a `RestClient` call does.

`@ImportHttpServices` goes on the application's `main` or on a bean
class, usually a `@Configuration()` class, once per group (`default`
when the group is not named); an interface belongs to one group. As in
Spring, a class's interfaces are imported only when the class is
registered: its conditions (`@Profile`, `@ConditionalOnProperty`, and
those of a class importing it with `@Import`) apply to their beans and
their group.

Instead of listing them in `types`, let the build find them:
`basePackages` takes library URI prefixes of the package being built,
`basePackageClasses` types whose library's directory is searched; every
class with an exchange annotation below is imported, subdirectories
included. build_runner lists the files of the package it builds only, so
another package's prefix or type fails the build (list its interfaces in
`types`), and so does an entry that finds nothing.

```dart
@SpringBootApplication()
@ImportHttpServices(group: 'catalog', basePackages: ['package:shop/src/catalog/'])
@ImportHttpServices(group: 'payments', basePackageClasses: [PaymentService])
void main(List<String> args) => runApplication(args);
```

**The URL and the defaults.** The interface's `@HttpExchange` gives the
URL prefix and the defaults of its methods (`method`, `contentType`,
`accept`, `headers`); a method's annotation adds to the URL and
overrides the rest. `headers` are written `'Name=value'`, and the URL
and the header values may hold `${property}` placeholders, filled once
when the bean is made (a `${...}` in the URL fills a path below the
group's base URL).

```dart
@PostExchange.of(
  url: '/{isbn}/reviews',
  accept: ['application/json'],
  headers: [r'X-Client=${spring.application.name}'],
)
Future<Review> review(@PathVariable() String isbn, @RequestBody() Review review);
```

**The parameters** say where their value goes, with the annotations a
controller uses:

| Annotation | Sent as |
|---|---|
| `@PathVariable()` | fills `{name}` of the URL (non-nullable) |
| `@RequestParam()` | a query parameter (a list: one per item; `null`: left out); with `contentType: 'application/x-www-form-urlencoded'`, a field of the form body |
| `@RequestHeader('X-Name')` | a header (a list: one value per item; `null`: left out) |
| `@CookieValue()` | a cookie (`null`: left out) |
| `@RequestParam()`, `@RequestHeader()`, `@CookieValue()` on a `Map<String, T>` (or `Map<String, List<T>>`, Spring's `MultiValueMap`) | one per entry (or per item), named by the key |
| `@PathVariable()` on a `Map<String, T>` | the URL's variables by name |
| `@RequestHeader()` on an `HttpHeaders` | every header of it |
| `@RequestAttribute()` | a request attribute of the call, the value as it is (a `Map<String, T>`: one per entry) |
| `@RequestBody()` | the body: JSON through the `ObjectMapper`, a `String` or bytes as they are |
| `@RequestPart()` | a part of a `multipart/form-data` body: a `MultipartFile` (or a list of them) as a file, `Uint8List` as a file without a name, a `String`, number, enum or `DateTime` as a text field, anything else as JSON |
| none, type `Uri` | the whole URL of the call |
| none, type `HttpMethod` | the method of the call |
| none, type `UriBuilderFactory` | the base the URL is expanded against instead of the group's (`null`: the group's) |

The name is the parameter's unless the annotation gives one
(`@RequestParam('page_size') int size`). A parameter with none of these
fails the build (Spring fails it when the application starts). A map's
values are written as a single parameter's; a `null` map adds nothing. A
header value with CR, LF or NUL, and a cookie value with a control
character or `;`, throw an `ArgumentError` before anything is sent.

```dart
@GetExchange('/search')
Future<List<Book>> search(
  @RequestParam() Map<String, String> filters, {
  @RequestHeader() HttpHeaders? extra,
  @RequestAttribute('trace.tag') String? trace,
});
```

**Uploads.** A `MultipartFile` part is read through its `openRead()`
while the body is sent, with its `size` as the length, never loaded
whole: a file a controller received goes on to another service in a
chunk or two of memory, and a retried call reads it again. With a
`RestClient`, `MultipartBodyPart.multipartFile` sends the same part, and
`MultipartBodyPart.fromPath` a file from the disk:

```dart
@PostExchange.of(url: '/{isbn}/cover', contentType: 'multipart/form-data')
Future<void> upload(@PathVariable() String isbn, @RequestPart() MultipartFile cover);

await rest.post()
    .uri('/{isbn}/cover', isbn)
    .body(MultipartBody([MultipartBodyPart.multipartFile('cover', cover)]))
    .retrieve()
    .toBodilessEntity();
```

A streamed body is read whole first only for an interceptor that wants
the bytes (Spring's interceptors get a `byte[]`); one that implements
`StreamingClientHttpRequestInterceptor`, as the OAuth2 starter's does,
lets it through. A part made from a stream is sent once: a retry fails
with a `NonRepeatableBodyException` instead of sending half of it.

**API versions.** `version:` of an exchange annotation (the method's, else
the interface's) is the version the call asks for; the group's client
puts it where `spring.http.serviceclient.<group>.apiversion.insert.*`
says, and a method without one sends the group's `apiversion.default`.
With a `RestClient`, the same is `apiVersionInserter(...)` and
`defaultApiVersion(...)` on the builder, `apiVersion(...)` on a call:

```dart
@GetExchange.of(url: '/stock/{sku}', version: '2.0')
Future<Level> level(@PathVariable() String sku);

await rest.get().uri('/stock/{sku}', sku).apiVersion('2.0').retrieve().body<Level>();
```

A version on a client without an inserter fails the call with a
`StateError`, as Spring's.

**What a method returns** decides what is read of the answer:

| Return type | Reads |
|---|---|
| `Future<T>` | the body as `T` (`List<Book>`, `Map<String, int>`, an enum...) |
| `Future<void>` | the status only |
| `Future<ResponseEntity<T>>` | the status, the headers and the body (`ResponseEntity<void>`: no body) |
| `Future<HttpHeaders>` | the headers |
| `EventStream<T>` | the server-sent events, their data as `T` |
| `Stream<List<int>>` | the bytes of the body as they arrive |

**Request attributes.** An annotation extending `HttpRequestAttribute`,
on the interface or on a method, sets a request attribute on each call,
which the interceptors read and which is never sent (the OAuth2 client's
`@ClientRegistrationId('github')` picks the registration whose token goes
with the call). A method's attribute replaces the interface's of the
same name.

```dart
class Tenant extends HttpRequestAttribute {
  const Tenant(String id) : super('tenant', id);
}

@HttpExchange('/orders')
@Tenant('neon')
abstract interface class OrderService { ... }
```

**Advice.** The client is a bean like any other, with a proxy for the
advice on the interface's methods. With `spring.resilience.enabled: true`
in `application.yml`, `@Retryable` retries a call:

```dart
@GetExchange('/{isbn}')
@Retryable(includes: [ResourceAccessException], maxRetries: 2)
Future<Book> find(@PathVariable() String isbn);
```

**What the generated class looks like**, for `find` and `search` above
(in `<library>.spring.dart`):

```dart
class _$BookServiceHttpService implements BookService {
  _$BookServiceHttpService(this._rest);

  final RestClient _rest;

  @override
  Future<Book> find(String isbn) => _rest
      .get()
      .uri(r'/books/{isbn}', {r'isbn': isbn})
      .retrieve()
      .body<Book>();

  @override
  Future<List<Book>> search(String q, {int? year}) => _rest
      .get()
      .uri(
        (UriBuilder uri) => uri
            .path(r'/books')
            .queryParam(r'q', q)
            .queryParamIfPresent(r'year', year)
            .build(),
      )
      .retrieve()
      .body<List<Book>>(const ListType<Book>(ClassType<Book>()));
}

// The bean, on the client of its group:
BeanDefinition<BookService>(
  name: r'bookService',
  create: (r) => _$BookServiceHttpService(
    r.dependency<HttpServiceGroups>().restClient(r'catalog'),
  ),
  ...
)
```

**Build errors.** What cannot work fails the build, naming the method and
what to write instead:

- a `{variable}` of the URL that no `@PathVariable` fills (with a
  did-you-mean), and a `@PathVariable` whose `{variable}` the URL lacks;
- a parameter with no role, or with two;
- a `@RequestBody` (or parts, or a form) on a `GET` or `HEAD`; two
  `@RequestBody`; `@RequestPart` with a `@RequestBody`, or with a content
  type that is not multipart; a form content type with a `@RequestBody`;
- a nullable `@PathVariable`; a header or cookie that is no text (a
  `String`, number, `bool`, enum, `DateTime` or a list of them);
- a `Map` parameter whose keys are no `String`, whose values are no text
  or may be `null`, or, for path variables, are lists; an `HttpHeaders`
  parameter without `@RequestHeader()`; a wildcard `_` parameter;
  `@RequestAttribute` on a method without an exchange annotation (a
  controller's handler); a `UriBuilderFactory` with a whole URL or a `Uri`
  parameter;
- a method without an exchange annotation, with two, or with a server's
  mapping (`@GetMapping`: write `@GetExchange`); a method with a body, a
  getter or a field; a generic method;
- a return type no call gives (above);
- an API `version` with a `${...}` placeholder (Spring sends it as
  written: set the group's `apiversion.default`) or a control character;
- a `basePackages` entry that is no `package:` prefix or names another
  package, a `basePackageClasses` type of another package, an entry that
  finds no interface;
- a listed type that is not an `abstract interface class`, or is generic,
  or carries an annotation whose starter implements it too (one marked
  `@InterfaceProxy`); an interface imported into two groups;
- in an application, an interface with exchange annotations that no
  `@ImportHttpServices` imports (it would be no bean). An interface of a
  library is left to the applications that import it.

Compared with Spring: `basePackages` names library URI prefixes and is
read by the build, not scanned on the classpath when the application
starts; `Map<String, List<T>>` stands for `MultiValueMap`, and a
`@RequestHeader() HttpHeaders` for the `MultiValueMap` of headers Spring 6
took (Spring 7's `HttpHeaders` is no `MultiValueMap`).

The [example](example/example.dart) calls a catalog through an HTTP
service, and [test/http_services_test.dart](test/http_services_test.dart)
covers every parameter role and return type.
