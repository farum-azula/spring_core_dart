import 'package:spring_core_dart/spring_core_dart.dart';

/// Marks a class whose methods answer HTTP requests: a REST controller.
///
/// This is the starting point of a web API built with
/// `spring_boot_starter_web`. The class is a bean, like any `@Component`,
/// so its dependencies are injected through the constructor. The server
/// sends each request to the method whose mapping annotation
/// (`@GetMapping`, `@PostMapping`, ...) matches its method and path, fills
/// the method's parameters from the request (`@PathVariable`,
/// `@RequestParam`, `@RequestBody`, ...), and writes the return value as
/// the response body: JSON for an object, text for a `String`. Return a
/// `ResponseEntity` to choose the status and headers as well.
///
/// This server has no HTML views, so a plain `@Controller` bean is mapped
/// in exactly the same way; `@RestController` says the intent.
///
/// ```dart
/// @RestController()
/// @RequestMapping('/api/books')
/// class BookController {
///   BookController(this.books);
///   final BookService books;
///
///   // GET /api/books/978-0 answers with the book as JSON.
///   @GetMapping('/{isbn}')
///   Future<Book> find(@PathVariable() String isbn) => books.find(isbn);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @RestController
/// @RequestMapping("/api/books")
/// class BookController {
///   @GetMapping("/{isbn}")
///   Book find(@PathVariable String isbn) { ... }
/// }
/// ```
class RestController extends Controller {
  /// Marks a REST controller; [name] is the bean name, by default the
  /// class name with a lower-case first letter (`bookController`).
  const RestController([super.name]);
}

/// Marks a bean whose `@ExceptionHandler` methods turn errors into
/// responses for every controller of the application.
///
/// Use it to answer the same kind of error the same way everywhere,
/// instead of repeating an `@ExceptionHandler` in each controller: for
/// example, a `BookNotFoundException` from any controller becomes a 404
/// problem. A controller's own handlers are tried first; the advice
/// handlers are used for what they leave, and also for errors raised
/// before any controller method runs (such as a path that no controller
/// maps). The advice beans are tried in `@Order`, as in Spring: the
/// first bean with a handler for the error answers it, with its handler
/// for the most specific exception type.
///
/// An advice applies to every controller unless it is narrowed with
/// [ControllerAdvice.of]: [basePackages] (library URI prefixes, such as `package:shop/admin/`),
/// [assignableTypes] (controllers of these types or their subtypes) or
/// [annotations] (controllers carrying one of these annotations). A
/// controller matching any of them is advised. A narrowed advice does not
/// answer errors raised before a controller method was chosen (a 404, a
/// 405), as in Spring.
///
/// ```dart
/// @ControllerAdvice()
/// class ApiErrors {
///   // Any controller throwing BookNotFoundException answers 404.
///   @ExceptionHandler()
///   ProblemDetail notFound(BookNotFoundException e) =>
///       ProblemDetail.forStatusAndDetail(HttpStatus.notFound, e.message);
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @ControllerAdvice
/// class ApiErrors {
///   @ExceptionHandler
///   ProblemDetail notFound(BookNotFoundException e) {
///     return ProblemDetail.forStatusAndDetail(
///         HttpStatus.NOT_FOUND, e.getMessage());
///   }
/// }
/// ```
class ControllerAdvice extends Component {
  /// Marks a controller advice for every controller; [name] is the bean
  /// name, by default the class name with a lower-case first letter.
  const ControllerAdvice([super.name])
    : basePackages = const [],
      assignableTypes = const [],
      annotations = const [];

  /// Marks a controller advice for the controllers that match
  /// [basePackages], [assignableTypes] or [annotations] (any of them).
  ///
  /// ```dart
  /// // Only the admin controllers answer errors this way.
  /// @ControllerAdvice.of(basePackages: ['package:shop/admin/'])
  /// class AdminErrors { ... }
  /// ```
  const ControllerAdvice.of({
    String? name,
    this.basePackages = const [],
    this.assignableTypes = const [],
    this.annotations = const [],
  }) : super(name);

  /// The controllers advised by where they are declared: prefixes of
  /// their library URI, such as `package:shop/admin/` (Spring's
  /// `basePackages`, with Dart library URIs instead of Java packages).
  final List<String> basePackages;

  /// The controllers advised by type: those of these types, or of a type
  /// that implements or extends one of them (Spring's `assignableTypes`).
  final List<Type> assignableTypes;

