## 0.3.2

- feat: hot reload on the Dart VM, flutter_notes example, fixes for example resources and workspace builds
- feat: spring_boot_starter_web, WebSocket server endpoints, uploads and downloads

## 0.3.1

- **Brings logging, like every Spring Boot starter:** depends on and re-exports `spring_boot_starter_logging` (and through it `spring_boot_dart` and `spring_core_dart`), so the starter is the only dependency an application lists, and one import gives everything. An application using it now gets the logging system (Boot's console format, `logging.*` properties) without adding the logging starter; `logging.enabled=false` turns it off.
- The example is a Spring Boot application: a `@WebSocketClient` against a local echo server.
- Tests take `MockWebSocketTransport` from `spring_boot_starter_test` (README).
- `spring_auto_configuration.dart` re-exports the logging starter's (and through it `spring_boot_dart`'s) auto-configuration, so a test naming `springBootAutoConfiguration` (`ApplicationContextRunner`) needs no other dependency.

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

- the auto-configured `webSocketTransport` backs off for a `WebSocketTransport` registered by an `@Import`ed `BeanRegistrar` / `ImportBeanDefinitionRegistrar` of the application; its condition is decided when the auto-configuration is read, like Boot's `OnBeanCondition`
- `reconnect.delay=0` waits nothing (± `jitter`) on every attempt; from attempt 1074 the wait was NaN, which threw and stopped reconnecting.
- After giving up on a server that accepts and closes at once, the retry count starts over for the next listener (it got a single attempt).
- No reconnect is made once every listener cancelled (a scheduled attempt still connected); the next listener starts afresh.
- `reconnect.*` is checked like Spring 7's `RetryPolicy.Builder` (`WebSocketReconnectPolicy.validate`): `delay` and `jitter` not negative, `multiplier` at least 1, `max-delay` positive, `max-retries` not negative; anything else fails the start naming the property, with the duration written like `1m` or `500ms`. A `delay` above `max-delay` is accepted, as in Spring (the waits are then `max-delay`).
- The retry count is reset only once a connection proves stable (a message, or open for `reconnect.max-delay`): a server that accepts and closes at once no longer keeps `reconnect.max-retries` from stopping.
- A send (or `connect()`) without a connection waits for the next attempt only and fails with it (it waited forever while listeners kept reconnecting without `max-retries`).
- `WebSocketClientFactory.destroy()` returns a future that completes once the open connections are closed (awaited by `closeAsync()`).
- A client's `default-request-headers` replace `default`'s of the same name in any case (both were sent).
- `reconnect.enabled` takes true / false in any case (and on / off, yes / no, 1 / 0); anything else fails the start (`nope` was on).
- Breaking: `WebSocketClientConfig.defaultRequestHeaders` is a `Map<String, List<String>>` bound through the Binder: `X: a,b` and YAML lists (`X[0]`) give several header values.

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
