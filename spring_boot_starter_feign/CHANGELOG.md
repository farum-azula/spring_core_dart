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
