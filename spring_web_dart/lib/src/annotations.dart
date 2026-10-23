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

  /// The path, possibly with `{variables}`: `/books/{isbn}`; empty when the
  /// annotation has none (`@GetMapping()`): a client uses its base path
  /// (`@FeignClient(url:, path:)`), like Spring's mapping without `path`.
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
/// @RequestMapping.of(path: '/books/{isbn}', method: HttpMethod.head)
/// Future<ResponseEntity<void>> exists(@PathVariable('isbn') String isbn);
/// ```
///
/// Spring (Java):
/// ```java
/// @RequestMapping(path = "/books/{isbn}", method = RequestMethod.HEAD)
/// ResponseEntity<Void> exists(@PathVariable("isbn") String isbn);
/// ```
class RequestMapping implements Mapping {
  /// Maps [path] (none by default: the path of the client or of the class)
  /// with `GET`.
  const RequestMapping([this.path = ''])
    : method = HttpMethod.get,
      headers = const [],
      produces = null,
      consumes = null;

  /// Every attribute by name, like Spring's
  /// `@RequestMapping(path = "...", method = ...)`; [headers] are
  /// `'Name=value'` entries.
  const RequestMapping.of({
    this.path = '',
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

/// Maps a `GET` request, like Spring's `@GetMapping`. The path is optional
/// (`@GetMapping()` maps the base path of the client or of the class); a
/// path with other attributes is written `@GetMapping.of(path: ..., ...)`,
/// because Dart cannot combine an optional positional parameter with named
/// ones.
///
/// ```dart
/// @GetMapping('/books/{isbn}')
/// Future<Book> find(@PathVariable('isbn') String isbn);
///
/// @GetMapping.of(path: '/books', produces: MediaType.applicationJson)
/// Future<List<Book>> all();
/// ```
///
/// Spring (Java):
/// ```java
/// @GetMapping("/books/{isbn}")
/// Book find(@PathVariable("isbn") String isbn);
///
/// @GetMapping(path = "/books", produces = MediaType.APPLICATION_JSON_VALUE)
/// List<Book> all();
/// ```
class GetMapping implements Mapping {
  /// Maps `GET` [path] (none by default: the path of the client or of
  /// the class).
  const GetMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Every attribute by name, like Spring's
  /// `@GetMapping(path = "...", produces = "...")`; [headers] are
  /// `'Name=value'` entries.
  const GetMapping.of({
    this.path = '',
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
  /// Maps `POST` [path] (none by default: the path of the client or of
  /// the class).
  const PostMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Every attribute by name, like Spring's
  /// `@PostMapping(path = "...", produces = "...")`; [headers] are
  /// `'Name=value'` entries.
  const PostMapping.of({
    this.path = '',
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
  /// Maps `PUT` [path] (none by default: the path of the client or of
  /// the class).
  const PutMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Every attribute by name, like Spring's
  /// `@PutMapping(path = "...", produces = "...")`; [headers] are
  /// `'Name=value'` entries.
  const PutMapping.of({
    this.path = '',
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
  /// Maps `PATCH` [path] (none by default: the path of the client or of
  /// the class).
  const PatchMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Every attribute by name, like Spring's
  /// `@PatchMapping(path = "...", produces = "...")`; [headers] are
  /// `'Name=value'` entries.
  const PatchMapping.of({
    this.path = '',
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
  /// Maps `DELETE` [path] (none by default: the path of the client or of
  /// the class).
  const DeleteMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Every attribute by name, like Spring's
  /// `@DeleteMapping(path = "...", produces = "...")`; [headers] are
  /// `'Name=value'` entries.
  const DeleteMapping.of({
    this.path = '',
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
/// A path variable is [required] by default: a `null` argument is an error
/// naming the variable, whatever the type of the parameter. With
/// `required: false` a `null` argument gives an empty string, as Spring's
/// URI template expansion does. Dart cannot combine the optional positional
/// [name] with named attributes, so those are written
/// `@PathVariable.of(name: 'id', required: false)`.
///
/// ```dart
/// @GetMapping('/books/{isbn}')
/// Future<Book> find(@PathVariable('isbn') String isbn);
///
/// @GetMapping('/authors/{id}')
/// Future<Author> author(@PathVariable() int id); // {id}
///
/// @GetMapping('/books/{isbn}/pages')
/// Future<Pages> pages(@PathVariable.of(required: false) String? isbn);
/// ```
///
/// Spring (Java):
/// ```java
/// Book find(@PathVariable("isbn") String isbn);
/// Pages pages(@PathVariable(required = false) String isbn);
/// ```
class PathVariable {
  /// Binds the variable [name] (default: the parameter name); required.
  const PathVariable([this.name]) : required = true;

  /// Binds the variable [name] (default: the parameter name); [required]
  /// is `true` by default.
  const PathVariable.of({this.name, this.required = true});

  /// The variable name, or `null` for the parameter name.
  final String? name;

  /// Whether a value is required (see above).
  final bool required;
}

/// Binds a parameter to a query parameter, like Spring's `@RequestParam`.
/// Without a [name] the parameter name is used; a list repeats the
/// parameter, and a `Map<String, ...>` adds one query parameter per entry
/// (its name is not used).
///
/// A parameter is [required] by default: a `null` argument is an error
/// naming the parameter. A [defaultValue] is sent instead of `null` (and
/// implies `required: false`); a `null` argument of a parameter that is not
/// required is left out. As in Spring (Kotlin, `@Nullable`), a nullable
/// Dart parameter (`int? page`) is not required either, and a default
/// value of the Dart parameter (`{int page = 0}`) is simply the argument.
/// Dart cannot combine the optional positional [name] with named
/// attributes, so those are written
/// `@RequestParam.of(name: 'page', defaultValue: '0')`.
///
/// ```dart
/// @GetMapping('/books')
/// Future<List<Book>> search(
///   @RequestParam('q') String query,
///   {@RequestParam.of(name: 'page', defaultValue: '0') int? page});
/// // GET /books?q=dune&page=0
///
/// @GetMapping('/books')
/// Future<List<Book>> filter(@RequestParam() Map<String, Object?> filters);
/// // GET /books?author=herbert&year=1965
/// ```
///
/// Spring (Java):
/// ```java
/// List<Book> search(@RequestParam("q") String query,
///     @RequestParam(name = "page", defaultValue = "0") int page);
/// List<Book> filter(@RequestParam Map<String, Object> filters);
/// ```
class RequestParam {
  /// Binds the query parameter [name] (default: the parameter name);
  /// required.
  const RequestParam([this.name]) : required = true, defaultValue = null;

  /// Binds the query parameter [name] (default: the parameter name);
  /// [required] is `true` by default.
  const RequestParam.of({this.name, this.required = true, this.defaultValue});

  /// The query parameter name, or `null` for the parameter name.
  final String? name;

  /// Whether a value is required (see above).
  final bool required;

  /// The text sent when the argument is `null`, or `null` for none.
  final String? defaultValue;
}

/// Binds a parameter to a header, like Spring's `@RequestHeader`. Without
/// a [name] the parameter name is used; a list gives several values, and a
/// `Map<String, ...>` adds one header per entry (its name is not used).
/// [required] and [defaultValue] work as for [RequestParam]
/// (`@RequestHeader.of(name: 'X-Tenant', defaultValue: 'public')`).
///
/// ```dart
/// @PostMapping('/orders')
/// Future<Order> place(@RequestBody() Order order, @RequestHeader('X-Request-Id') String requestId);
///
/// @GetMapping('/orders')
/// Future<List<Order>> list(@RequestHeader() Map<String, String> headers);
///
/// @GetMapping('/orders')
/// Future<List<Order>> mine(@RequestHeader.of(name: 'X-Tenant', defaultValue: 'public') String? tenant);
/// ```
///
/// Spring (Java):
/// ```java
/// Order place(@RequestBody Order order, @RequestHeader("X-Request-Id") String requestId);
/// List<Order> list(@RequestHeader Map<String, String> headers);
/// List<Order> mine(@RequestHeader(name = "X-Tenant", defaultValue = "public") String tenant);
/// ```
class RequestHeader {
  /// Binds the header [name] (default: the parameter name); required.
  const RequestHeader([this.name]) : required = true, defaultValue = null;

  /// Binds the header [name] (default: the parameter name); [required] is
  /// `true` by default.
  const RequestHeader.of({this.name, this.required = true, this.defaultValue});

  /// The header name, or `null` for the parameter name.
  final String? name;

  /// Whether a value is required (see [RequestParam]).
  final bool required;

  /// The text sent when the argument is `null`, or `null` for none.
  final String? defaultValue;
}

/// Binds a parameter to a cookie, like Spring's `@CookieValue`. Without a
/// [name] the parameter name is used; a client sends the cookies of a call
/// in one `Cookie` header (`a=1; b=2`), leaving out `null` values.
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
