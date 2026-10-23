import 'package:spring_web_dart/src/http_method.dart';

/// What every request mapping annotation (`@GetMapping`, `@PostMapping`,
/// ..., `@RequestMapping`) exposes, so code reading annotations can find
/// any of them with `annotations.whereType<Mapping>()`.
///
/// ```dart
/// final mapping = method.annotations.whereType<Mapping>().single;
/// print('${mapping.method.value} ${mapping.path}'); // GET /books/{isbn}
/// ```
///
/// Spring (Java): the `@RequestMapping` meta-annotation that `@GetMapping`
/// and friends carry, read with `AnnotatedElementUtils`:
/// ```java
/// RequestMapping mapping =
///     AnnotatedElementUtils.findMergedAnnotation(method, RequestMapping.class);
/// ```
abstract interface class Mapping {
  /// The HTTP method.
  HttpMethod get method;

  /// The path, possibly with `{variables}`: `/books/{isbn}`.
  String get path;

  /// Extra headers, each `'Name=value'` like Spring's
  /// `headers = "Name=value"`. A client sends them; entries that are only
  /// conditions for a server (`'Name'`, `'!Name'`, `'Name!=value'`) are
  /// ignored by clients, like Spring Cloud OpenFeign does.
  List<String> get headers;

  /// The media type of the response (`Accept` for a client).
  String? get produces;

  /// The media type of the request body (`Content-Type` for a client).
  String? get consumes;
}

