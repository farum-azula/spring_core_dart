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