  /// The controllers advised by annotation: those whose class carries an
  /// annotation of one of these types, such as `RestController` (Spring's
  /// `annotations`; the annotation's exact type, not one it extends).
  final List<Type> annotations;
}

/// Marks a [ControllerAdvice] for a REST API, whose handlers write their
/// return value as the response body.
///
/// Here every advice writes its handlers' return values as the body, so
/// `@RestControllerAdvice` and `@ControllerAdvice` behave the same. It
/// exists so that code written for Spring reads the same; pick either.
///
/// Spring (Java): `@RestControllerAdvice`, which is `@ControllerAdvice`
/// plus `@ResponseBody`.
class RestControllerAdvice extends ControllerAdvice {
  /// Marks a REST controller advice for every controller; [name] is the
  /// bean name, by default the class name with a lower-case first letter.
  const RestControllerAdvice([super.name]);

  /// Marks a REST controller advice narrowed as [ControllerAdvice.of].
  const RestControllerAdvice.of({
    super.name,
    super.basePackages,
    super.assignableTypes,
    super.annotations,
  }) : super.of();
}

/// Sets the HTTP status of the response of a controller method or an
/// `@ExceptionHandler` method.
///
/// Without it, a method that returns normally answers `200 OK`. Use it
/// when another success status fits, such as `201 Created` after creating
/// something or `204 No Content` after a delete, or on an exception
/// handler to give the error's status. It applies to a plain return value
/// (also `null` or `void`) and to a returned `ProblemDetail`; a returned
/// `ResponseEntity` keeps its own status. With a [reason], the method's
/// result is ignored and the answer is an error: a `ProblemDetail` with
/// the status and the reason as its detail.
///
/// It is read on the handler method, or on the controller class for all
/// of its methods (a method's own annotation wins). Unlike Spring, an
/// exception class carrying it is not mapped to the status: throw a
/// `ResponseStatusException`, or write an `@ExceptionHandler`, instead.
///
/// ```dart
/// // POST /books answers 201 with the created book.
/// @PostMapping('/books')
/// @ResponseStatus(HttpStatus.created)
/// Future<Book> create(@RequestBody() NewBook book) => books.create(book);
/// ```
///
/// Spring (Java):
/// ```java
/// @PostMapping("/books")
/// @ResponseStatus(HttpStatus.CREATED)
/// Book create(@RequestBody NewBook book) { ... }
/// ```
class ResponseStatus {
  /// Answers with the status [value], an `HttpStatus` constant or a
  /// number; with a [reason], answers with an error instead of the
  /// method's result.
  const ResponseStatus(this.value, {this.reason});

  /// The status code of the response.
  final int value;

  /// The detail of the error response, or `null` to write the method's
  /// result normally.
  final String? reason;
}

/// Marks a method that turns an exception into the HTTP response.
///
/// Without it, an exception thrown by a controller method becomes a 500
/// (or the status of an `ErrorResponse` such as
/// `ResponseStatusException`). An exception handler lets the application
/// answer its own errors properly: a `BookNotFoundException` as a 404, a
/// conflict as a 409 with a useful message. On a controller, it handles
/// the errors of that controller's methods; on a [ControllerAdvice] bean,
/// those of every controller.
///
/// The exception types it handles come from its exception parameter (the
/// usual way; subtypes match too), or from [value] when the method does
/// not take the exception. When several handlers match, an exact type in
/// [value] wins, then the most specific parameter type. Besides the
/// exception, the method may take the `ServerHttpRequest`, the
/// `ServerHttpResponse` and the request's `HttpHeaders`. It returns what a
/// controller method returns (a `ProblemDetail`, a `ResponseEntity`, an
/// object, nothing), and `@ResponseStatus` sets the status.
///
/// ```dart
/// @RestController()
/// class BookController {
///   ...
///
///   // A StateError from this controller is a 409 with its message.
///   @ExceptionHandler()
///   ResponseEntity<ProblemDetail> conflict(StateError e) =>
///       ResponseEntity.status(HttpStatus.conflict).body(
///         ProblemDetail.forStatusAndDetail(HttpStatus.conflict, e.message),
///       );
///
///   // A slow backend: 504 without a body.
///   @ExceptionHandler([TimeoutException])
///   @ResponseStatus(HttpStatus.gatewayTimeout)
///   void timeout() {}
/// }
/// ```
///
/// Spring (Java):
/// ```java
/// @ExceptionHandler
/// ResponseEntity<ProblemDetail> conflict(IllegalStateException e) { ... }
///
/// @ExceptionHandler(TimeoutException.class)
/// @ResponseStatus(HttpStatus.GATEWAY_TIMEOUT)
/// void timeout() { }
/// ```
@BeanMethodAnnotation()
class ExceptionHandler {
  /// Handles the type of the method's exception parameter, or the types
  /// in [value].
  const ExceptionHandler([this.value = const []]);

