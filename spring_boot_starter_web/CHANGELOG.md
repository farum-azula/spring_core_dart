## Unreleased

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

### Changes

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
- At `server.servlet.session.max-sessions`, a new session takes the place of an expired one, then of one its client never came back with, then of the least recently used one without a login; a login goes only for the user who holds the most sessions (two or more), else the new session is refused with a `TooManyActiveSessionsException` (503), as Tomcat refuses sessions above its limit. Anonymous requests can no longer log everyone out.
- `InMemoryHttpSessionRepository.principalNameAttribute` and `principalKeyAttribute` (set by the security starter at each login) tell the users apart for that limit; `loginAttribute` marks a logged-in session.
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
