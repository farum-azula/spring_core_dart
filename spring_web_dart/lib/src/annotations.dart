import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// What every request mapping annotation (`@GetMapping`, `@PostMapping`,
/// ..., `@RequestMapping`) exposes, so code reading annotations can find
/// any of them with `annotations.whereType<Mapping>()`.
///
/// The same annotations describe Feign clients (`@FeignClient` interfaces)
/// and controllers (`@RestController` classes of
/// `spring_boot_starter_web`). They are marked `@BeanMethodAnnotation()`,
/// so the generator describes a controller's mapped methods (parameters,
/// their annotations, the result type) in its bean definition.
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
///     AnnotatedElementUtils.findMergedAnnotation(
///         method, RequestMapping.class);
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
@BeanMethodAnnotation()
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
@BeanMethodAnnotation()
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
@BeanMethodAnnotation()
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
/// Future<Book> replace(
///   @PathVariable('isbn') String isbn,
///   @RequestBody() Book book,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @PutMapping("/books/{isbn}")
/// Book replace(@PathVariable("isbn") String isbn, @RequestBody Book book);
/// ```
@BeanMethodAnnotation()
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
/// Future<Book> rename(
///   @PathVariable('isbn') String isbn,
///   @RequestBody() Map<String, Object?> changes,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// @PatchMapping("/books/{isbn}")
/// Book rename(@PathVariable("isbn") String isbn,
///     @RequestBody Map<String, Object> changes);
/// ```
@BeanMethodAnnotation()
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
@BeanMethodAnnotation()
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
/// The parameter's type says whether a value is required: a nullable one
/// (`String? isbn`) takes `null` (a client then expands the variable to an
/// empty string, as Spring's URI template expansion does); otherwise a
/// missing value is an error naming the variable.
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
/// Without a [name] the parameter name is used; a list repeats the
/// parameter, and a `Map<String, ...>` adds one query parameter per entry
/// (its name is not used).
///
/// The Dart parameter says what Spring's `required` and `defaultValue`
/// say in Java: a nullable parameter (`Genre? genre`) is optional (a
/// server passes `null` when the request has none, a client leaves a
/// `null` argument out), a default value (`{int page = 0}`) is the value
/// when the request has none, and any other parameter is required (a
/// missing one is a 400 on a server).
///
/// ```dart
/// @GetMapping('/books')
/// Future<List<Book>> search(
///   @RequestParam('q') String query, {
///   @RequestParam('page') int page = 0,
///   @RequestParam('genre') Genre? genre,
/// });
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
///     @RequestParam(name = "page", defaultValue = "0") int page,
///     @RequestParam(name = "genre", required = false) Genre genre);
/// List<Book> filter(@RequestParam Map<String, Object> filters);
/// ```
class RequestParam {
  /// Binds the query parameter [name] (default: the parameter name).
  const RequestParam([this.name]);

  /// The query parameter name, or `null` for the parameter name.
  final String? name;
}

/// Binds a parameter to a header, like Spring's `@RequestHeader`. Without
/// a [name] the parameter name is used; a list gives several values, and a
/// `Map<String, ...>` adds one header per entry (its name is not used).
/// Optional and default values as for [RequestParam]: `String? tenant`,
/// `{String tenant = 'public'}`.
///
/// ```dart
/// @PostMapping('/orders')
/// Future<Order> place(
///   @RequestBody() Order order,
///   @RequestHeader('X-Request-Id') String requestId,
/// );
///
/// @GetMapping('/orders')
/// Future<List<Order>> list(@RequestHeader() Map<String, String> headers);
///
/// @GetMapping('/orders')
/// Future<List<Order>> mine({
///   @RequestHeader('X-Tenant') String tenant = 'public',
/// });
/// ```
///
/// Spring (Java):
/// ```java
/// Order place(@RequestBody Order order,
///     @RequestHeader("X-Request-Id") String requestId);
/// List<Order> list(@RequestHeader Map<String, String> headers);
/// List<Order> mine(
///     @RequestHeader(name = "X-Tenant", defaultValue = "public")
///     String tenant);
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
/// A nullable parameter makes the body optional (Spring's
/// `required = false`): a server passes `null` for an empty body, a client
/// sends none for a `null` argument.
///
/// ```dart
/// @PostMapping('/books')
/// Future<Book> create(@RequestBody() Book book); // JSON body
///
/// @PatchMapping('/books/{isbn}')
/// Future<Book> touch(
///   @PathVariable() String isbn,
///   @RequestBody() Book? book,
/// );
/// ```
///
/// Spring (Java):
/// ```java
/// Book create(@RequestBody Book book);
/// Book touch(@PathVariable String isbn,
///     @RequestBody(required = false) Book book);
/// ```
class RequestBody {
  /// Marks the parameter.
  const RequestBody();
}

/// Binds a part of a `multipart/form-data` request, like Spring's
/// `@RequestPart`: a file (`MultipartFile`, `List<MultipartFile>`), a text
/// field (`String`), or a part read into an object by its `Content-Type`
/// (JSON). Without a [name] the parameter name is used.
///
/// ```dart
/// @PostMapping.of(path: '/books', consumes: MediaType.multipartFormData)
/// Future<Book> create(
///   @RequestPart('book') @Valid() NewBook book,
///   @RequestPart('cover') MultipartFile cover,
/// ) => books.create(book, cover);
/// ```
///
/// A Feign client sends such a parameter as a part of a multipart body.
///
/// Spring (Java): `@RequestPart("cover") MultipartFile cover`.
class RequestPart {
  /// Binds the part [name] (default: the parameter name); a nullable
  /// parameter makes it optional.
  const RequestPart([this.name]);

  /// The part name, or `null` for the parameter name.
  final String? name;
}
