## Unreleased

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
