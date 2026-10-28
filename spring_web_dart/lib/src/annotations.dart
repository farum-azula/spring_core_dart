import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:spring_web_dart/src/http_method.dart';

/// The interface shared by all request mapping annotations (`@GetMapping`,
/// `@PostMapping`, ..., `@RequestMapping`): the HTTP method, path, headers
/// and media types of one HTTP call.
///
/// Applications never implement it; they put one of the annotations on a
/// method. It exists for the code that reads those annotations. The web
/// server (`spring_boot_starter_web`) reads it to send each request to the
/// right controller method, and the HTTP client (`spring_boot_starter_feign`)
/// reads it to build the request of a `@FeignClient` method. Because every
/// mapping annotation implements it, that code finds any of them with
/// `annotations.whereType<Mapping>()`.
///
/// The annotations are marked `@BeanMethodAnnotation()`. That makes the
/// code generator record each annotated method (its parameters, their
/// annotations and the result type) in the bean definition, which is where
/// the server finds the methods at startup.
///
/// ```dart
/// // A library printing the routes of a controller bean at startup.
/// final definition = registry.getBeanDefinition('bookController');
/// for (final method in definition.annotatedMethods) {
///   final mapping = method.annotations.whereType<Mapping>().firstOrNull;
///   if (mapping != null) {
///     print('${mapping.method} ${mapping.path}'); // GET /{isbn}
///   }
/// }
/// ```
///
/// Spring (Java): the `@RequestMapping` meta-annotation that `@GetMapping`
/// and the other shortcuts carry, read with `AnnotatedElementUtils`:
/// ```java
/// RequestMapping mapping =
///     AnnotatedElementUtils.findMergedAnnotation(
///         method, RequestMapping.class);
/// ```
abstract interface class Mapping {
  /// The HTTP method: fixed by a shortcut annotation (`GET` for
  /// `@GetMapping`), chosen freely with `@RequestMapping.of`.
  HttpMethod get method;

  /// The path, relative to the base path. It may hold `{variables}`
  /// (`/books/{isbn}`), bound with `@PathVariable`, and `${property}`
  /// placeholders, filled from the configuration at startup. A server also
  /// accepts the wildcards of `PathPattern` (`*`, `**`, `{name:regex}`).
  ///
  /// Empty (`@GetMapping()`) means the base path itself: the path of the
  /// class's `@RequestMapping` on a server, the `url` and `path` of
  /// `@FeignClient` on a client, as in Spring when `path` is left out.
  String get path;

  /// Header entries in Spring's syntax, such as `'X-Api-Version=2'`.
  ///
  /// A client sends every `'Name=value'` entry with each call (with
  /// `${property}` placeholders filled). A server reads every entry as a
  /// condition the request must meet for this method to be chosen:
  /// `'Name'` (the header is present), `'!Name'` (absent), `'Name=value'`
  /// and `'Name!=value'`. When no method meets them, the answer is a 400.
  /// A client ignores the condition-only forms, as Spring Cloud OpenFeign
  /// does.
  List<String> get headers;

  /// The media types of the response: one, or a comma-separated list
  /// (`MediaType.applicationJson`).
  ///
  /// A server chooses this method only when the request's `Accept` header
  /// allows one of them (otherwise the answer is a 406) and writes the
  /// body with it. A client sends the value as its `Accept` header.
  /// `null`: a server accepts any `Accept`; a client asks for JSON, or for
  /// `text/event-stream` when the method returns an event stream.
  String? get produces;

  /// The media types of the request body: one, or a comma-separated list.
  ///
  /// A server chooses this method only when the request's `Content-Type`
  /// is one of them (otherwise the answer is a 415). A client sends its
  /// body with this `Content-Type`: `MediaType.multipartFormData` makes a
  /// multipart body, `MediaType.applicationFormUrlencoded` writes a map or
  /// an object as form fields. `null`: a server accepts any body; a client
  /// picks the type from the body (JSON for an object, `text/plain` for a
  /// `String`, `application/octet-stream` for bytes).
  String? get consumes;
}

