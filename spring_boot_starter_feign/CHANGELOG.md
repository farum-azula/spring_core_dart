## 0.5.0

### Changes

- The `headers` and `full` logs show the values of `Proxy-Authorization`, `Cookie` and `Set-Cookie` as `***` too, in requests and responses, next to `Authorization` and `DPoP`.
- `spring.cloud.openfeign.client.config.<name>.sensitive-headers` names more headers to mask in the logs, such as `X-Api-Key` (this starter's addition; Feign's logger masks none).
- `FeignException.toString()` shows a preview of the body as Feign's message does (the whole body under 400 bytes, else its first 200 characters and its size); `responseBody` keeps all of it.
- A negative `Retry-After` (`-5`) leaves the error not retryable, as in Feign, and a huge one waits at most a year (both gave a zero delay).
- A `@PathVariable` value `.` or `..` (or one with such a segment between slashes) throws an `ArgumentError`: Dart's `Uri` would drop it and call another path. Differs from Feign, which sends it as it is.

## 0.4.3

- Flutter security (#15)
- feat(security): spring_boot_starter_flutter_security — app login on e… (#13)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- feat: spring_security_core, spring_boot_starter_security and a CI quality gate

## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds
- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- **Brings logging, like every Spring Boot starter:** depends on and re-exports `spring_boot_starter_logging` (and through it `spring_boot_dart` and `spring_core_dart`), so the starter is the only dependency an application lists, and one import gives everything. An application using it now gets the logging system (Boot's console format, `logging.*` properties) without adding the logging starter; `logging.enabled=false` turns it off.
- The example is a Spring Boot application: a `@FeignClient` against a local server (a book, a 404 as `null`, a search, an event stream).
- Tests take `MockHttpTransport` from `spring_boot_starter_test` (README).
- `spring_auto_configuration.dart` re-exports the logging starter's (and through it `spring_boot_dart`'s) auto-configuration, so a test naming `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other dependency.

## 0.3.0

- feat(spring_boot_starter_flutter): themes from properties, free reads in Spring widgets

## 0.2.3

- add spring application handling
- docs(spring_boot_starter_flutter): add an example for pub.dev

## 0.2.2

- ci: run only the tests of the packages a change affects

## 0.2.1

- feat: spring_boot_starter_flutter, @Log, --dart-define properties, Flutter counter example

## 0.2.0

- the auto-configured `httpTransport` backs off for an `HttpTransport` registered by an `@Import`ed `BeanRegistrar` / `ImportBeanDefinitionRegistrar` of the application (two transports failed the start); its condition is decided when the auto-configuration is read, like Boot's `OnBeanCondition`
- `dismiss404`, `follow-redirects`, `event-stream.reconnect` and `spring.cloud.openfeign.client.decode-slash` take true / false in any case (and on / off, yes / no, 1 / 0); anything else fails naming the key (`yes` was off for `dismiss404`, `nope` was on for the others).
- Form bodies: with `consumes: application/x-www-form-urlencoded` (or that `Content-Type` header) a `Map` or object body is sent as `name=value&...` like Spring Cloud OpenFeign's `SpringFormEncoder` (it was sent as JSON).
- `Future<ResponseEntity<void>>` ignores the body (a non-JSON body failed the call).
- `Future<HttpResponse>` returns the raw response for any status, without error decoding, like Feign's `Response`.
- A `request-interceptors` bean that is also a `RequestInterceptor` bean of the context runs once.
- `@FeignClient(configuration: [...])`: the `Retryer`, `ErrorDecoder` and `RequestInterceptor` beans of the listed `@Configuration()` classes apply to that client only (and never reach the other clients); properties `retryer`, `error-decoder` and `request-interceptors` of `spring.cloud.openfeign.client.config.<name>` (bean or class names) win over them.
- Breaking: `default-request-headers` is a `Map<String, List<String>>` and both `default-request-headers` and `default-query-parameters` are bound through the Binder: `X: a,b` and YAML lists (`X[0]`, `X[1]`) give several values (lists were sent as a header `X.0`).
- Breaking: `DefaultRetryer` waits 150 ms, 225 ms, ... (period × 1.5^attempt) like Feign's `Retryer.Default` (it started at 100 ms).
- Breaking: `BasicAuthRequestInterceptor` encodes ISO-8859-1 like Feign (`encoding: utf8` for other characters).
- A client `url` without a scheme gets `http://`; `@FeignClient(url: '')` (or a placeholder resolving to empty) falls back to the `url` property.
- A query written in a mapping path (`@GetMapping('/items?type=a%20b&flag')`) is sent as written; the call's parameters are appended.
- Breaking: `FeignClientFactory` looks up the interceptors, error decoder and retryer per client; its `interceptors` / `errorDecoder` / `retryer` arguments are optional overrides.

## 0.1.7

- `@GetMapping()` without a path calls the `url` and `path` of the client itself.
- `required` and `defaultValue` of `@RequestParam` / `@RequestHeader` and `required` of `@PathVariable`: `defaultValue` is sent for a `null` argument; a required `null` fails the call with an `ArgumentError` naming the parameter before anything is sent; a `null` that is not required leaves a query parameter or header out (a path variable becomes an empty string).
- `spring.cloud.openfeign.client.config.*` keys with relaxed names, like Spring Cloud OpenFeign's binding: `readTimeout`, `loggerLevel`, `defaultRequestHeaders.X-Shop`, `read_timeout`, environment variables
- Breaking: `Map` parameters of `@RequestParam` / `@RequestHeader` give one query parameter / header per entry (they were sent as JSON); an object as the value of a path variable, query parameter, header or cookie (a class written as a JSON object) stops the application at startup, or fails the call with an `EncodeException` when only the value tells.
- Breaking: mapping `headers` use Spring's `'Name=value'` (as Spring Cloud OpenFeign reads them; server conditions like `'!Name'` are ignored); `'Name: value'` stops the application with the reason.
- Breaking: `read-timeout` is the longest wait for data (for the response, then between two chunks of the body), not a limit for the whole call; default `read-timeout` 60 s and `connect-timeout` 10 s, like Feign's `Request.Options()` (`0` for none).
- Breaking: `RequestTemplate.header` adds a value like Feign's (it replaced); new `removeHeader`. Interceptors run for every attempt of a call on a new template (a refreshed token reaches the retry); `default-request-headers` (and the default `Accept`) are applied after the interceptors, for names they did not set.
- Breaking: `dismiss404` keeps throwing for `void` methods, like Feign.
- Breaking: the `<--- ERROR` and `---> RETRYING` log lines are written only above `logger-level: none`.
- `@FeignClient(contextId:, qualifiers:, primary:, dismiss404:)` like Spring Cloud OpenFeign (`primary` and `qualifiers` need the matching generator).
- `default-query-parameters.<name>`, `follow-redirects`, `spring.cloud.openfeign.client.decode-slash` (default `true`: a `/` in a path variable stays a `/`).
- `@CookieValue` parameters (one `Cookie` header).
- `DefaultErrorDecoder` reads `Retry-After` as an HTTP date too.
- README: more "Differences from Spring Cloud OpenFeign" (default `Accept`, spaces as `+`, masked `Authorization`, logger names).

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- Initial version: @FeignClient interfaces with request mapping annotations, JSON through ObjectMapper, interceptors, error decoding, retries, fallbacks, spring.cloud.openfeign.client.config.* properties.
- Server-sent events: methods returning `EventStream<T>` (or `Stream<T>`) read `text/event-stream` responses, decode each event's data, reconnect with `Last-Event-ID` (`event-stream.*` properties; not in Spring Cloud OpenFeign).
