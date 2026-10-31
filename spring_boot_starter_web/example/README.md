# spring_boot_starter_web: example

[`example.dart`](example.dart) is a complete Spring Boot application
serving a small book API. It shows the usual pieces of a REST API:

- a `@RestController` whose `GET` returns a book as JSON;
- a `POST` whose body is checked with `@Valid()` and which answers
  `201 Created` with a `Location` header;
- an `@ExceptionHandler` that turns a missing book into a 404
  `ProblemDetail`;
- server-sent events: every added book is pushed to the clients that
  listen.

The application listens on port **8085**, set in
[`lib/resources/application.properties`](lib/resources/application.properties).

```yaml
dependencies:
  spring_boot_starter_web: ^0.5.0

dev_dependencies:
  build_runner: ^2.17.0
  spring_core_dart_generator: ^0.5.0
```

## Run it

From the `spring_boot_starter_web` directory:

```bash
dart run build_runner build   # writes example.spring.dart: the beans and the request handlers
dart run example/example.dart
# INFO  Web server started on port 8085 (http)
```

Then, from another terminal:

```bash
# A book as JSON.
curl localhost:8085/api/books/978-0
# {"isbn":"978-0","title":"Dune"}

# A book that does not exist: the exception handler answers a ProblemDetail.
curl localhost:8085/api/books/9
# {"type":"about:blank","title":"Not Found","status":404,"detail":"No book 9","instance":"/api/books/9"}

# Keep this one open to see the books added below arrive as events.
curl -N localhost:8085/api/books/added

# Add a book: 201 Created, with Location: /api/books/978-1.
curl -i localhost:8085/api/books -H 'Content-Type: application/json' \
    -d '{"isbn": "978-1", "title": "Emma"}'

# An invalid body: 400, with one entry per violated constraint.
curl localhost:8085/api/books -H 'Content-Type: application/json' \
    -d '{"isbn": "", "title": "Emma"}'
# {"type":"about:blank","title":"Bad Request","status":400,"detail":"Invalid request content.",
#  "instance":"/api/books","errors":[{"field":"isbn","message":"must not be blank","rejectedValue":""},
#  {"field":"isbn","message":"size must be between 4 and 13","rejectedValue":""}]}
```

## What to look at

- `BookController` gets its `BookService` through the constructor, like
  any bean. The class-level `@RequestMapping('/api/books')` is the
  prefix of every method's path.
- `NewBook` carries the constraints (`@NotBlank()`, `@Size`) that
  `@Valid()` checks before `create` runs. `Book` and `NewBook` are read
  and written as JSON without any code of yours: the generator
  introspects the types the controller uses.
- `notFound` is an `@ExceptionHandler`: the type of its parameter,
  `BookNotFound`, says which exceptions it answers.
- `added` returns an `EventStream<Book>`. Each listener gets its own
  subscription to the service's stream, and it is cancelled when the
  client goes away.

The package [README](https://pub.dev/packages/spring_boot_starter_web)
describes every feature: parameters, results, errors, files, sessions,
filters, CORS, the server settings and testing with `MockMvc`.