/// Maps HTTP requests of any method to a method, or, on a controller
/// class, gives the base path shared by all its methods.
///
/// It has two uses. On a `@RestController` class it sets the path prefix
/// of every method, and its [produces], [consumes] and [headers] apply to
/// them all: a method's own [produces] or [consumes] replaces the class's,
/// while [headers] add up. Its [method] does not matter there. On a
/// method, it is for the HTTP methods without a shortcut annotation
/// (`HEAD`, `OPTIONS`, `TRACE`); for the others, [GetMapping],
/// [PostMapping], [PutMapping], [PatchMapping] and [DeleteMapping] are
/// shorter. A Feign client does not read it on the interface: its base
/// path comes from `@FeignClient(path: ...)`.
///
/// ```dart
/// // Every path of this controller starts with /api/books.
/// @RestController()
/// @RequestMapping('/api/books')
/// class BookController {
///   BookController(this.books);
///   final BookService books;
///
///   // HEAD /api/books/978-0 tells whether the book exists, without a
///   // body. HEAD has no shortcut annotation.
///   @RequestMapping.of(path: '/{isbn}', method: HttpMethod.head)
///   ResponseEntity<void> exists(@PathVariable() String isbn) =>
///       ResponseEntity.status(
///         books.contains(isbn) ? HttpStatus.ok : HttpStatus.notFound,
///       ).build();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @RestController
/// @RequestMapping("/api/books")
/// class BookController {
///   @RequestMapping(path = "/{isbn}", method = RequestMethod.HEAD)
///   ResponseEntity<Void> exists(@PathVariable String isbn) { ... }
/// }
/// ```
@BeanMethodAnnotation()
class RequestMapping implements Mapping {
  /// Maps [path] with `GET`. This is the usual form on a class, where only
  /// the path counts (`@RequestMapping('/api/books')`). Without a path,
  /// the base path itself is mapped.
  const RequestMapping([this.path = ''])
    : method = HttpMethod.get,
      headers = const [],
      produces = null,
      consumes = null;

