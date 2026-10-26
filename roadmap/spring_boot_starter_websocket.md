# spring_boot_starter_websocket

Done:

- **Clients:** declarative clients (`@WebSocketClient`, `@OnMessage`,
  `@SendMessage`), one shared connection opened on demand, reconnection
  with backoff, handshake interceptors, `MockWebSocketTransport`.
- **Server side** (served by
  [spring_boot_starter_web](spring_boot_starter_web.md#websocket-endpoints)
  when the application lists it; this starter does not depend on it):
  `@WebSocketEndpoint` beans with `@OnOpen`, `@OnMessage` (the reply is
  sent back), `@OnClose`, `@OnError`; Spring's `WebSocketHandler`,
  `AbstractWebSocketHandler`, `TextWebSocketHandler`,
  `WebSocketConfigurer` and `HandshakeInterceptor`;
  `ServerWebSocketSession`, `WebSocketSessionRegistry` for broadcasting;
  origin checks like Spring's; handshakes through the web starter's
  filters; `MockMvc.webSocket` in tests.

## Next steps

- STOMP (`@MessageMapping`, `@SendTo`, `@SubscribeMapping`-style
  destinations on one connection), on both sides.
- A connection state stream for UIs (clients).
- Message filters by a JSON field (clients).
- Server: per-session send buffers and limits (Spring's
  `ConcurrentWebSocketSessionDecorator`), message size limits, ping /
  idle timeouts.
