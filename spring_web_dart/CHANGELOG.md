## Unreleased

- Breaking: `HttpStatus` has every Spring Framework 7 constant with Spring 7's names (`unprocessableContent` instead of `unprocessableEntity`, `contentTooLarge`, ...), as an extension type over `int`; `reasonPhrase`, `series` (`HttpStatusSeries`) and `is1xxInformational` / `is2xxSuccessful` / `is3xxRedirection` / `is4xxClientError` / `is5xxServerError` / `isError` are getters, `valueOf` / `resolve` find a constant. The static `HttpStatus.reasonPhrase(int)`, `isSuccess`, `isClientError`, `isServerError` and `isError` are gone.
- Breaking: `statusCode` of `ResponseEntity`, `HttpResponse` and `StreamedHttpResponse` is an `HttpStatusCode` (still an `int`; `HttpStatusCode.valueOf` for any code).
- Breaking: `HttpHeaders.forEach` passes each name once with all its values (`(name, values)`, Spring 7); the name constants end in `Header` (`HttpHeaders.contentType` → `HttpHeaders.contentTypeHeader`, also `acceptHeader`, `authorizationHeader`, `contentLengthHeader`, `userAgentHeader`) and there are many more. New: `toSingleValueMap()`, `contentType`, `location`, `contentLength`, `setBearerAuth`, `setBasicAuth`, `encodeBasicAuth`.
- Breaking: mapping `headers` use Spring's `'Name=value'` syntax; `'Name: value'` is no longer accepted by clients.
- Breaking: `WebSocketConnection` → `WebSocketSession` (`send` → `sendMessage`, `protocol` → `acceptedProtocol`, new `uri` and `isOpen`; `closeCode` / `closeReason` → `closeStatus`); `WebSocketStatus` → `CloseStatus` with Spring's constants (`normal`, `goingAway`, `noStatusCode`, `noCloseFrame`, `serverError`, `serviceRestarted`, `serviceOverload`, ...), `close([CloseStatus status = CloseStatus.normal])` (a normal closure by default, like Spring). `MockWebSocket.url` → `uri`, `closeFromServer([CloseStatus])`.
- `HttpRequest.readTimeout`: the longest wait for data (for the response, then between two chunks of the body), next to `timeout` (the whole exchange); `HttpRequest.followRedirects` (default `true`; `IoHttpTransport` no longer limits it to `GET` and `HEAD` itself).
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