  /// Sets every attribute by name: on a method, to choose another HTTP
  /// [method] (`GET` by default); on a class, to add [produces],
  /// [consumes] or [headers] (`'Name=value'` entries) for all methods.
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

/// Maps HTTP `GET` requests to a method. On a controller, the method
/// answers them; on a Feign client, calling the method sends one.
///
/// `GET` reads data without changing anything, which makes this the most
/// common mapping. The path is optional: `@GetMapping()` maps the base
/// path (the class's `@RequestMapping` on a controller, the `@FeignClient`
/// path on a client). To give other attributes, write
/// `@GetMapping.of(path: ..., produces: ...)`: Dart does not allow an
/// optional positional parameter and named ones in the same constructor.
///
/// ```dart
/// @RestController()
/// @RequestMapping('/books')
/// class BookController {
///   BookController(this.books);
///   final BookService books;
///
///   // GET /books/978-0 answers with the book as JSON.
///   @GetMapping('/{isbn}')
///   Future<Book> find(@PathVariable() String isbn) => books.find(isbn);
///
///   // GET /books: the class's path itself; JSON only.
///   @GetMapping.of(produces: MediaType.applicationJson)
///   Future<List<Book>> all() => books.all();
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @RestController
/// @RequestMapping("/books")
/// class BookController {
///   @GetMapping("/{isbn}")
///   Book find(@PathVariable String isbn) { ... }
///
///   @GetMapping(produces = MediaType.APPLICATION_JSON_VALUE)
///   List<Book> all() { ... }
/// }
/// ```
@BeanMethodAnnotation()
class GetMapping implements Mapping {
  /// Maps `GET` requests to [path], relative to the base path; without a
  /// path, to the base path itself.
  const GetMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Maps `GET` requests with every attribute by name: [path], [headers]
  /// (`'Name=value'` entries), [produces] and [consumes].
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

/// Maps HTTP `POST` requests to a method. On a controller, the method
/// answers them; on a Feign client, calling the method sends one.
///
/// `POST` usually creates something or starts an action, with the data in
/// the request body (see [RequestBody]). The path is optional, and other
/// attributes are given with `@PostMapping.of(...)`, as for [GetMapping].
///
/// ```dart
/// // A Feign client: create sends the book as JSON to
/// // POST {catalog.url}/books and reads the stored book from the answer.
/// @FeignClient('catalog', url: r'${catalog.url}')
/// abstract interface class CatalogClient {
///   @PostMapping('/books')
///   Future<Book> create(@RequestBody() Book book);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @FeignClient(name = "catalog", url = "${catalog.url}")
/// interface CatalogClient {
///   @PostMapping("/books")
///   Book create(@RequestBody Book book);
/// }
/// ```
@BeanMethodAnnotation()
class PostMapping implements Mapping {
  /// Maps `POST` requests to [path], relative to the base path; without a
  /// path, to the base path itself.
  const PostMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Maps `POST` requests with every attribute by name: [path], [headers]
  /// (`'Name=value'` entries), [produces] and [consumes].
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

/// Maps HTTP `PUT` requests to a method. On a controller, the method
/// answers them; on a Feign client, calling the method sends one.
///
/// `PUT` replaces the whole resource at a known address with the request
/// body; sending the same request twice gives the same result. For a
/// partial change, use [PatchMapping].
///
/// ```dart
/// // PUT /books/978-0 with a complete book replaces the stored one.
/// @PutMapping('/books/{isbn}')
/// Future<Book> replace(
///   @PathVariable() String isbn,
///   @RequestBody() Book book,
/// ) => books.replace(isbn, book);
/// ```
///
/// Spring (Java):
/// ```java
/// @PutMapping("/books/{isbn}")
/// Book replace(@PathVariable String isbn, @RequestBody Book book) { ... }
/// ```
@BeanMethodAnnotation()
class PutMapping implements Mapping {
  /// Maps `PUT` requests to [path], relative to the base path; without a
  /// path, to the base path itself.
  const PutMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Maps `PUT` requests with every attribute by name: [path], [headers]
  /// (`'Name=value'` entries), [produces] and [consumes].
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

/// Maps HTTP `PATCH` requests to a method. On a controller, the method
/// answers them; on a Feign client, calling the method sends one.
///
/// `PATCH` changes part of a resource: the body carries only the fields
/// to change. To replace the whole resource, use [PutMapping].
///
/// ```dart
/// // PATCH /books/978-0 with {"title": "Dune"} renames the book and
/// // leaves its other fields alone.
/// @PatchMapping('/books/{isbn}')
/// Future<Book> update(
///   @PathVariable() String isbn,
///   @RequestBody() Map<String, Object?> changes,
/// ) => books.update(isbn, changes);
/// ```
///
/// Spring (Java):
/// ```java
/// @PatchMapping("/books/{isbn}")
/// Book update(@PathVariable String isbn,
///     @RequestBody Map<String, Object> changes) { ... }
/// ```
@BeanMethodAnnotation()
class PatchMapping implements Mapping {
  /// Maps `PATCH` requests to [path], relative to the base path; without a
  /// path, to the base path itself.
  const PatchMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Maps `PATCH` requests with every attribute by name: [path], [headers]
  /// (`'Name=value'` entries), [produces] and [consumes].
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

/// Maps HTTP `DELETE` requests to a method. On a controller, the method
/// answers them; on a Feign client, calling the method sends one.
///
/// `DELETE` removes the resource at the path. A controller method that
/// returns nothing answers `200 OK` with no body; add
/// `@ResponseStatus(HttpStatus.noContent)` for the more usual 204.
///
/// ```dart
/// // DELETE /books/978-0 removes the book and answers 204.
/// @DeleteMapping('/books/{isbn}')
/// @ResponseStatus(HttpStatus.noContent)
/// Future<void> delete(@PathVariable() String isbn) => books.delete(isbn);
/// ```
///
/// Spring (Java):
/// ```java
/// @DeleteMapping("/books/{isbn}")
/// @ResponseStatus(HttpStatus.NO_CONTENT)
/// void delete(@PathVariable String isbn) { ... }
/// ```
@BeanMethodAnnotation()
class DeleteMapping implements Mapping {
  /// Maps `DELETE` requests to [path], relative to the base path; without
  /// a path, to the base path itself.
  const DeleteMapping([this.path = ''])
    : headers = const [],
      produces = null,
      consumes = null;

