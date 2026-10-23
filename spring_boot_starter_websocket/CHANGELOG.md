## 0.1.7

- `spring.websocket.client.config.*` keys with relaxed names: `connectTimeout`, `reconnect.maxRetries`, `defaultRequestHeaders.X-Shop`, environment variables
- Breaking: the reconnect properties are named like Spring 7's `RetryPolicy`, under `reconnect.*`: `reconnect` → `reconnect.enabled`, `reconnect-delay` → `reconnect.delay`, `max-reconnect-delay` → `reconnect.max-delay`, `max-attempts` → `reconnect.max-retries` (retries after the first attempt: `max-attempts=N` is `max-retries=N-1`); new `reconnect.multiplier` (default 2) and `reconnect.jitter` (default none), computed like Spring's `ExponentialBackOff`.
- Breaking: `WebSocketClientConfig.reconnect` is a `WebSocketReconnectPolicy` (`enabled`, `delay`, `multiplier`, `maxDelay`, `jitter`, `maxRetries`, `delayFor(retry)`); `reconnectDelay`, `maxReconnectDelay` and `maxAttempts` are gone.
- Breaking: the reconnecting `WebSocketSession` is now `WebSocketConnectionManager` (Spring's name; `isOpen` → `isConnected`, `send` → `sendMessage`), `WebSocketInvocationHandler.session` → `connectionManager`; `WebSocketSession` is now `spring_web_dart`'s open connection (formerly `WebSocketConnection`).

## 0.1.6

- update road map
- ci: release with a button on main, skip new packages when publishing; shorter pubspec descriptions

## 0.1.5

- Initial version: @WebSocketClient interfaces with @OnMessage streams and @SendMessage methods, JSON through ObjectMapper, one shared connection per client opened on demand, reconnection with backoff, handshake interceptors, spring.websocket.client.config.* properties.
