import 'package:spring_core_dart/spring_core_dart.dart';

/// A controller whose methods answer HTTP requests with their return value
/// as the body (JSON for objects), like Spring's `@RestController`
/// (`@Controller` + `@ResponseBody`). It is a bean (a `@Component`);
/// `spring_boot_starter_web` maps its `@GetMapping`, `@PostMapping`, ...
/// methods.
///
/// ```dart
/// @RestController()
/// @RequestMapping('/api/books')
/// class BookController {
///   BookController(this.books);
///   final BookService books;
///
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
  /// Marks a REST controller; [name] is the bean name (default: the class
  /// name, decapitalized).
  const RestController([super.name]);
}

/// Exception handlers and other advice shared by every controller, like
/// Spring's `@ControllerAdvice`. Its `@ExceptionHandler` methods handle
/// what the controllers' own handlers leave; several advice beans are
/// tried in `@Order`.
///
/// ```dart
/// @ControllerAdvice()
/// class ApiErrors {
///   @ExceptionHandler()
///   @ResponseStatus(HttpStatus.notFound)
///   ProblemDetail notFound(BookNotFoundException e) =>
///       ProblemDetail.forStatusAndDetail(HttpStatus.notFound, e.message);
/// }
/// ```
///
/// Spring (Java): `@ControllerAdvice`.
class ControllerAdvice extends Component {
  /// Marks a controller advice; [name] is the bean name.
  const ControllerAdvice([super.name]);
}

/// A [ControllerAdvice] whose handlers write their return value as the
/// body, like Spring's `@RestControllerAdvice`. Every advice here writes
/// its return value, so both mean the same.
class RestControllerAdvice extends ControllerAdvice {
  /// Marks a REST controller advice; [name] is the bean name.
  const RestControllerAdvice([super.name]);
}

/// The status of a handler's response, like Spring's `@ResponseStatus` on
/// a method. With [reason] the response is an error with that detail.
///
/// ```dart
/// @PostMapping()
/// @ResponseStatus(HttpStatus.created)
/// Future<Book> create(@RequestBody() NewBook book) => books.create(book);
/// ```
///
/// Spring (Java): `@ResponseStatus(HttpStatus.CREATED)`.
class ResponseStatus {
  /// The status [value] (an `HttpStatus` constant or a number); [reason]
  /// turns the response into an error with that detail.
  const ResponseStatus(this.value, {this.reason});

  /// The status code.
  final int value;

  /// The error detail, or `null` for a normal response.
  final String? reason;
}

/// Marks a method handling exceptions thrown by handlers, like Spring's
/// `@ExceptionHandler`: on a controller for its own handlers, on a
/// [ControllerAdvice] for all of them.
///
/// The exception types come from the method's exception parameter (the
/// usual way), or from [value] when the method takes none. The handler for
/// the most specific type wins. It may take the exception, the
/// `ServerHttpRequest` and the `ServerHttpResponse`, and return what a
/// controller method returns (`ProblemDetail`, `ResponseEntity`, an
/// object, ...).
///
/// ```dart
/// @ExceptionHandler()
/// ResponseEntity<ProblemDetail> conflict(StateError e) => ...;
///
/// @ExceptionHandler([TimeoutException])
/// @ResponseStatus(HttpStatus.gatewayTimeout)
/// void timeout() {}
/// ```
///
/// Spring (Java): `@ExceptionHandler(TimeoutException.class)`.
@BeanMethodAnnotation()
class ExceptionHandler {
  /// Handles the types of the method's exception parameter, or [value].
  const ExceptionHandler([this.value = const []]);

  /// Exception types matched by their exact runtime type (Dart has no
  /// reflection to test subtypes of a `Type`); use an exception parameter
  /// to match subtypes.
  final List<Type> value;
}

/// Allows cross-origin requests to a controller or a handler method, like
/// Spring's `@CrossOrigin`. Without [origins] (and [originPatterns]) every
/// origin is allowed.
///
/// ```dart
/// @RestController()
/// @CrossOrigin(origins: ['https://shop.example'])
/// class BookController { ... }
/// ```
///
/// Spring (Java): `@CrossOrigin(origins = "https://shop.example")`.
class CrossOrigin {
  /// Allows [origins] (or all), with the given headers, methods,
  /// credentials and pre-flight cache time.
  const CrossOrigin({
    this.origins = const [],
    this.originPatterns = const [],
    this.allowedHeaders = const [],
    this.exposedHeaders = const [],
    this.methods = const [],
    this.allowCredentials,
    this.maxAge,
  });

  /// Allowed origins (`https://shop.example`), or `*`.
  final List<String> origins;

  /// Allowed origin patterns (`https://*.example`).
  final List<String> originPatterns;

  /// Request headers allowed in actual requests (default: all).
  final List<String> allowedHeaders;

  /// Response headers the browser may read.
  final List<String> exposedHeaders;

  /// Allowed methods (default: the handler's).
  final List<String> methods;

  /// Whether cookies and credentials are sent (default: no).
  final bool? allowCredentials;

  /// How long a pre-flight answer may be cached, in seconds (default
  /// 1800).
  final int? maxAge;
}