  /// Maps `DELETE` requests with every attribute by name: [path],
  /// [headers] (`'Name=value'` entries), [produces] and [consumes].
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

/// Binds a method parameter to a `{variable}` of the mapping's path.
///
/// Use it when the path itself names the resource, as in `/books/{isbn}`.
/// On a controller, the server takes the value from the request path and
/// converts it to the parameter's type: a `String`, a number, a `bool`,
/// an enum, a `DateTime`, a `Duration`, a `Uri`, or a `List` of them. On a
/// Feign client, the argument is percent-encoded and written into the
/// path. Without a [name], the parameter's own name is the variable name.
/// Every `{variable}` of the path needs such a parameter and every such
/// parameter needs a variable; a mismatch is reported at startup.
///
/// A server always has a value once the path matched. A client needs one:
/// a `null` argument is an `ArgumentError`, unless the parameter is
/// nullable (`String? isbn`); then the variable becomes an empty string,
/// as in Spring's URI templates.
///
/// ```dart
/// // GET /books/978-0: isbn is '978-0'.
/// @GetMapping('/books/{isbn}')
/// Future<Book> find(@PathVariable() String isbn) => books.find(isbn);
///
/// // The parameter has another name than the variable, so name it.
/// @GetMapping('/authors/{id}/books')
/// Future<List<Book>> byAuthor(@PathVariable('id') int authorId) =>
///     books.byAuthor(authorId);
/// ```
///
/// Spring (Java):
/// ```java
/// @GetMapping("/books/{isbn}")
/// Book find(@PathVariable String isbn) { ... }
///
/// @GetMapping("/authors/{id}/books")
/// List<Book> byAuthor(@PathVariable("id") int authorId) { ... }
/// ```
class PathVariable {
  /// Binds the path variable [name]; without one, the variable named like
  /// the parameter.
  const PathVariable([this.name]);

  /// The variable name, or `null` to use the parameter's name.
  final String? name;
}

/// Binds a method parameter to a query parameter (`?q=dune`).
///
/// Use it for the optional inputs of a call that are not part of the
/// resource's address: search terms, filters, page numbers. On a
/// controller, the server reads the value from the query string, or from
/// the fields of a form or multipart body when the query has none, and
/// converts it to the parameter's type (a `String`, a number, a `bool`, an
/// enum, a `DateTime`, ...). A `List` parameter takes every value of a
/// repeated parameter, and a `MultipartFile` parameter takes an uploaded
/// file. On a Feign client, the argument is added to the query string; a
/// `List` repeats the parameter. Without a [name], the parameter's own
/// name is used. A `Map<String, ...>` parameter stands for all query
/// parameters: a server fills it with every one it received, a client
/// sends one query parameter per entry (the [name] is not used then).
///
/// The Dart parameter decides whether a value is required:
///
/// * a nullable parameter (`Genre? genre`) is optional: a server passes
///   `null` when the request has no value, a client leaves a `null`
///   argument out;
/// * a parameter with a default value (`{int page = 0}`) is optional too:
///   a server passes the default when the request has no value;
/// * any other parameter is required: a request without it gets a 400.
///
/// A controller parameter with a simple type and no annotation at all is
/// read as a query parameter of the same name, as in Spring.
///
/// ```dart
/// // GET /books?q=dune&page=2&genre=scienceFiction
/// @GetMapping('/books')
/// Future<List<Book>> search(
///   @RequestParam('q') String query, {
///   @RequestParam() int page = 0,
///   @RequestParam() Genre? genre,
/// }) => books.search(query, page: page, genre: genre);
///
/// // GET /books?author=herbert&year=1965: any filter the caller sends.
/// @GetMapping('/books/filter')
/// Future<List<Book>> filter(
///   @RequestParam() Map<String, String> filters,
/// ) => books.filter(filters);
/// ```
///
/// Spring (Java) says in the annotation what the Dart parameter says by
/// its type (`required = false`, `defaultValue`):
/// ```java
/// List<Book> search(@RequestParam("q") String query,
///     @RequestParam(defaultValue = "0") int page,
///     @RequestParam(required = false) Genre genre) { ... }
/// List<Book> filter(@RequestParam Map<String, String> filters) { ... }
/// ```
class RequestParam {
  /// Binds the query parameter [name]; without one, the parameter named
  /// like the method parameter.
  const RequestParam([this.name]);

