## Unreleased

- The documentation names HTTP service interfaces and `RestClient` as the clients of the annotations and transports: the request mapping annotations (`@GetMapping`, ...) are a server's, a client's calls are the exchange annotations' (`@GetExchange`, ...), and the parameter annotations serve both. The example declares an `@HttpExchange` interface.
- `RestClient`, Spring's fluent HTTP client, on the `HttpTransport`: `RestClient.create`, `RestClient.builder()` and `RestClientBuilder` (base URL, default headers, cookies and URI variables, `defaultRequest`, `defaultStatusHandler`, interceptors, message converters, the `ObjectMapper`, the transport, read and connect timeouts, redirects, sensitive headers, `apply`, `clone`, `build`), `mutate()`; `get`/`head`/`post`/`put`/`patch`/`delete`/`options`/`method`; `uri` with a template and its variables as a list, a map or one value, a `Uri`, or a `UriBuilder` function (`path`, `pathSegment`, `queryParam`, `queryParamIfPresent`, `replaceQueryParam`, `fragment`, `build`); `header`, `headers`, `accept`, `cookie`, `contentType`, `body`; `retrieve()` with `onStatus`, `body<T>`, `toEntity<T>`, `toBodilessEntity`, `eventStream<T>` (server-sent events) and `bodyStream`; `exchange`. URI templates are compiled once per client and encoded as Spring's `TEMPLATE_AND_VALUES`; a missing or extra value and a path variable `.` or `..` are errors. A call honours the `RequestDeadline` of the code that makes it (its timeouts are cut to the time left; a shorter timeout of the request's own is kept), and its log (`web.client.RestClient`) masks credential headers and query parameters.
- The exceptions of `RestClient`: `RestClientException`, `RestClientResponseException` (status, headers, body bytes and text, `bodyAs<T>()`), `HttpStatusCodeException`, `HttpClientErrorException`, `HttpServerErrorException`, `UnknownHttpStatusCodeException`, `ResourceAccessException`.
- `ClientHttpRequestInterceptor` and `ClientHttpRequestExecution`; `HttpMessageConverter` with `ByteArrayHttpMessageConverter`, `StringHttpMessageConverter`, `MultipartHttpMessageConverter`, `FormHttpMessageConverter` and `JsonHttpMessageConverter`.
- The annotations of HTTP service interfaces, in the main library: `@HttpExchange`, `@GetExchange`, `@PostExchange`, `@PutExchange`, `@PatchExchange`, `@DeleteExchange`, `@ImportHttpServices(group:, types:)`, and `HttpRequestAttribute`, the base of an annotation that sets a request attribute on the generated calls (the OAuth2 client's `@ClientRegistrationId`).
- Request attributes: `attribute(name, value)` and `attributes(configure)` on a `RestClient` request (in `defaultRequest` for every call), handed to the interceptors as `HttpRequest.attributes` and never sent, as Spring's `HttpRequest.getAttributes()`.
- **Security:** outgoing addresses can be limited: `AllowedAddresses` (host names, `*.` subdomains, address literals, CIDR blocks, `*`) on `IoHttpTransport`, `FetchHttpTransport` and `platformHttpTransport(allowedAddresses:)`. Loopback, private networks, link-local and cloud metadata are denied unless an entry within their own block opens them. On `dart:io` the transport resolves the name, checks each address and connects to the addresses it checked, in order until one answers (`localhost` is `::1`, then `127.0.0.1`; against DNS rebinding), and checks each redirect; with `fetch` only the URL's host is checked (and each redirect in a server runtime). A denied call fails with a `FilteredHostException`. `AllowedAddresses.allowHostName` adds a host name learned at run time from a trusted source (never an address, a block, a wildcard or `localhost`), as the OAuth2 client does with the endpoints a provider's discovery names. `InetAddressFilter` (Spring Boot 4.1's), `IpAddress` and `IpAddressRange` describe addresses on every platform.
- **Security:** `RestClient.create(baseUrl)` and a `RestClient.builder()` built without a transport call only the host of the base URL (a host name that resolves to loopback or a private network included, unless it is `localhost` or the base URL gives the address); every other address, and every address without a base URL, fails with a `FilteredHostException` that says how to allow it: a transport with `AllowedAddresses`, or the RestClient starter's `spring.http.clients.allowed-addresses`. Spring's `RestClient.create()` calls any address.
- `EventStreamRetryAdapter`, a `RetryStreamAdapter` that keeps the `EventStream` of a retried `@Retryable` method an `EventStream` with its whole events (the web and RestClient starters declare it with `spring.resilience.enabled: true`).
- `RequestDeadline` and `RequestDeadlineExceededException` moved to `spring_core_dart` (`core.dart`), so the retries read the same deadline; this package re-exports them, and nothing changes for code that imports them from here.
- `HttpRequest.connectTimeout`: the longest wait for this request's connection (on `dart:io` within the transport's own). `IoHttpTransport` takes `allowBadCertificates`, `securityContext` and `lookup` (a resolver of its own).

## 0.10.0

- `HttpSecrets`: the one rule for the headers and parameters a log never shows (credentials, cookies, the DPoP proof, OAuth's `code`, `state`, `code_verifier`, `client_assertion`, signed-URL signatures, and names `SecretNames` calls secret), shared by the web starter's request logs and the Feign client's.
- `IoHttpTransport` follows redirects itself: a redirect to another origin drops the headers that carry a credential (`HttpSecrets` and the new `HttpRequest.sensitiveHeaders`), and one from `https` to `http` is not followed (the `3xx` is returned).
- **Security:** `FetchHttpTransport` no longer leaves a request with a credential header to `fetch`'s redirect rules, which kept `X-Api-Key` and other custom headers on another origin (seen in Chromium, WebKit, Deno, workerd and Supabase's Edge Runtime; workerd kept `Cookie` too) and followed `https` to `http`. In an edge runtime it follows such a redirect itself, by the rules of `IoHttpTransport`. A browser hides a redirect's target, so there a request with a custom credential header fails with an `HttpTransportException` on a redirect, also to the same origin, and the target gets nothing; a request whose only credentials are `Authorization` or `Cookie` is still followed, as the browser removes them itself. Differs from Spring and OpenFeign, whose clients keep custom headers on another origin.
- `HttpTransportException.isRetryable`: `false` for a redirect the browser's transport refuses, which the server has already handled, so an event stream does not reconnect to it. `HttpRequest.withHeaders` copies a request with other headers and keeps its `sensitiveHeaders`.

## 0.9.0

- No changes of its own; released with the family version 0.9.0.

## 0.8.4

- No changes of its own; released with the family version 0.8.4.

## 0.8.3

- No changes of its own; released with the family version 0.8.3.

## 0.8.2

- No changes of its own; released with the family version 0.8.2.

## 0.8.1

- No changes of its own; released with the family version 0.8.1.

## 0.8.0

- **Fixed (Dart 3.14):** a WebSocket connection whose socket the other side reset before the session was made no longer fails the upgrade. Dart 3.14 reads the socket's remote address and port when it makes the `WebSocket` (for the profiler of its tools), and a socket closed by then throws for them; the session is made without them, and the reset shows where it is handled, as a close with 1006 and the error as the reason.
- `HttpRequest(abort:)`: a future that completes when the caller no longer wants the response. `IoHttpTransport` and `FetchHttpTransport` then give up a request that still waits for the status and headers (the connection closes, the call fails with an `HttpTransportException`, `request aborted`); once the headers arrived it has no effect, the body's subscription is cancelled instead. A transport of your own that wraps another one copies it to the request it passes on; one that ignores it keeps working, the request then runs until the server answers.
- `WebSocketTransport.connect(url, maxTextMessageSize:, maxBinaryMessageSize:)`: the largest messages this one connection receives, in bytes (`-1`: no limit); `null`, the default, keeps the transport's own limits. `IoWebSocketTransport` uses them for the session it opens, the browser (which has no limit) ignores them, and a `MockWebSocket` keeps them (`maxTextMessageSize`, `maxBinaryMessageSize`) and closes with 1009 when the test pushes a larger message. A class that implements `WebSocketTransport` adds the two parameters to its `connect`.

## 0.7.4

- No changes of its own; released with the family version 0.7.4.

## 0.7.3

- No changes of its own; released with the family version 0.7.3.

## 0.7.2

- README: the link goes to the package's own page on farum-azula.org, and what the README says was checked against the code and brought up to date.
- `platformHttpTransport(allowBadCertificates:)` accepts a certificate that is expired, self-signed or for another host (`dart:io` only), for the configuration's downloads with `spring.remote.allow-insecure`.

## 0.7.1

- `MappingDescriptions`: a bean that describes the addresses a part of the application answers (the web server's handlers, an app's screens), for the actuator's `mappings` endpoint and the editor.
- `CacheControl`, Spring's builder of `Cache-Control` values (`maxAge`, `noCache`, `noStore`, `mustRevalidate`, `noTransform`, `cachePublic`, `cachePrivate`, `proxyRevalidate`, `sMaxAge`, `staleIfError`, `staleWhileRevalidate`, `immutable`, `headerValue`).
- `PathPattern.extractPathWithinPattern`: the part of a path a pattern does not fix (`css/app.css` of `/assets/css/app.css` under `/assets/**`).
- `MediaTypeFactory` knows `.webmanifest` (`application/manifest+json`).

## 0.7.0

- No changes of its own; released with the family version 0.7.0.

## 0.6.3

- Ships `lib/spring_gen/spring_metadata.json`, written by hand and empty (the library reads no properties and declares no beans), so editors know the package is complete.

## 0.6.2

- No changes of its own; released with the family version 0.6.2.

## 0.6.1

- No changes of its own; released with the family version 0.6.1.

## 0.6.0

### Changes

- The doc comments name the renamed properties (`spring.web.multipart.*`, `server.context-path`; see `spring_boot_starter_web`).
- `RequestDeadline`, a time limit for the total work of a request and the calls it makes, carried in the `Zone` like a transaction (an extension: Spring has no counterpart): `RequestDeadline.run(budget, body)` and `runUntil(instant, body)` (a nested deadline ends at the earlier of the two, never later), `RequestDeadline.current` (`null` outside any), `remaining`, `isExpired`, `check()`, which throws a `RequestDeadlineExceededException`. It works in the browser too. The web starter's `server.request-timeout` and the Feign starter's `call-timeout` use it.

## 0.5.0

### Breaking

- `ResponseCookie` checks its name, value, domain and path as Spring's `ResponseCookie` does (RFC 6265): a character that would end the value or start another attribute (`;`, `,`, a space, a quote, a control character, non-ASCII) is an `ArgumentError`, so text from a request can never add `; Domain=...`. Its constructor is no longer `const`.
- `IoWebSocketTransport` (and `platformWebSocketTransport()` on `dart:io`) does not read a message over 8 KB, text or binary, and closes the session with 1009, as Tomcat's client in Spring; raise the limits with `maxTextMessageSize` / `maxBinaryMessageSize` (`-1`: no limit).
- An `IoWebSocketSession` of the transport (or of the web starter's server) drops the connection with 4500 (`CloseStatus.sessionNotReliable`) when more than 512 KB wait to be sent or what was sent has not left within 10 seconds, as Spring's `ConcurrentWebSocketSessionDecorator`; set other limits with `IoWebSocketTransport(sendBufferSizeLimit:, sendTimeLimit:)`.
- A connection the other side resets ends `messages` without an error, with `closeStatus` 1006 (`CloseStatus.noCloseFrame`) and the error as the reason, as Tomcat reports it (was a `WebSocketException` and 1002), whether a read or a write met it first, over TLS too.
- `isOpen` is `false` right after `close()`, and `sendMessage` then throws a `WebSocketException`.
- An `IoWebSocketSession` listens to its `dart:io` socket from the start, paused until `messages` is listened to: don't listen to a socket you wrapped in one. Messages that arrive after `close()` while nobody listens are dropped.
- The WebSocket client refuses a handshake answer that picks a subprotocol it did not offer, or any extension (it offers none, so no permessage-deflate), as RFC 6455 asks, and does not follow redirects, as browsers.

### Changes

- `AllowedOrigins`: the origin check of Spring's `CorsConfiguration`, shared by the web starter's CORS and the WebSocket starter's handshake. Origins are compared without case, patterns with case; `*` matches any text, as Spring's `.*`; a port list at the end takes the ports listed (`http://localhost:[3000,3001]`) or, with `[*]`, any port or none; a value may list several, separated by commas; a trailing `/` is ignored.
- `AllowedOrigins` matches patterns in time that grows with the origin's length, however many `*` they have; one difference from Spring: an origin longer than 1024 characters (`maxOriginLength`) is never allowed.
- `@CrossOrigin(allowPrivateNetwork:)`, Spring's attribute for Chrome's Private Network Access; `@CrossOrigin()` without `methods` documents Spring's default, the method the handler is mapped to.
- `@ControllerAdvice.of` and `@RestControllerAdvice.of` narrow an advice to some controllers, as Spring's attributes: `basePackages` (library URI prefixes such as `package:shop/admin/`), `assignableTypes` or `annotations`.
- `PathPattern` leaves matrix parameters out of the match, as Spring: `/books/1111;v=1` matches `/books/{isbn}` with `isbn` `1111`. An escape that is not UTF-8 is matched as written.
- `MultipartParser`: an error in the middle of a part (a size limit, a client that went away) ends that part's content with the error, so its reader never waits for ever; cancelling the parts stops reading the body.
- `IoWebSocketSession.flush()` completes once everything sent has left (and fails with a `WebSocketException` when the connection ends first): await it after each message to send at the network's pace, as Spring's blocking `sendMessage` does. `done` completes when the connection has closed.
- `IoWebSocketSession.fromUpgradedSocket` makes a session, with the limits above, over a socket whose handshake was done by hand (what it sends follows the handshake answer); `webSocketAccept(key)` gives the `Sec-WebSocket-Accept` value.
- `platformWebSocketTransport(maxTextMessageSize:, maxBinaryMessageSize:)`; the browser has no such limits and ignores them.
- A ping between the fragments of a message is answered at once and the message arrives whole (`dart:io`'s own `WebSocket` loses the fragments before it); an unfinished message takes the memory of its payload, however many fragments, empty ones too, it comes in.
- A session goes on reading while its messages wait to be sent, so two peers that both send more than the network holds no longer wait for each other for ever.

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

- `Principal` now comes from `spring_core_dart` (still exported here, the same type).
- `RequestPostProcessor` and `FunctionRequestPostProcessor` moved here from `spring_boot_starter_test` (`package:spring_web_dart/testing.dart`), so other starters can offer post-processors (the security starter's `user()`, `jwt()`, `csrf()`); the test starter still exports them.

## 0.3.2

- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- No changes of its own.

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

- `ResponseEntity.status(...).headers(h)` replaces the values of those names like Spring's `putAll` (it added them).
- `ResponseEntity` and `ResponseEntity.status` take only three-digit status codes (100–999), like Spring's `HttpStatusCode.valueOf`; others throw an `ArgumentError`. `HttpResponse` and `StreamedHttpResponse` take those and 0, the opaque redirect a browser gives for `followRedirects: false` (any other code throws).
- `HttpHeaders.addAll(name, values)`, `addHeaders`, `putAll`, `setAll`, `clear`, `size`, `containsHeaderValue`, `isNotEmpty`, `==` / `hashCode` (names in any case), `HttpHeaders.readOnly` (a view whose setters throw).
- `ResponseEntity`: read-only headers, `==` / `hashCode`, `ResponseEntity.of` / `ofNullable` (200 with the body, 404 without one).
- `HttpResponse.bodyText` decodes with the `charset` of the `Content-Type`, quoted or not and in any spelling Dart knows (only `charset=iso-8859-1` / `latin1` were seen); `HttpResponse.decodeBody`.
- `HttpHeaders.lastModified` is lenient like Spring's: `null` for a value that is not an HTTP date (it threw).
- `MediaType.parse` and the constructor check parameters like Spring: names are tokens, values tokens or quoted strings (also single quotes), no empty values, a legal charset name; a parameter without `=` is ignored (it threw) and a repeated name (any case) keeps the last value.
- `MediaType.parse` / `parseMediaTypes` give `MediaType` objects with `includes`, `isCompatibleWith`, `charset`, `qualityValue`, `subtypeSuffix` (Spring's rules for wildcards and `+json` suffixes; `InvalidMediaTypeException`); more constants: `applicationXml`, `applicationProblemJson`, `applicationProblemXml`, `applicationNdjson`, `applicationPdf`, `applicationYaml`, `textXml`, `textMarkdown`, images, multipart, ...
- `HttpHeaders.accept`, `eTag` (quoted like Spring's `setETag`), `ifNoneMatch`, `lastModified`, `date` (HTTP dates: RFC 1123, RFC 850, asctime; `formatDate` / `parseDate`), `contentDisposition` (new `ContentDisposition`, `filename*` for non-ASCII names), `setContentDispositionFormData`.
- `ResponseEntity.status(...)`, `created(uri)`, `accepted()`, `noContent()`, `badRequest()`, `notFound()`, `unprocessableContent()`, `internalServerError()` builders (`header`, `headers`, `location`, `contentType`, `eTag`, `lastModified`, then `body(x)` or `build<T>()`), and `hasBody`.
- Breaking: `HttpMethod.parse` is case-sensitive and does not trim, like Spring's `HttpMethod.valueOf` (`'get'` throws).

## 0.1.7

- Breaking: `HttpStatus` has every Spring Framework 7 constant with Spring 7's names (`unprocessableContent` instead of `unprocessableEntity`, `contentTooLarge`, ...), as an extension type over `int`; `reasonPhrase`, `series` (`HttpStatusSeries`) and `is1xxInformational` / `is2xxSuccessful` / `is3xxRedirection` / `is4xxClientError` / `is5xxServerError` / `isError` are getters, `valueOf` / `resolve` find a constant. The static `HttpStatus.reasonPhrase(int)`, `isSuccess`, `isClientError`, `isServerError` and `isError` are gone.
- Breaking: `statusCode` of `ResponseEntity`, `HttpResponse` and `StreamedHttpResponse` is an `HttpStatusCode` (still an `int`; `HttpStatusCode.valueOf` for any code).
- Breaking: `HttpHeaders.forEach` passes each name once with all its values (`(name, values)`, Spring 7); the name constants end in `Header` (`HttpHeaders.contentType` → `HttpHeaders.contentTypeHeader`, also `acceptHeader`, `authorizationHeader`, `contentLengthHeader`, `userAgentHeader`) and there are many more. New: `toSingleValueMap()`, `contentType`, `location`, `contentLength`, `setBearerAuth`, `setBasicAuth`, `encodeBasicAuth`.
- Breaking: mapping `headers` use Spring's `'Name=value'` syntax; `'Name: value'` is no longer accepted by clients.
- Breaking: `WebSocketConnection` → `WebSocketSession` (`send` → `sendMessage`, `protocol` → `acceptedProtocol`, new `uri` and `isOpen`; `closeCode` / `closeReason` → `closeStatus`); `WebSocketStatus` → `CloseStatus` with Spring's constants (`normal`, `goingAway`, `noStatusCode`, `noCloseFrame`, `serverError`, `serviceRestarted`, `serviceOverload`, ...), `close([CloseStatus status = CloseStatus.normal])` (a normal closure by default, like Spring). `MockWebSocket.url` → `uri`, `closeFromServer([CloseStatus])`.
- `HttpRequest.readTimeout`: the longest wait for data (for the response, then between two chunks of the body), next to `timeout` (the whole exchange); `HttpRequest.followRedirects` (default `true`; `IoHttpTransport` no longer limits it to `GET` and `HEAD` itself).
- Breaking: mapping attributes next to a path use the `.of` constructor, because the path is now an optional positional parameter: `@GetMapping('/books', produces: ...)` is `@GetMapping.of(path: '/books', produces: ...)` (also `PostMapping`, `PutMapping`, `PatchMapping`, `DeleteMapping`); `@RequestMapping('/x', method: ...)` is `@RequestMapping.of(path: '/x', method: ...)`.
- `path` is optional in `@GetMapping()` and the other mapping annotations (`''`: the base path of the client or class).
- `required` and `defaultValue` (`.of` constructors) on `@RequestParam` and `@RequestHeader`, `required` on `@PathVariable`, as in Spring: `required` is `true` by default, a default value implies `false`, a nullable Dart parameter of a query parameter or header is never required.
- `@CookieValue`; `@RequestBody(required:)`; `@RequestParam` / `@RequestHeader` document `Map` parameters (one query parameter / header per entry).
- README: a "Differences from Spring" section.

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- Initial version: Request mapping annotations, ResponseEntity, HttpHeaders, HTTP client transport (dart:io and fetch), MockHttpTransport.
- Streaming responses: `HttpTransport.stream` and `StreamedHttpResponse` (dart:io and fetch).
- Server-sent events: `EventStream<T>` (a `Stream<T>` with the whole events in `.events`), `ServerSentEvent<T>`, `SseDecoder`, `connectServerSentEvents` with `EventSource`-style reconnection (`SseReconnect`, `Last-Event-ID`), `MediaType.textEventStream`.
- WebSocket transports: `WebSocketTransport`, `IoWebSocketTransport` (dart:io), `BrowserWebSocketTransport` (js_interop), `platformWebSocketTransport()`, `WebSocketStatus`.
- Testing: `MockHttpTransport.respondEvents` / `respondStream`, `MockWebSocketTransport`.
- `IoHttpTransport`: request headers replace `HttpClient`'s defaults (a `User-Agent` is no longer appended to `Dart/x (dart:io)`).
