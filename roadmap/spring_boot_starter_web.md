# spring_boot_starter_web

The server side of `spring_web_dart`: Spring MVC controllers with the
mapping annotations Feign clients already use (`@GetMapping`,
`@PathVariable`, `@RequestBody`, ...), server-sent events, WebSocket
endpoints, filters and `ProblemDetail` errors. Runs on the VM and inside
Flutter apps on mobile and desktop (a local API, a companion server, an
MCP server for AI tools); not on the web, which has no server sockets.

**First version: `dart:io`.** The server is `dart:io`'s `HttpServer`,
behind a `WebServerFactory` so another server can replace it
([Replaceable server](#replaceable-server)). The starter's core (routing,
binding, errors, `MockMvc`) never imports `dart:io`.

How to use it: the starter's [README](../spring_boot_starter_web/README.md),
[docs/testing.md](../docs/testing.md#17-web-tests-mockmvc) and the
[configuration reference](../docs/configuration.md#18-reference-web-server).

## Status

The first version on `dart:io` is done. What is left is listed under
[Left](#left) and in the sections below, where every item says whether it
exists.

### Done

- **Generator.** `BeanMethod` (`BeanDefinition.annotatedMethods`) carries
  `parameters` (names, types, annotations, named or positional, required),
  `returnTypeInfo`, `isFuture`, `isVoid` and `invokeNamed`.
  `@BeanMethodAnnotation()` methods may have required named parameters.
  The mapping annotations, `@ExceptionHandler` and the WebSocket
  `@OnOpen` / `@OnMessage` / `@OnClose` / `@OnError` are marked with it;
  the parameter and result types of the bean's package are introspected.
- **Controllers.** `@RestController` (and `@Controller`), `@RequestMapping`
  on the class as a prefix, every mapping annotation with `produces`,
  `consumes` and `headers` conditions, `${...}` in paths. Binding of path
  variables, query parameters (lists, enums, dates, durations), headers,
  cookies, JSON / `String` / bytes / streamed / form (`Map`) bodies,
  multipart parts (`@RequestPart`, files through `@RequestParam`),
  `ServerHttpRequest`, `ServerHttpResponse`, `HttpHeaders`, `HttpMethod`,
  `Uri`, `Principal`; unannotated simple values and files as request
  parameters.
  `required` / `defaultValue` / nullable / Dart defaults. `@Valid` and
  `@Validated(groups)` on bodies → 400 with the field errors.
- **Results.** Objects as JSON, `String`, `Uint8List`, `Resource`, byte
  streams, `StreamingResponseBody`, `ResponseEntity`,
  `ProblemDetail`, `ErrorResponse`, `void`; `@ResponseStatus` (with
  `reason`); content negotiation with 406 / 415; `HEAD` and `OPTIONS`
  answered automatically; 404 / 405 with `Allow`.
- **Startup checks.** A `{variable}` without `@PathVariable`, a parameter
  without a role, two bodies, ambiguous mappings, an invalid
  `@ExceptionHandler` or `produces`: the application stops with the list.
- **Errors.** `ProblemDetail`, `ErrorResponse`, `ErrorResponseException`,
  `ResponseStatusException` (in `spring_web_dart`); `@ExceptionHandler` on
  controllers and `@ControllerAdvice` / `@RestControllerAdvice` in
  `@Order`; unknown exceptions → 500 without details, logged.
- **Streaming.** `EventStream<T>` / `Stream<T>` results as server-sent
  events (any method, `POST` included), NDJSON with
  `produces: application/x-ndjson`, `SseEmitter` (buffering, timeout from
  `spring.mvc.async.request-timeout`, callbacks), heartbeats
  (`spring.mvc.sse.heartbeat-interval`), `Last-Event-ID` through
  `@RequestHeader`, streams closed on shutdown.
- **Files.** Multipart uploads (`MultipartFile`, `@RequestPart`,
  `spring.servlet.multipart.*`, temporary files), `Resource` downloads
  with `Range` / `Last-Modified`, byte streams and
  `StreamingResponseBody`; see [Files](#files-multipart-resources-byte-streams).
- **Filters, interceptors, CORS.** `WebFilter` beans in `@Order`,
  `OncePerRequestFilter`, request / response decorators;
  `WebMvcConfigurer` with `HandlerInterceptor`s (path patterns), CORS
  mappings and argument resolvers; `@CrossOrigin`, a
  `CorsConfigurationSource` bean, `UrlBasedCorsConfigurationSource`,
  pre-flight requests.
- **Server.** `WebServer`, `WebServerFactory`,
  `ConfigurableWebServerFactory`, `WebServerFactoryCustomizer`,
  `IoWebServerFactory` (`@ConditionalOnMissingBean`); `server.port` (0),
  `server.address`, `server.shutdown`, `server.ssl.*` (PEM, client
  certificates), `server.servlet.context-path`,
  `server.max-http-request-body-size` (413), `server.compression.enabled`;
  `WebServerStartStopLifecycle` with graceful shutdown within
  `spring.lifecycle.timeout-per-shutdown-phase`;
  `WebServerInitializedEvent`, `local.server.port`;
  `PortInUseFailureAnalyzer`; `spring.main.web-application-type=none`.
- **Dispatcher.** Each request in its own `Zone`
  (`RequestContextHolder`), filters, then the `HandlerMapping` beans in
  order (controllers 0, WebSocket 1). `PathPattern` lives in
  `spring_web_dart`.
- **WebSocket endpoints** (in `spring_boot_starter_websocket`, served when
  the application lists this starter too): see
  [WebSocket endpoints](#websocket-endpoints).
- **Flutter.** `127.0.0.1` by default, the server stops in the background
  and starts again with the context; a clear error on the web.
- **Tests.** `MockMvc` (`get`, `post`, ..., `perform`, `multipart`, `webSocket`,
  `andExpect`, `andReturn`, SSE read event by event,
  `RequestPostProcessor`), `springBootTest(webEnvironment:)`,
  `app.localServerPort`, `@SpringBootTest(webEnvironment:)`,
  `@LocalServerPort`, `@AutoConfigureMockMvc`, `@Autowired MockMvc`;
  `ApplicationContextRunner` starts no server by default.

### Left

- `@ConditionalOnWebApplication` / `@ConditionalOnNotWebApplication`.
- Files, the rest: several byte ranges (`multipart/byteranges`), `ETag`
  for resources, streamed uploads in Feign, `@RequestPart` with
  `multipart/mixed` — see *Files* below.
- `ResponseBodyEmitter`, `@ModelAttribute` (form binding to objects),
  `HttpSession`; views and static resources (*MVC* below, to
  investigate).
- Filters with URL patterns (`FilterRegistrationBean`-like),
  `spring.web.cors.*`.
- Static files, forwarded headers, `server.max-http-request-header-size`,
  timeouts, `server.compression.*` beyond `enabled`.
- Flutter: blocking warnings, JSON offload, `server.isolate: background`,
  platform checks at startup, hot restart and the port.
- Other servers (`shelf`, Rust), HTTP/2.
- Test slices (`@WebMvcTest`); replacing the examples' hand-written
  `dart:io` stand-in servers (the `spring_web_dart` example and tests)
  with controllers.
- Later: STOMP, the [actuator](spring_boot_actuator.md) over HTTP, the
  [security starter](spring_boot_starter_security.md), the
  [MCP server](spring_ai_mcp.md).

## Controllers

Done (see [Done](#done)). Left:

- **Form binding to objects** (`@ModelAttribute`) and url-encoded form
  fields in `@RequestParam` (today such a body is read only into a
  `@RequestBody() Map`; multipart text fields are `@RequestParam`s
  already).
- **`@ResponseStatus` on exception classes** cannot be read at runtime;
  the generator could describe the exceptions of the package (as it does
  for JSON models).

## Streaming: SSE, emitters, bodies

Done: `EventStream<T>` / `Stream<T>` results, `SseEmitter`, SSE from a
`POST`, `Last-Event-ID` (a `@RequestHeader`), heartbeats
(`spring.mvc.sse.heartbeat-interval`), NDJSON, streamed request bodies
(`@RequestBody() Stream<Uint8List>`), streams closed on shutdown;
`StreamingResponseBody` and byte stream results (see
[Files](#files-multipart-resources-byte-streams)). Left:

- **`ResponseBodyEmitter`** for other streamed formats.
- **A first event without the comment line.** `dart:io` sends the headers
  with the first body bytes, so every stream starts with `:`; a server
  that can flush headers alone would not need it.

## WebSocket endpoints

Done, in `spring_boot_starter_websocket` (`lib/src/server/`), on the same
port and the same filter chain as HTTP, so the handshake is authenticated
like any request:

- **Declarative:** `@WebSocketEndpoint(path, allowedOrigins:,
  allowedOriginPatterns:, protocols:)` beans with `@OnOpen`, `@OnMessage`
  (the client's annotation; the return value is sent back), `@OnClose`,
  `@OnError`; `@PathVariable`, `Principal`, `CloseStatus` parameters.
- **Spring's handler style:** `WebSocketHandler`,
  `AbstractWebSocketHandler`, `TextWebSocketHandler`,
  `WebSocketConfigurer` + `WebSocketHandlerRegistry`,
  `HandshakeInterceptor`s.
- **Sessions:** `ServerWebSocketSession` (id, handshake headers,
  attributes, principal, path variables, `sendJson`) and a
  `WebSocketSessionRegistry` for broadcasting.
- **Allowed origins** checked on the handshake like Spring's.
- **Tests:** `MockMvc.webSocket` in memory, real sockets with
  `WebEnvironment.randomPort`.

Left: STOMP (`@MessageMapping`, `@SendTo`), shared with the client side
([spring_boot_starter_websocket](spring_boot_starter_websocket.md)).

## Files: multipart, resources, byte streams

Done (it was the first priority of the [roadmap](README.md)); how to use
it: the starter's
[Files](../spring_boot_starter_web/README.md#files-uploads-and-downloads)
section.

- **Multipart uploads:** `MultipartFile` (name, original filename,
  content type, size, bytes, a stream, `transferTo` moving the temporary
  file), `@RequestPart` (a file, `List<MultipartFile>`, a text field,
  bytes, or a JSON part read into an object, with `@Valid`) and
  `@RequestParam` for files and text fields (like servlet parameters);
  unannotated `MultipartFile` parameters; 400 for a missing part or a
  malformed request; `spring.servlet.multipart.*` (`enabled`,
  `max-file-size`, `max-request-size` → 413, `file-size-threshold`,
  `location`): files are streamed to temporary files deleted after the
  request; `server.max-http-request-body-size` does not apply to
  multipart. The streaming parser is written here (`MultipartParser` in
  `spring_web_dart`, no third-party package in the runtime).
- **`Resource` responses**, like Spring's `ResourceHttpMessageConverter`:
  `ByteArrayResource` and `FileSystemResource` (streamed with
  `FileSystemResource.openRead(start, end)`) with the media type from the
  file name (`MediaTypeFactory`), `Content-Length`, `Last-Modified` /
  `If-Modified-Since` (304), `Accept-Ranges`, one `Range` (206, 416;
  several or malformed → the whole content), `If-Range` by date, 404 for
  a missing resource, `ResponseEntity<Resource>` with
  `Content-Disposition`.
- **Byte streams:** a `Stream<List<int>>` / `Stream<Uint8List>` result is
  written as bytes (not server-sent events), `StreamingResponseBody` with
  a `ResponseBodySink` for code that writes the body itself.
- **Tests:** `MockMvc.multipart` with `MockMultipartFile`.
- **Feign:** multipart request bodies (`@RequestPart`, `MultipartFile`),
  see [spring_boot_starter_feign](spring_boot_starter_feign.md).

Left:

- Several byte ranges in one response (`multipart/byteranges`).
- `ETag` (and `If-None-Match`) for resources.
- Streamed uploads in Feign (the multipart body is built in memory).
- `@RequestPart` with `multipart/mixed` bodies.

## MVC: views and static resources (to investigate)

Spring MVC is not only REST: a plain `@Controller` returns a view name
rendered by a template engine, and Spring Boot serves static files from
`classpath:static`. Before building it, find out whether it fits Dart:

- **Static resources** (`/**` from `lib/resources/static/`, Spring's
  `ResourceHttpRequestHandler`): embedded by the generator like the
  config files (today limited to 1 MB per file), or read from a directory
  at run time (`spring.web.resources.static-locations=file:...`) for AOT
  executables shipped with their assets? Caching (`ETag`,
  `Cache-Control`), `Range`, an `index.html` welcome page, a single-page
  app fallback, and serving a built Flutter web app from the server.
- **Views:** `@Controller` methods returning a view name or
  `ModelAndView`, a `Model` parameter, `redirect:` / `forward:`,
  `@ModelAttribute` form binding. Which template engine: Mustache
  (`mustache_template` is published by the Flutter team, so allowed), our
  own, or none (server-side HTML through a typed builder)?
- **Worth it?** Who would render HTML on a Dart server rather than with
  Flutter web or a JS front end; admin pages and the actuator's dashboard
  are the likely users. Decide after a prototype.
- **Browser SSO with it (not decided):** server-rendered pages log their
  users in on the server, Spring Security's `oauth2Login()` with OpenID
  Connect ([spring_boot_starter_security](spring_boot_starter_security.md#sso-oauth2login-with-openid-connect)).
  Without views it is not needed: apps log in on the client and send
  tokens, which the resource server already checks.

## Filters, interceptors, CORS, static files

Done: `WebFilter` beans in `@Order`, `OncePerRequestFilter`,
`HandlerInterceptor`s registered by a `WebMvcConfigurer`, `@CrossOrigin`,
`CorsRegistry`, a `CorsConfigurationSource` bean (security's `.cors()`
will reuse it), the body size limit (`server.max-http-request-body-size`),
gzip (`server.compression.enabled`). Left:

- **Filter registration** with URL patterns and an order outside
  `@Order` (`FilterRegistrationBean`).
- **`spring.web.cors.*`** properties.
- **Static files** from `lib/resources/static/` (Spring Boot's
  `classpath:static`), embedded by the generator like the config files.
  `ETag`, `Last-Modified` and `Cache-Control` from `spring.web.resources.*`.
- **Proxies:** `server.forward-headers-strategy` (`X-Forwarded-*`,
  `Forwarded`) for the scheme, host and client address behind a proxy.
- **Limits:** `server.max-http-request-header-size`, timeouts,
  `server.compression.mime-types` / `min-response-size`.

## Server and properties

Done: `server.port` (0 = random), `server.address`, `server.ssl.*` (PEM
through `SecurityContext` of `dart:io`), `server.shutdown`,
`server.servlet.context-path`; the `SmartLifecycle` with graceful
shutdown, `WebServerInitializedEvent`, `local.server.port`; the
port-in-use failure analysis; `spring.main.web-application-type=none`.
Left:

- `@ConditionalOnWebApplication` / `@ConditionalOnNotWebApplication`.
- Key stores and SSL bundles, HTTP/2 (another server).

## Replaceable server

Done: the starter's core talks to an interface, and the server behind it
can be swapped, like Spring Boot with Tomcat, Jetty, Undertow or Netty.

```dart
abstract interface class WebServerFactory {
  WebServer getWebServer(HttpHandler handler);
}

abstract interface class WebServer {
  Future<void> start();
  Future<void> stop({Duration? timeout});   // graceful within the timeout
  int get port;
}
```

- **The handler is independent of the server.** `HttpHandler` (routing,
  binding, filters, errors) works on `ServerHttpRequest` /
  `ServerHttpResponse` of `spring_web_dart`, never on `dart:io`'s
  `HttpRequest`.
- **Default:** `IoWebServerFactory` on `dart:io`'s `HttpServer`, a bean
  with `@ConditionalOnMissingBean(WebServerFactory)`.
- **Replacing it:** a `WebServerFactory` bean in the application, or a
  starter whose auto-configuration declares one first.
- **Customizing it:** `WebServerFactoryCustomizer` beans;
  `ConfigurableWebServerFactory.settings` holds `server.*`
  (`ServerProperties`).
- **`MockMvc` is one more caller** of the same `HttpHandler`, in memory.

Candidates after `dart:io` (left):

| Server | How | Dependency rule |
|---|---|---|
| `dart:io` `HttpServer` | default, done | SDK |
| `shelf` | `spring_boot_starter_web_shelf`, `shelf` middleware usable | `tools.dart.dev`, allowed |
| Rust (hyper / axum) over FFI | its own starter, with [flutter_spring_rust](flutter_spring_rust.md) | an exception in its own starter |

JVM servers (Netty, Tomcat) cannot run in a Dart process.

## Flutter

### Isolates

- **The main isolate by default** (done). `HttpServer` I/O is
  asynchronous, so the server does not block the UI, the same as the
  Feign client. Controllers use the same beans as the widgets: one state,
  nothing copied. This is enough for a local API, a companion server or
  an MCP server.
- **Heavy work.** What can drop frames is synchronous CPU work inside a
  handler: big JSON, images, hashing, compression, big sorts. Move that
  part with `Isolate.run`, later with a `TaskExecutor` pool and `@Async`
  ([spring_boot_starter_scheduling](spring_boot_starter_scheduling.md)):

  ```dart
  @PostMapping('/images')
  Future<Thumbnail> upload(@RequestBody() Uint8List bytes) =>
      Isolate.run(() => makeThumbnail(bytes));
  ```

- **Finding the heavy part** (left). Every request already runs in its
  own `Zone`; the starter will time every synchronous slice between
  `await`s there. In debug builds a slice longer than the threshold is
  logged (like Android's StrictMode); the same numbers can go to the
  actuator later.

  ```yaml
  server:
    flutter:
      blocking-warning-threshold: 8ms   # 16 ms per frame at 60 Hz, 8 at 120 Hz
  ```

  ```
  WARN GET /api/books/export blocked the main isolate for 41 ms
       (frame budget 16 ms); move the heavy part to Isolate.run
  ```

- **Big JSON bodies off the main isolate** (left). The starter decodes
  them itself, so it can choose by `Content-Length`. `Isolate.run` returns
  the result through `Isolate.exit`, without copying it.

  ```yaml
  server:
    json:
      offload-threshold: 256KB
  ```

- **Later: `server.isolate: background`.** The whole server in a
  background isolate, for heavy servers.
  - Beans cannot be shared across isolates, so the isolate runs a second
    context with the server's own beans, like Spring Boot's separate
    management context.
  - The UI and the server talk through a bridge of `ApplicationEvent`s.
  - Plugins in that isolate need `BackgroundIsolateBinaryMessenger`.

### Lifecycle

Done: the server is a `SmartLifecycle`, so `SpringApplicationWidget`
handles it:

- **In the background:** the server stops and frees the port, and starts
  again when the app comes back.
- **On a hot reload** with changed beans: it restarts with the context.
- **When the widget is removed:** it closes.

`spring.flutter.lifecycle.pause-in-background=false` keeps it running, but
the OS decides:

- iOS suspends a background app within seconds.
- Android keeps a server alive only from a foreground service with a
  notification. That is native code; a third-party plugin would need an
  exception to the dependency rule.

Left to check: whether a hot restart (not reload) frees the port when the
isolate is replaced.

### Platforms

- **Default address in Flutter:** `127.0.0.1`, not `0.0.0.0` (done). An
  app opens a port to the network only when asked.
- **Web:** no server; the starter fails at startup with an error saying
  so (done).
- **What each platform needs** (documented; left: checking it at startup
  where possible and naming what is missing):

  | Platform | Needs |
  |---|---|
  | macOS | the `com.apple.security.network.server` entitlement |
  | iOS | binding beyond localhost asks for local network access: `NSLocalNetworkUsageDescription` |
  | Android | `INTERNET` in the release manifest |

## Ready for Spring Security

[spring_boot_starter_security](spring_boot_starter_security.md) (done)
plugs into these slots:

| Slot | Status |
|---|---|
| **A filter chain with a fixed slot.** Security registers its `FilterChainProxy` as one filter at Spring Boot's order (`SecurityProperties.DEFAULT_FILTER_ORDER`); any number of `SecurityFilterChain`s live behind it. | exists: a `WebFilter` bean with `@Order` |
| **Path patterns** shared with the router (`/**`, `{variable}`), so `requestMatchers('/api/admin/**')` matches exactly what the router maps. | exists: `PathPattern` in `spring_web_dart`; `RequestMatcher` is security's |
| **A request `Zone`.** Every request runs in its own `Zone`, where `spring_security_core` keeps the `SecurityContext`; it survives `await`, like Spring's `ThreadLocal`. | exists: `RequestContextHolder`; a WebSocket session's handlers run from the handshake's request. Carrying the context into an emitter sent to from elsewhere is security's part |
| **The request.** `ServerHttpRequest.principal` and request attributes; `Principal` resolves as a handler argument. | exists |
| **Argument resolvers** for `@AuthenticationPrincipal` and `@CurrentSecurityContext`. | exists: `HandlerMethodArgumentResolver`, asked before the built-in ones |
| **Exception translation.** `AuthenticationException` → 401 with `WWW-Authenticate`, `AccessDeniedException` → 403, both as `ProblemDetail`, from filters, handlers and method security alike. | exists: an exception implementing `ErrorResponse` (status, headers, problem) is answered that way wherever it is thrown |
| **Method security on controllers.** Handlers are invoked on the bean as the context holds it (its AOP proxy), so `@PreAuthorize` works. | exists |
| **Sessions:** an `HttpSession` abstraction (in memory first, a store later) for form login, and response cookies (`Set-Cookie` with `HttpOnly`, `Secure`, `SameSite`). | exists: `request.getSession()`, `HttpSessionRepository` (in memory, `server.servlet.session.*`), `HttpSessionFilter`; a shared store is left |
| **CSRF** needs form bodies and cookies. | exist (a form body into a `Map`, `@CookieValue`) |
| **CORS:** the `CorsConfigurationSource` bean is shared. | exists |
| **Handshakes:** WebSocket and SSE requests pass the same filter chain, so a connection carries its user. | exists |
| **Scheme and client address** (`isSecure`, `remoteAddress`), correct behind proxies, for HSTS and HTTPS redirects. | `isSecure` and `remoteAddress` exist; behind proxies needs forwarded headers (left) |
| **Tests.** `MockMvc` request post-processors (Spring's `RequestPostProcessor`); security adds `user(...)`, `jwt(...)` and `csrf()` the way `spring-security-test` does. | exists: `RequestPostProcessor`, `MockRequestBuilder.with_`, `defaultPostProcessors` |

## MCP servers

AI clients (Claude, IDEs, agents) call tools through MCP servers. A Dart
MCP server on this starter can live in a backend or inside a Flutter app,
exposing the app's beans as tools. Planned in the AI starter
(`spring_boot_starter_ai`): [spring_ai_mcp.md](spring_ai_mcp.md).

What MCP's Streamable HTTP transport needs from this starter, and which
exists now:

- **One endpoint** (exists). A `POST` with a JSON-RPC message, answered
  with either `application/json` or a `text/event-stream` (SSE from a
  `POST`: an `EventStream` or `SseEmitter` result). A `GET` opens a stream
  for messages from the server (`SseEmitter`s kept in a registry bean),
  and a `DELETE` ends the session.
- **Sessions and resuming** (exists). Headers `Mcp-Session-Id` and
  `MCP-Protocol-Version` through `@RequestHeader` and `ResponseEntity`
  headers; resuming with `Last-Event-ID`.
- **`Origin` checks against DNS rebinding** (exists), and `127.0.0.1` by
  default for local servers: a `WebFilter` and the Flutter default
  address.
- **Authorization** (left): an OAuth 2.1 resource server (the security
  starter's JWT support), protected resource metadata at
  `/.well-known/oauth-protected-resource`, and `WWW-Authenticate` on a 401
  (an `ErrorResponse` can already carry it).

## Tests

Done: `MockMvc`, the same `HttpHandler` without a socket:

```dart
@SpringBootTest()
@AutoConfigureMockMvc()
class BookControllerTest {
  @Autowired()
  late MockMvc mvc;

  @Test()
  Future<void> rejectsInvalidBody() async {
    await mvc
        .post('/api/books', json: {'isbn': '', 'title': ''})
        .andExpect(status: 400, contentType: MediaType.applicationProblemJson);
  }
}
```

It also reads SSE streams and emitters event by event, sends multipart
uploads (`multipart` with `MockMultipartFile`), and opens WebSocket
sessions in memory. `springBootTest(webEnvironment:
WebEnvironment.randomPort)` runs the real server with `@LocalServerPort`,
so a Feign client and the controller can be tested together.

Left: test slices (`@WebMvcTest`), and the examples' hand-written
`dart:io` stand-in servers (the `spring_web_dart` example and tests)
becoming Spring controllers.

## Order of work

1. ~~**Generator:** metadata for controller methods and introspection of
   their types.~~ Done.
2. ~~**`dart:io` server behind `WebServerFactory`.**~~ Done.
3. ~~**Errors:** `ProblemDetail`, `@ExceptionHandler`,
   `@ControllerAdvice`, `@Valid` → 400.~~ Done.
4. ~~**Tests:** `MockMvc`, `randomPort`.~~ Done; replacing the stand-in
   servers is left.
5. ~~**Streaming:** `EventStream` and `SseEmitter`, SSE from a `POST`,
   heartbeats.~~ Done; `ResponseBodyEmitter` is left.
6. **Filters, interceptors, CORS, sessions, cookies:** done except
   `HttpSession` and filter registration with URL patterns.
7. ~~**WebSocket endpoints.**~~ Done.
8. ~~**Files:** multipart uploads, `Resource` downloads with `Range`,
   byte streams, `StreamingResponseBody`, `MockMvc.multipart`.~~ Done;
   byte-range lists, `ETag`, streamed Feign uploads left.
9. **Flutter:** lifecycle and default address done; platform checks,
   blocking warnings, JSON offload left.
10. **Static files, forwarded headers, limits:** compression and the body
   limit done; the rest left.

Later: the `shelf` server, `server.isolate: background`, STOMP, the
[actuator](spring_boot_actuator.md) over HTTP, the
[security starter](spring_boot_starter_security.md), the
[MCP server](spring_ai_mcp.md).
