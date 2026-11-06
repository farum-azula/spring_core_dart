## 0.7.1

### Changes

- Static resources, as Spring Boot's `ResourceHttpRequestHandler`: the files of `lib/resources/static/` and `lib/resources/public/` (embedded by the generator) and of `file:` directories read at run time (an AOT executable's files, a `flutter build web` output) are served under `/**`, after the controllers. `spring.web.resources.static-locations`, `add-mappings`, `cache.period`, `cache.use-last-modified`, `cache.cachecontrol.*`, `chain.compressed` (precompressed `.br` / `.gz` with `Content-Encoding` and `Vary: Accept-Encoding`), `spring.mvc.static-path-pattern` and `server.mime-mappings`. Answers: `Content-Type` by extension with `X-Content-Type-Options: nosniff`, a weak `ETag` and `Last-Modified` with `304`, `Cache-Control`, `Range`, `HEAD`; `OPTIONS` gets `Allow`, other methods a 405; `index.html` is the welcome page at `/` for clients that take HTML. `spring.web.resources.spa-fallback` (this starter's own key) answers a browser's deep link of a single-page app with `index.html`.
- `WebMvcConfigurer.addResourceHandlers` with `ResourceHandlerRegistry` / `ResourceHandlerRegistration` (locations, `setCachePeriod`, `setCacheControl`, `setUseLastModified`, `setCompressed`) adds mappings; one with the default's pattern replaces it. `ResourceHttpRequestHandler` and the `resourceHandlerMapping` bean (`ResourceHandlerMapping`, order `Ordered.lowestPrecedence - 1`) are public.
- The static resources fail closed: a path is decoded once and refused (404) for dot segments, encoded or doubly encoded separators and dots, backslashes, invalid or overlong UTF-8, control characters, `;` and empty segments, Windows' device names, short names, streams and trailing dots, look-alike characters, `WEB-INF` / `META-INF`, and dot files (except `.well-known/`, whose `apple-app-site-association` is sent as `application/json`). A file is resolved with its symbolic links and refused when it leaves its location or is not a regular file; directories are never listed. The global CORS rules apply to them; filters (the security chain) run before them.
- `ResponseWriter.checkNotModified` (Spring's `checkNotModified`) is public, and `writeResource` takes `conditional: false` for a caller that checked the conditions itself; `If-Range` then also matches a strong `ETag`.
- The handlers for the actuator's `mappings` endpoint, in Spring WebFlux's shape: the `dispatcherHandlersMappingDescriptions` bean (`DispatcherHandlersMappingDescriptions`, `dispatcherHandlers` → `webHandler`) lists every handler of every `DescribableHandlerMapping` of the dispatcher: the controllers' request mappings (`predicate` as Spring's `RequestMappingInfo.toString()`, `handler`, `details.handlerMethod`, `details.requestMappingConditions`) and the static resources (`ResourceWebHandler [...]`, the welcome page, the single-page app's fallback). `describeRequestMapping` writes one entry of that shape.
- `spring.web.resources.directory-index` (this starter's own key, off by default): a path with no file whose folder holds an `index.html` gets that file (`/guide` and `/guide/` get `guide/index.html`), before `spa-fallback`, as static hosts answer; the pages of `spring.flutter.web.seo.*` are served at their addresses this way. The file is looked up with the same checks as any static resource.
- Fix: a `Range` header whose positions are not plain decimal digits (a sign, another base) is malformed and answered with the whole content; one such header could make a range that starts after the content and end the answer with an error instead of a response.
- Fix: `Range: bytes=500-` past the end of a resource is a 416, not the whole content.

## 0.7.0

- No changes of its own: its generated code (`lib/spring_gen/`) is regenerated with spring_core_dart_generator 0.7.0.

## 0.6.3

### Changes

- The editor metadata of `server.*`, `spring.web.multipart.*`, `spring.mvc.*`, `spring.main.web-application-type`, `spring.test.web-environment` and `local.server.port` is made from code and the starter reads the same classes: `ServerSettings` (`ssl`, `compression`, `websocket`, `session`, `forward-headers`; `Shutdown`, `ClientAuth`, `ForwardHeadersStrategy` and `SessionSameSite` are enums), `MultipartSettings`, `MvcSettings`, `WebMainSettings`, `WebTestSettings` and `LocalServerSettings` are bound by the Binder; `ServerProperties.of`, `HttpSessionProperties.of` and `MultipartProperties.of` bind them, and `.from` builds the settings from the bound classes. The hand-written `spring_metadata_additional.json` is gone. `spring.mvc.log-request-details` is now in the metadata; the constants `webEnvironmentProperty` and `logRequestDetailsProperty` are gone. A value that does not fit (a port that is not a number, an unreadable `server.session.max-sessions`) now fails the binding naming the property.

## 0.6.2

- feat: 0.6.2 — the theme (typed keys and messages, states, every component, a theme from a URL), (#20)

## 0.6.1

- feat(flutter): the desktop window from properties — title bar, initia… (#18)

## 0.6.0

### Breaking

- Properties renamed: `spring.servlet.multipart.*` is `spring.web.multipart.*`; `server.servlet.context-path` is `server.context-path` and `server.servlet.session.*` is `server.session.*` (there is no servlet container). An old name stops the start, naming the new one. The Boot 1 key `server.context-path`, which was read when `server.servlet.context-path` was not set, is now the key itself.

### Changes

- `server.request-timeout`, a deadline for every request (no limit by default, `0` or less: none; an extension, Spring Boot has no such key): the filters and the handler run under a `RequestDeadline` of that length, and when it passes before the answer starts the answer is a `503 Service Unavailable` problem (`AsyncRequestTimeoutException`, a generic detail, logged as a warning at most every 10 seconds). What the handler does afterwards is dropped (no second answer, no unhandled error); a response already committed is left alone; a response that becomes a stream (server-sent events, `SseEmitter`, a streamed body) leaves the deadline when it starts, and a WebSocket handshake is not timed. Code the request calls can read the deadline (`RequestDeadline.current`), and an error that ends a request after its deadline, or a `RequestDeadlineExceededException`, is a 503 instead of a 500. `AsyncRequestTimeoutException` takes an optional detail.
- `HandlerExceptionResolver`, Spring's extension point for turning an error into an answer: a bean returns an `ErrorResponse` (status, headers and problem) or `null` to pass the error on. The resolvers are asked in `@Order` after the `@ExceptionHandler` methods of the controller and of the `@ControllerAdvice` beans (the application's handlers always win) and before the default 500; not for an error that is already an `ErrorResponse` or that a filter throws; a resolver that throws is logged and skipped. A library maps its exceptions to HTTP with it: with `spring_boot_starter_data` among the dependencies the generator adds one, so an `OptimisticLockingFailureException` and a `DuplicateKeyException` are a 409 and an `EmptyResultDataAccessException` a 404 (see the data starter).
- The framework logs its main steps as Spring does, so `logging.level.root=debug` (or `logging.level.web=debug`) shows what happens: `GET "/api/books", parameters={masked}`, `Mapped to BookController#search()`, `Completed 200 OK` and `Resolved [Type: detail]` for the dispatcher; `N mappings in 'requestMappingHandlerMapping'` at debug and each mapping at trace; created, invalidated and re-keyed sessions (never their ids); the forwarded headers applied (scheme and host only); the parts and bytes of a multipart request. Parameters show as `masked`, and headers (trace) as `{masked}`, unless `spring.mvc.log-request-details=true`; even then `Authorization`, `Cookie`, `Set-Cookie` and any header or parameter whose name contains `token`, `secret`, `key`, `password` or `session` stay `masked`. Paths, parameter values and other client text go through `LogFormatUtils.formatValue`: line breaks show as `<EOL>`. The query string is not logged in the request line (parameters are, when allowed), unlike Spring.

### Fixes

- `@RequestParam` and `@RequestHeader` on a `Map` (every query parameter or header) answered 500 when the map was typed (`Map<String, String>`, `Map<String, List<String>>`, `Map<String, int>`): the map is now built with the parameter's own key and value types; the same for a form read into a `Map` with `@RequestBody`.

## 0.5.0

### Breaking

- `@CrossOrigin()` without `methods` allows only the method the handler is mapped to, as in Spring (it allowed `GET`, `HEAD` and `POST`): a cross-origin `HEAD` to a `@GetMapping` needs `methods: ['GET', 'HEAD']`.
- Every cross-origin request is checked as Spring's `DefaultCorsProcessor` checks it, its own method included: an allowed origin's `DELETE`, `PUT`, `HEAD` or `OPTIONS` that the rules do not list is a 403 before the handler runs, with or without a pre-flight.
- Only the bean named `corsConfigurationSource` is a CORS source, as in Spring Security (a `CorsConfigurationSource` bean of another name is ignored, and several such beans no longer fail the start). It is no longer combined with `@CrossOrigin` or the `WebMvcConfigurer` mappings: where it has a configuration for a request, that configuration alone applies, with and without the security starter. Where it has none, `@CrossOrigin` and the mappings apply.
- Answers whose type the app didn't set have no `Content-Type` (dart:io's `text/plain; charset=utf-8` default is gone); 1xx, 204 and 304 answers have no `Content-Length` or `Transfer-Encoding`, a 304 or 1xx no `Content-Type`, and a body written to them is dropped, as Tomcat does.
- `*` in the allowed origins together with `allowCredentials` or `allowPrivateNetwork`, also inside a comma-separated value, stops the startup for a `@CrossOrigin` and makes the requests a 500 for a mapping or a bean, as in Spring.
- CORS origin patterns are compared with case (origins without), by `AllowedOrigins`.
- Every answer of a handler with CORS rules gets `Vary: Origin, Access-Control-Request-Method, Access-Control-Request-Headers`, a CORS request or not, as Spring adds it; a handler's own `Vary` (of a `ResponseEntity` or an `ErrorResponse`) is merged with these names instead of replacing them.
- A pre-flight to a mapped path without CORS rules, and one from the server's own origin, gets a 200 without CORS headers (was a 403), as in Spring; a pre-flight for a method no handler of the path maps is decided by the global rules alone (a 403 when they refuse it, never a 405).
- An `Origin`, or a pre-flight's requested method or headers, with a character outside visible US-ASCII is a 403 (was a 500 with a stack trace).
- A `ResponseEntity` with a status of 200 and an `ETag` or `Last-Modified` answers a conditional `GET` or `HEAD` with a 304 (or a 412 for `If-Unmodified-Since`), as Spring's `HttpEntityMethodProcessor`.
- A `@RequestBody` object in a request without a `Content-Type` is a 415, as Spring reads such a body as `application/octet-stream` (it was read as JSON); a `Content-Type` that is not a media type is a 415 too.
- `server.max-http-request-body-size` limits every body, `multipart/*` ones included (the media type is checked before the body is read); only the multipart resolver reads uploads with `spring.servlet.multipart.max-request-size` instead.
- A multipart request may have at most 50 parts (`spring.servlet.multipart.max-part-count`, `-1`: no limit; Tomcat's default in Boot 4); more is a 413.
- The server answers a 400 before any filter, as Tomcat does, for an encoded `/`, `\` or NUL in the path (`%2F`, `%5C`, `%00`), a `.` or `..` segment behind matrix parameters (`/files/..;/secret`), a `%` escape in the path or the query that is not UTF-8, and a malformed or missing `Host` (or an absolute target naming another host); a form with a malformed `%` escape is a 400 too.
- WebSocket server sessions read at most 8 KB per message, as Tomcat in Spring (`server.websocket.max-text-message-size` and `max-binary-message-size`; above, the session closes with 1009), negotiate no permessage-deflate, and drop a client that takes nothing past 512 KB waiting or 10 seconds (`server.websocket.send-buffer-size-limit` and `send-time-limit`; 4500), as Spring's `ConcurrentWebSocketSessionDecorator`.
- `@ControllerAdvice` beans are tried in `@Order`, as in Spring: the first bean with a handler for the error answers it, even when a later bean has a more specific one.
- A request body that sends nothing for `server.connection-timeout` (60 s, Tomcat's default; `0` or less: no limit) ends with a 408, and idle keep-alive connections close after the same time.
- At `server.servlet.session.max-sessions` the in-memory repository removes every expired session and, when it is still full, refuses the new session with a `TooManyActiveSessionsException` (503), as WebFlux's `InMemoryWebSessionStore` does; a live session is never pushed out for a new one. The constants `InMemoryHttpSessionRepository.loginAttribute`, `principalNameAttribute` and `principalKeyAttribute` are removed. The security starter creates a session only at a login, so anonymous requests cannot fill the store.

### Changes

- `server.forward-headers-strategy` (`native` or `framework`, Spring Boot's) adds `ForwardedHeaderFilter`, first of all filters: behind a reverse proxy the request gets the scheme, host, port and client address of `Forwarded` (RFC 7239) or `X-Forwarded-Proto`, `-Host`, `-Port` and `-For`, so cookies get `Secure` behind a TLS proxy and redirect URIs are `https://`. Only from the proxies of `server.forward-headers.trusted-proxies` (loopback and private networks by default, as Tomcat's `RemoteIpValve`; Spring's filter believes every peer); the client's address is the first from the right that is not a trusted proxy; invalid values are ignored; the headers are removed for the rest of the chain. `X-Forwarded-Prefix` is not read.
- The private directory of the uploads' temporary files is `rwx------` on Linux too (dart:io's `createTemp` made it `rwxr-xr-x` there, readable by every user of the machine; on macOS it was already private). When it can't be made private, the upload fails.
- `DispatcherHandler.corsConfigurationFor(request)` gives the CORS rules of the mapping that would take a request, in the dispatcher's order (Spring's `HandlerMappingIntrospector`): a WebSocket handshake gets the `corsConfigurationSource` bean's rules or none, never the `WebMvcConfigurer` mappings.
- A port in use fails the start, as in Spring Boot: the application waits for the server to listen before the `ApplicationStartedEvent`, the runners and the `ApplicationReadyEvent`, `runAsync` throws the `PortInUseException`, and the program ends with a non-zero exit code.
- Graceful shutdown lets running requests finish within `spring.lifecycle.timeout-per-shutdown-phase` before the beans are destroyed (the lifecycle processor now has that timeout too).
- An upload that fails inside a part (a limit, a broken body, a client that went away) is answered (413 or 400) instead of hanging, and its temporary files are deleted at once.
- Uploads go to a private directory of the process (`0700`, random file names), made again when the system cleans its temporary directory.
- `@CrossOrigin` defaults no longer widen the global CORS rules, as Spring's default markers: `@CrossOrigin(methods: ['PUT'])` under `/api/**` keeps the global origins and adds `PUT`.
- `allowPrivateNetwork` on `@CrossOrigin`, `CorsConfiguration` and `CorsRegistration` answers Chrome's Private Network Access pre-flights with `Access-Control-Allow-Private-Network: true`; `CorsConfiguration.validateAllowCredentials()` and `validateAllowPrivateNetwork()` are Spring's checks.
- CORS origins are checked by `AllowedOrigins`: port lists (`http://localhost:[3000,3001]`, `[*]`), comma-separated values and a trailing `/`, as in Spring. Differs from Spring: an `Origin` longer than 1024 characters is never allowed (a pattern with several `*` froze the server on a large `Origin`).
- A pre-flight is answered from the CORS rules of the first handler of its path and method, and an actual request from those of the handler that answers it, chosen with all its conditions. Differs from Spring when several handlers match a pre-flight equally: Spring allows it from any origin, here the other handlers' origins get a 403 (give such handlers the same rules).
- Event streams (`Stream`, `EventStream`, NDJSON) are paused while an event is written, so a client that reads slowly slows the stream down instead of filling the server's memory; an `SseEmitter` whose unawaited sends reach 1000 for a client that reads nothing fails the next `send` with a `StateError` and ends.
- `ResponseEntity<SseEmitter>`, `ResponseEntity<EventStream<T>>` and `ResponseEntity<Stream<T>>` write their events with the entity's status and headers.
- Compression covers every response of `server.compression.mime-types` (Spring Boot's list) of at least `server.compression.min-response-size` (2 KB), not only byte streams; never one with a strong `ETag`; and every answer that could be compressed gets `Vary: Accept-Encoding`, also for a client without gzip, as Tomcat.
- A body the handler does not read (an upload answered with a 413 or 415) gets its answer first; then up to 2 MB are read and dropped, for at most 5 seconds, as Tomcat's `max-swallow-size`, so the connection can serve the next request.
- A handler that fails after the response was committed drops the connection without finishing the response, as Tomcat does (the response looked complete).
- A response header `dart:io` cannot send (non-ASCII, a line break) is dropped and the error answered with a 500 problem (was an empty 200).
- The server answers the WebSocket handshake itself: a missing, repeated or malformed `Sec-WebSocket-Key` is a 400, another `Sec-WebSocket-Version` a 426.
- A 5xx answer an exception asks for (a `ResponseStatusException`, the 503 of a refused session) is logged as a warning without a stack trace, at most once every 10 seconds for the same kind; an unexpected exception is logged with its stack trace.
- `ServerProperties` has the new settings: `compressionMimeTypes`, `compressionMinResponseSize`, `connectionTimeout`, `webSocketMaxTextMessageSize`, `webSocketMaxBinaryMessageSize`, `webSocketSendBufferSizeLimit`, `webSocketSendTimeLimit`.

## 0.4.3

- Flutter security (#15)
- feat: single sign-on with OAuth 2.0 / OpenID Connect (spring_boot_sta… (#11)
- docs: the READMEs and docs/ rewritten: what it is, why and when you need it, an example, then Spring (#10)

## 0.4.2

- Docs (#9)

## 0.4.1

- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs
- feat: guides replace the examples; optional parameters from Dart nullability; coloured logs

## 0.4.0

- `HttpSession`: `request.getSession()`, an in-memory `HttpSessionRepository` with expiry and a limit (`server.servlet.session.timeout`, `.max-sessions`, `.cookie.*`; `SameSite=Lax` by default), `changeSessionId()`; the session cookie is written by `HttpSessionFilter`.
- `@RequestParam` reads the fields of `application/x-www-form-urlencoded` bodies too, like Spring MVC (`readFormParameters`).
- A request target starting with `//` is no longer read as a host by `dart:io`: the path keeps its `//` (and is answered 404, or refused by the security starter's firewall).

## 0.3.2

- Initial version: Spring MVC for Dart. `@RestController` classes with `@GetMapping`, `@PostMapping`, ... on `dart:io`'s `HttpServer` (`server.*` properties), path variables, request parameters, headers and cookies, JSON bodies through the `ObjectMapper`, `@Valid` bodies, `ResponseEntity`, errors as `ProblemDetail` with `@ExceptionHandler` and `@RestControllerAdvice`, server-sent events (`EventStream`, `SseEmitter`), filters, interceptors, CORS, WebSocket endpoints of `spring_boot_starter_websocket` on the same server; `MockMvc` and `springBootTest(webEnvironment:)` in `spring_boot_starter_test`.