  /// The query parameter name, or `null` to use the parameter's name.
  final String? name;
}

/// Binds a method parameter to an HTTP header of the request.
///
/// Use it for values that travel in headers rather than in the path or
/// the body: a request id, a tenant, an API version, a token. On a
/// controller, the server reads the header and converts it to the
/// parameter's type; a `List` takes all its values. On a Feign client, the
/// argument is sent as that header, replacing a value of the same name
/// from the mapping's `headers`. Without a [name], the parameter's own name
/// is the header name. A `Map<String, ...>` parameter stands for all
/// headers: a server fills it with every header of the request, a client
/// sends one header per entry. On a server, an `HttpHeaders` parameter
/// gets all headers too.
///
/// Whether a value is required follows the Dart parameter, as for
/// [RequestParam]: nullable (`String? tenant`) or with a default
/// (`{String tenant = 'public'}`) is optional, anything else is required
/// (a missing header is a 400 on a server).
///
/// ```dart
/// // The caller's id for the request, echoed into the logs.
/// @PostMapping('/orders')
/// Future<Order> place(
///   @RequestBody() Order order,
///   @RequestHeader('X-Request-Id') String requestId,
/// ) => orders.place(order, requestId: requestId);
///
/// // Requests without X-Tenant use the public tenant.
/// @GetMapping('/orders')
/// Future<List<Order>> list({
///   @RequestHeader('X-Tenant') String tenant = 'public',
/// }) => orders.list(tenant);
/// ```
///
/// Spring (Java), with `defaultValue` where Dart uses a default value:
/// ```java
/// Order place(@RequestBody Order order,
///     @RequestHeader("X-Request-Id") String requestId) { ... }
/// List<Order> list(
///     @RequestHeader(name = "X-Tenant", defaultValue = "public")
///     String tenant) { ... }
/// ```
class RequestHeader {
  /// Binds the header [name]; without one, the header named like the
  /// parameter.
  const RequestHeader([this.name]);

  /// The header name, or `null` to use the parameter's name.
  final String? name;
}

/// Binds a method parameter to a cookie of the request.
///
/// Use it when a value comes in a cookie, such as a session id or a user
/// preference set by a browser. On a controller, the server reads the
/// cookie from the request's `Cookie` header and converts it to the
/// parameter's type. On a Feign client, the cookies of a call are sent
/// together in one `Cookie` header (`a=1; b=2`); a `null` argument is left
/// out. Without a [name], the parameter's own name is the cookie name.
/// Whether a value is required follows the Dart parameter, as for
/// [RequestParam].
///
/// ```dart
/// // Cookie: SESSION=4f2a... picks the shopping cart of that session.
/// @GetMapping('/cart')
/// Future<Cart> cart(@CookieValue('SESSION') String session) =>
///     carts.forSession(session);
/// ```
///
/// Spring (Java):
/// ```java
/// @GetMapping("/cart")
/// Cart cart(@CookieValue("SESSION") String session) { ... }
/// ```
class CookieValue {
  /// Binds the cookie [name]; without one, the cookie named like the
  /// parameter.
  const CookieValue([this.name]);

