# Spring Boot + Feign against real servers

A small, complete Spring Boot application in Dart that talks to real
public servers, no key needed:

- a REST API — [JSONPlaceholder](https://jsonplaceholder.typicode.com) —
  through a Feign client
  ([`spring_boot_starter_feign`](../../spring_boot_starter_feign/README.md));
- server-sent events — [Wikimedia EventStreams](https://stream.wikimedia.org),
  every edit on Wikipedia as it happens — through a Feign method returning
  `EventStream<RecentChange>`;
- a WebSocket — Postman's echo server (`wss://ws.postman-echo.com/raw`) —
  through a declarative `@WebSocketClient`
  ([`spring_boot_starter_websocket`](../../spring_boot_starter_websocket/README.md)).

```bash
cd example/spring_boot_feign
dart run build_runner build   # only after changing beans or the client
dart run bin/main.dart
```

```text
Started spring-boot-feign-example in 82 ms (profiles: default)
DEBUG [feign.JsonPlaceholderClient] ---> GET https://jsonplaceholder.typicode.com/users/1
DEBUG [feign.JsonPlaceholderClient] <--- 200 OK (143 ms)
 INFO [blog] user 1: Leanne Graham <Sincere@april.biz>, Gwenborough, works at Romaguera-Crona
 ...
 INFO [blog] post 9999: 404 Not Found (FeignNotFound)
DEBUG [feign.WikimediaStreams] ---> GET https://stream.wikimedia.org/v2/stream/recentchange
DEBUG [feign.WikimediaStreams] <--- 200 OK (500 ms, event stream)
 INFO [wikipedia] commonswiki edit: "File:2026-08-22 Motorsport, Formel 1, ... .jpg" by Rkieferbot (bot)
 INFO [wikipedia] enwiki edit: "Graham Seed" by Mouldylocks
 INFO [wikipedia] enwiki categorize: "Category:Canada election preliminary results" by Moondragon21
 INFO [wikipedia] enwiki edit: "Draft:Locative media art" by Normospheric
 INFO [wikipedia] enwiki edit: "The House Institute Foundation" by Taylorpiper
DEBUG [websocket.EchoSocket] connected to wss://ws.postman-echo.com/raw
 INFO [echo] echo: dart says "hello"
 INFO [echo] echo: dart says "spring"
```

The three runners go one after another (`@Order(1)`, `(2)`, `(3)`), as in
Spring Boot: each starts when the previous one's `Future` has completed.

It needs the internet; without it the application starts and each runner
logs that its server is not reachable.

## Tests

```bash
dart test
```

No internet needed, so they run in CI too:

- **unit tests** — each client against `MockHttpTransport` /
  `MockWebSocketTransport` (requests, headers, JSON, 404, retries, the
  event stream's reconnect with `Last-Event-ID`, lazy WebSocket connect),
  and each runner called directly (what it prints, and that a failing
  server is logged, not thrown);
- **end to end** (`test/local_servers_test.dart`) — the application
  started like `dart run bin/main.dart` (generated `springApplication`,
  config file, runners) with the real `dart:io` transports, against local
  stand-ins for the three servers (`test/support/local_servers.dart`): the
  REST calls, 5 events across a reconnect and the stream closed after
  `break`, two WebSocket messages echoed.

## What is where

| File | What |
|---|---|
| `bin/main.dart` | `@SpringBootApplication` + `runApplication(args)` — the whole entry point |
| `lib/src/jsonplaceholder_client.dart` | the API as an interface: `@FeignClient`, `@GetMapping`, `@PostMapping`, `@PathVariable`, `@RequestParam`, `@RequestBody`, `ResponseEntity` |
| `lib/src/models.dart` | `User` (with nested `Address`, `Company`), `Post`, `NewPost`, `Comment`, `RecentChange`, `ChatMessage`: plain immutable classes, no annotations, no `fromJson` / `toJson` (unknown JSON fields are ignored) |
| `lib/src/feign_config.dart` | a `RequestInterceptor` bean (an `X-Client` header on every request) and a `Retryer` bean |
| `lib/src/blog_runner.dart` | an `ApplicationRunner`: gets the client injected, calls the API, handles `FeignNotFound` |
| `lib/src/wikimedia_client.dart` | server-sent events: `@GetMapping` returning `EventStream<RecentChange>`, a `User-Agent` header from a property |
| `lib/src/echo_socket.dart` | a declarative WebSocket client: `@WebSocketClient`, `@OnMessage` (`Stream<ChatMessage>`), `@SendMessage` |
| `lib/src/live_runners.dart` | `WikipediaRunner` (prints 5 live edits, then `break` closes the stream) and `EchoRunner` (sends two messages, prints the echo) |
| `lib/resources/application.properties` | the server URLs, the Wikimedia `User-Agent`, Feign and WebSocket settings, logging levels |
| `bin/main.beans.dart` | generated: the beans, the client implementations, the JSON metadata of the models |
| `test/` | unit tests on mocks, the end-to-end test and its local servers (`test/support/`) |

## Things to try

```bash
# Another API base URL (e.g. a local copy of JSONPlaceholder)
dart run bin/main.dart --jsonplaceholder.url=http://localhost:3000

# See the headers of each request (the X-Client header of the interceptor)
dart run bin/main.dart --spring.cloud.openfeign.client.config.jsonplaceholder.logger-level=headers

# No request log
dart run bin/main.dart --logging.level.feign=info

# The headers of the event stream request (User-Agent, Accept: text/event-stream)
dart run bin/main.dart --spring.cloud.openfeign.client.config.wikimedia.logger-level=headers
```

Add a method to `JsonPlaceholderClient` (say `@GetMapping('/todos')
Future<List<Todo>> todos(@RequestParam('userId') int userId);` with a
`Todo` class next to the models), run `dart run build_runner build` and call
it from the runner.
