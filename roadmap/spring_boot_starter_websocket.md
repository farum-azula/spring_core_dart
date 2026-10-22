# spring_boot_starter_websocket

Done: declarative clients (`@WebSocketClient`, `@OnMessage`,
`@SendMessage`), one shared connection opened on demand, reconnection with
backoff, handshake interceptors, `MockWebSocketTransport`.

## Next steps

STOMP (`@SubscribeMapping`-style destinations on one connection), a
connection state stream for UIs, message filters by a JSON field, and the
server side together with the coming web server starter.