  /// The cookie name, or `null` to use the parameter's name.
  final String? name;
}

/// Binds a method parameter to the request body.
///
/// Use it for the data a `POST`, `PUT` or `PATCH` sends. On a controller,
/// the server reads the body as JSON into the parameter's type; a body
/// with another `Content-Type` gets a 415. Some types are read
/// differently: a `String` gets the text, a `Uint8List` the raw bytes, a
/// `Stream` of bytes the body as it arrives, and a `Map` also accepts the
/// fields of a form (`application/x-www-form-urlencoded`). With `@Valid()`
/// on the parameter, the object is validated and a failure is a 400
/// listing the field errors. On a Feign client, the argument becomes the
/// body: JSON for an object, text for a `String`, the bytes for a
/// `Uint8List`, form fields when the mapping `consumes` a form. The only
/// parameter of a Feign method without an annotation is the body too.
///
/// A method has at most one body. The body is required unless the
/// parameter is nullable (`Book? book`) or has a default value: a server
/// then passes `null` (or the default) for an empty body, where it would
/// otherwise answer 400, and a client sends no body for a `null` argument.
///
/// ```dart
/// // POST /books with {"isbn": "978-0", "title": "Dune"}.
/// @PostMapping('/books')
/// @ResponseStatus(HttpStatus.created)
/// Future<Book> create(@RequestBody() @Valid() Book book) =>
///     books.create(book);
///
/// // The body is optional: without one, the book is only touched.
/// @PatchMapping('/books/{isbn}')
/// Future<Book> touch(
///   @PathVariable() String isbn,
///   @RequestBody() Book? book,
/// ) => books.touch(isbn, book);
/// ```
///
/// Spring (Java), with `required = false` where Dart uses a nullable type:
/// ```java
/// Book create(@RequestBody @Valid Book book) { ... }
/// Book touch(@PathVariable String isbn,
///     @RequestBody(required = false) Book book) { ... }
/// ```
class RequestBody {
  /// Marks the parameter that holds the request body.
  const RequestBody();
}

/// Binds a method parameter to one part of a `multipart/form-data`
/// request: an uploaded file, a text field, or a JSON part.
///
/// Use it for uploads, often with data next to the file, as an HTML form
/// with a file input sends them. On a controller, the server finds the
/// part by name and gives it according to the parameter's type: a
/// `MultipartFile` (or a `List<MultipartFile>` for several files under
/// one name), a `String` or other simple value for a text field, bytes
/// (`Uint8List`), or an object read from the part's JSON (validated with
/// `@Valid()`). A request that is not multipart gets a 400. On a Feign
/// client, each such parameter becomes a part of a multipart body; the
/// mapping then needs no `consumes`. Without a [name], the parameter's own
/// name is the part name.
///
/// The part is required unless the parameter is nullable
/// (`MultipartFile? cover`) or has a default value; a missing required
/// part is a 400 on a server, and a `null` argument an `ArgumentError` on a
/// client.
///
/// ```dart
/// // A form posting the book's data as JSON and its cover image.
/// @PostMapping.of(path: '/books', consumes: MediaType.multipartFormData)
/// Future<Book> create(
///   @RequestPart('book') @Valid() NewBook book,
///   @RequestPart('cover') MultipartFile cover,
/// ) => books.create(book, cover);
/// ```
///
/// Spring (Java):
/// ```java
/// @PostMapping(path = "/books",
///     consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
/// Book create(@RequestPart("book") @Valid NewBook book,
///     @RequestPart("cover") MultipartFile cover) { ... }
/// ```
class RequestPart {
  /// Binds the part [name]; without one, the part named like the
  /// parameter.
  const RequestPart([this.name]);

  /// The part name, or `null` to use the parameter's name.
  final String? name;
}
