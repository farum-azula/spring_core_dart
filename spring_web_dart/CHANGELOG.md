## Unreleased

- Initial version: Request mapping annotations, ResponseEntity, HttpHeaders, HTTP client transport (dart:io and fetch), MockHttpTransport.
- Streaming responses: `HttpTransport.stream` and `StreamedHttpResponse` (dart:io and fetch).
- Server-sent events: `EventStream<T>` (a `Stream<T>` with the whole events in `.events`), `ServerSentEvent<T>`, `SseDecoder`, `connectServerSentEvents` with `EventSource`-style reconnection (`SseReconnect`, `Last-Event-ID`), `MediaType.textEventStream`.
- WebSocket transports: `WebSocketTransport`, `IoWebSocketTransport` (dart:io), `BrowserWebSocketTransport` (js_interop), `platformWebSocketTransport()`, `WebSocketStatus`.
- Testing: `MockHttpTransport.respondEvents` / `respondStream`, `MockWebSocketTransport`.
- `IoHttpTransport`: request headers replace `HttpClient`'s defaults (a `User-Agent` is no longer appended to `Dart/x (dart:io)`).