  /// Exception types to handle, matched by their exact runtime type: a
  /// subtype does not match, because Dart cannot test whether one `Type`
  /// is a subtype of another at runtime. Use an exception parameter to
  /// match subtypes. Empty: the parameter's type decides.
  final List<Type> value;
}

/// Lets web pages from other origins call a controller or one of its
/// methods (CORS).
///
/// A browser blocks a page of `https://shop.example` from reading the
/// answers of `https://api.example` unless the server allows it with
/// `Access-Control-Allow-...` headers, and for most requests it first
/// asks with an `OPTIONS` "pre-flight" request. This annotation makes the
/// server answer both. Put it on the controller class for all its
/// methods, or on a method; when both carry it, their lists are merged
/// and the method's [allowCredentials], [allowPrivateNetwork] and
/// [maxAge] win. A global configuration for many paths is a
/// `CorsConfigurationSource` bean named `corsConfigurationSource` instead
/// (see `spring_boot_starter_web`).
///
/// Every attribute has a default, so `@CrossOrigin()` alone allows every
/// origin, the method the handler is mapped to (`DELETE` for a
/// `@DeleteMapping`), every request header, no credentials, and a
/// pre-flight cache of 30 minutes, as in Spring.
///
/// ```dart
/// // Only the shop's pages may call this API from a browser.
/// @RestController()
/// @CrossOrigin(origins: ['https://shop.example'])
/// class BookController { ... }
/// ```
///
/// Spring (Java):
/// ```java
/// @RestController
/// @CrossOrigin(origins = "https://shop.example")
/// class BookController { ... }
/// ```
class CrossOrigin {
  /// Allows [origins] (all when empty), with the given headers, methods,
  /// credentials and pre-flight cache time.
  const CrossOrigin({
    this.origins = const [],
    this.originPatterns = const [],
    this.allowedHeaders = const [],
    this.exposedHeaders = const [],
    this.methods = const [],
    this.allowCredentials,
    this.allowPrivateNetwork,
    this.maxAge,
  });

  /// The origins allowed to call, as a browser sends them
  /// (`https://shop.example`, compared without case), or `*` for any.
  /// Empty, with no [originPatterns] either: any origin. `*` cannot be
  /// combined with [allowCredentials]; use [originPatterns] then. Checked
  /// as Spring does, by `AllowedOrigins`: a value may list several,
  /// separated by commas, and a trailing `/` is ignored.
  final List<String> origins;

  /// Origin patterns: `*` matches any text, as Spring's `.*`
  /// (`https://*.example`), and a port list at the end the ports listed
  /// or, with `[*]`, any port or none (`http://localhost:[3000,3001]`,
  /// `http://localhost:[*]`). See `AllowedOrigins`.
  final List<String> originPatterns;

  /// The request headers a page may send (default: all).
  final List<String> allowedHeaders;

  /// The response headers, besides the simple ones, that the page's
  /// script may read (default: none).
  final List<String> exposedHeaders;

  /// The HTTP methods allowed (`'PUT'`, `'DELETE'`), for pre-flights and
  /// actual cross-origin requests; default: the method the handler is
  /// mapped to (`GET` for a `@GetMapping`, so not `HEAD`), as in Spring.
  final List<String> methods;

  /// Whether the browser may send cookies and other credentials, and let
  /// the page read the answer (default: no).
  final bool? allowCredentials;

  /// Whether pages of public sites may call this server on a private
  /// network, such as `localhost` or an office network (Chrome's Private
  /// Network Access: a pre-flight with
  /// `Access-Control-Request-Private-Network: true` gets
  /// `Access-Control-Allow-Private-Network: true`); default: no. With
  /// `true`, list [origins] or use [originPatterns]: all origins cannot be
  /// allowed then (the startup fails).
  final bool? allowPrivateNetwork;

  /// How long the browser may reuse a pre-flight answer, in seconds
  /// (default 1800, 30 minutes).
  final int? maxAge;
}
