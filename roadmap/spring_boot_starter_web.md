# spring_boot_starter_web (planned)

The server side of `spring_web_dart`: the mapping annotations Feign clients
already use (`@GetMapping`, `@PathVariable`, `@RequestBody`, ...) on
controllers, like Spring MVC, on `dart:io`'s `HttpServer`. Runs on the VM
and inside Flutter apps on mobile and desktop (a local API, a companion
server); not on the web, which has no server sockets.

## Controllers

```dart
@RestController()
@RequestMapping('/api/books')
class BookController {
  BookController(this.books);
  final BookService books;

  @GetMapping('/{isbn}')
  Future<Book> find(@PathVariable() String isbn) => books.find(isbn);

  @GetMapping()
  Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam('page') int page = 0}) =>
      books.search(query, page: page);

  @PostMapping()
  Future<ResponseEntity<Book>> create(@RequestBody() @Valid() NewBook book) async {
    final created = await books.create(book);
    return ResponseEntity.created(Uri.parse('/api/books/${created.isbn}'), body: created);
  }

  @GetMapping('/events')
  EventStream<StockEvent> events() => books.stockEvents();   // server-sent events
}
```

- Binding like the Feign side, in reverse: path variables, query
  parameters (lists, enums, dates), headers, JSON bodies through the
  `ObjectMapper`; `ResponseEntity`, `@ResponseStatus`; checked at startup
  (a `{variable}` without a parameter stops the application, as for Feign).
- `@Valid` on bodies with the existing validation: a violation is a 400
  with the messages.
- Errors: `@ExceptionHandler` and `@ControllerAdvice`, answers as
  `ProblemDetail` (RFC 9457) like Spring 6.
- Server-sent events: a controller returns `EventStream<T>` — the same
  type the clients read; `id`, `event` and `retry` through
  `ServerSentEvent<T>`.
- WebSocket endpoints as beans, in the same declarative style as
  `@WebSocketClient`.
- Filters and `HandlerInterceptor`s, CORS (`@CrossOrigin`,
  `spring.web.cors.*`), static files from `lib/resources/static/` (Spring
  Boot's `classpath:static`).
- `server.port`, `server.address`, TLS, graceful shutdown with the context.

## Tests

- A `MockMvc`-style client that calls the controllers without a socket:
  `mockMvc.get('/api/books/1').andExpect(status: 200, json: {...})`.
- `springBootTest(webEnvironment: randomPort)` with the real transports,
  so client and server are tested together — the examples' hand-written
  `dart:io` stand-in servers become Spring controllers.

## Later

Security on top: [spring_boot_starter_security](spring_boot_starter_security.md)
(filter chain, Basic, sessions, JWT) with `@PreAuthorize` from
[spring_security_core](spring_security_core.md).