/// Maps a request with any HTTP [method] to a path, like Spring's
/// `@RequestMapping`. Prefer the shortcuts `@GetMapping`, `@PostMapping`,
/// ...
///
/// ```dart
/// @RequestMapping('/books/{isbn}', method: HttpMethod.head)
/// Future<ResponseEntity<void>> exists(@PathVariable('isbn') String isbn);
/// ```
///
/// Spring (Java):
/// ```java
/// @RequestMapping(path = "/books/{isbn}", method = RequestMethod.HEAD)
/// ResponseEntity<Void> exists(@PathVariable("isbn") String isbn);
/// ```
class RequestMapping implements Mapping {
  /// Maps [path] with [method]; [headers] are `'Name=value'` entries.
  const RequestMapping(
    this.path, {
    this.method = HttpMethod.get,
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  @override
  final String path;

  @override
  final HttpMethod method;

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Maps a `GET` request, like Spring's `@GetMapping`.
///
/// ```dart
/// @GetMapping('/books/{isbn}')
/// Future<Book> find(@PathVariable('isbn') String isbn);
/// ```
///
/// Spring (Java):
/// ```java
/// @GetMapping("/books/{isbn}")
/// Book find(@PathVariable("isbn") String isbn);
/// ```
class GetMapping implements Mapping {
  /// Maps `GET` [path]; [headers] are `'Name=value'` entries.
  const GetMapping(
    this.path, {
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  @override
  HttpMethod get method => HttpMethod.get;

  @override
  final String path;

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Maps a `POST` request, like Spring's `@PostMapping`.
///
/// ```dart
/// @PostMapping('/books')
/// Future<Book> create(@RequestBody() Book book);
/// ```
///
/// Spring (Java):
/// ```java
/// @PostMapping("/books")
/// Book create(@RequestBody Book book);
/// ```
class PostMapping implements Mapping {
  /// Maps `POST` [path]; [headers] are `'Name=value'` entries.
  const PostMapping(
    this.path, {
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  @override
  HttpMethod get method => HttpMethod.post;

  @override
  final String path;

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Maps a `PUT` request, like Spring's `@PutMapping`.
///
/// ```dart
/// @PutMapping('/books/{isbn}')
/// Future<Book> replace(@PathVariable('isbn') String isbn, @RequestBody() Book book);
/// ```
///
/// Spring (Java):
/// ```java
/// @PutMapping("/books/{isbn}")
/// Book replace(@PathVariable("isbn") String isbn, @RequestBody Book book);
/// ```
class PutMapping implements Mapping {
  /// Maps `PUT` [path]; [headers] are `'Name=value'` entries.
  const PutMapping(
    this.path, {
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  @override
  HttpMethod get method => HttpMethod.put;

  @override
  final String path;

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Maps a `PATCH` request, like Spring's `@PatchMapping`.
///
/// ```dart
/// @PatchMapping('/books/{isbn}')
/// Future<Book> rename(@PathVariable('isbn') String isbn, @RequestBody() Map<String, Object?> changes);
/// ```
///
/// Spring (Java):
/// ```java
/// @PatchMapping("/books/{isbn}")
/// Book rename(@PathVariable("isbn") String isbn, @RequestBody Map<String, Object> changes);
/// ```
class PatchMapping implements Mapping {
  /// Maps `PATCH` [path]; [headers] are `'Name=value'` entries.
  const PatchMapping(
    this.path, {
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  @override
  HttpMethod get method => HttpMethod.patch;

  @override
  final String path;

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Maps a `DELETE` request, like Spring's `@DeleteMapping`.
///
/// ```dart
/// @DeleteMapping('/books/{isbn}')
/// Future<void> delete(@PathVariable('isbn') String isbn);
/// ```
///
/// Spring (Java):
/// ```java
/// @DeleteMapping("/books/{isbn}")
/// void delete(@PathVariable("isbn") String isbn);
/// ```
class DeleteMapping implements Mapping {
  /// Maps `DELETE` [path]; [headers] are `'Name=value'` entries.
  const DeleteMapping(
    this.path, {
    this.headers = const [],
    this.produces,
    this.consumes,
  });

  @override
  HttpMethod get method => HttpMethod.delete;

  @override
  final String path;

  @override
  final List<String> headers;

  @override
  final String? produces;

  @override
  final String? consumes;
}

/// Binds a parameter to a `{variable}` of the path, like Spring's
/// `@PathVariable`. Without a [name] the parameter name is used.
///
/// ```dart
/// @GetMapping('/books/{isbn}')
/// Future<Book> find(@PathVariable('isbn') String isbn);
///
/// @GetMapping('/authors/{id}')
/// Future<Author> author(@PathVariable() int id); // {id}
/// ```
///
/// Spring (Java):
/// ```java
/// Book find(@PathVariable("isbn") String isbn);
/// ```
class PathVariable {
  /// Binds the variable [name] (default: the parameter name).
  const PathVariable([this.name]);

  /// The variable name, or `null` for the parameter name.
  final String? name;
}

/// Binds a parameter to a query parameter, like Spring's `@RequestParam`.
/// Without a [name] the parameter name is used; a `null` value is left
/// out, a list repeats the parameter, and a `Map<String, ...>` adds one
/// query parameter per entry (its name is not used).
///
/// Whether the parameter is required and its default come from the Dart
/// parameter, as Spring does for Kotlin: a nullable parameter is optional
/// and a default value (`{int page = 0}`) is the default — Dart cannot
/// combine the optional positional [name] with `required:` /
/// `defaultValue:` attributes.
///
/// ```dart
/// @GetMapping('/books')
/// Future<List<Book>> search(@RequestParam('q') String query, {@RequestParam() int page = 0});
/// // GET /books?q=dune&page=0
///
/// @GetMapping('/books')
/// Future<List<Book>> filter(@RequestParam() Map<String, Object?> filters);
/// // GET /books?author=herbert&year=1965
/// ```
///
/// Spring (Java):
/// ```java
/// List<Book> search(@RequestParam("q") String query, @RequestParam int page);
/// List<Book> filter(@RequestParam Map<String, Object> filters);
/// ```
class RequestParam {
  /// Binds the query parameter [name] (default: the parameter name).
  const RequestParam([this.name]);

  /// The query parameter name, or `null` for the parameter name.
  final String? name;
}

/// Binds a parameter to a header, like Spring's `@RequestHeader`. Without
/// a [name] the parameter name is used; a `null` value is left out, a list
/// gives several values, and a `Map<String, ...>` adds one header per
/// entry (its name is not used). Required and default: as for
/// [RequestParam], from the Dart parameter.
///
/// ```dart
/// @PostMapping('/orders')
/// Future<Order> place(@RequestBody() Order order, @RequestHeader('X-Request-Id') String requestId);
///
/// @GetMapping('/orders')
/// Future<List<Order>> list(@RequestHeader() Map<String, String> headers);
/// ```
///
/// Spring (Java):
/// ```java
/// Order place(@RequestBody Order order, @RequestHeader("X-Request-Id") String requestId);
/// List<Order> list(@RequestHeader Map<String, String> headers);
/// ```
class RequestHeader {
  /// Binds the header [name] (default: the parameter name).
  const RequestHeader([this.name]);

  /// The header name, or `null` for the parameter name.
  final String? name;
}

/// Binds a parameter to a cookie, like Spring's `@CookieValue`. Without a
/// [name] the parameter name is used; a client sends the cookies of a call
/// in one `Cookie` header (`a=1; b=2`), leaving out `null` values.
/// Required and default: as for [RequestParam], from the Dart parameter.
///
/// ```dart
/// @GetMapping('/cart')
/// Future<Cart> cart(@CookieValue('SESSION') String session);
/// // Cookie: SESSION=...
/// ```
///
/// Spring (Java):
/// ```java
/// Cart cart(@CookieValue("SESSION") String session);
/// ```
class CookieValue {
  /// Binds the cookie [name] (default: the parameter name).
  const CookieValue([this.name]);

  /// The cookie name, or `null` for the parameter name.
  final String? name;
}

/// Binds a parameter to the request body, like Spring's `@RequestBody`.
///
/// ```dart
/// @PostMapping('/books')
/// Future<Book> create(@RequestBody() Book book); // JSON body
///
/// @PatchMapping('/books/{isbn}')
/// Future<Book> touch(@PathVariable() String isbn, @RequestBody(required: false) Book? book);
/// ```
///
/// Spring (Java):
/// ```java
/// Book create(@RequestBody Book book);
/// Book touch(@PathVariable String isbn, @RequestBody(required = false) Book book);
/// ```
class RequestBody {
  /// Marks the parameter; with [required] `false` the body may be absent
  /// (a `null` argument sends no body).
  const RequestBody({this.required = true});

  /// Whether a body is required (for a server; a client sends none for a
  /// `null` argument either way).
  final bool required;
}
