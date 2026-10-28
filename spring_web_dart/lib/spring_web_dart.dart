/// The web vocabulary shared by the Spring Dart server and HTTP client:
/// the annotations that map HTTP calls to methods, and the types that
/// describe requests and responses.
///
/// Import it to write a web API or to call one. The same annotations
/// serve both sides: on a `@RestController` class (with
/// `spring_boot_starter_web`) they say which requests a method answers;
/// on a `@FeignClient` interface (with `spring_boot_starter_feign`) they
/// say which request calling a method sends. It holds:
///
/// - the mapping annotations (`@RequestMapping`, `@GetMapping`,
///   `@PostMapping`, ...) and the parameter annotations (`@PathVariable`,
///   `@RequestParam`, `@RequestHeader`, `@CookieValue`, `@RequestBody`,
///   `@RequestPart`);
/// - the controller annotations (`@RestController`, `@ControllerAdvice`,
///   `@ExceptionHandler`, `@ResponseStatus`, `@CrossOrigin`);
/// - the HTTP types: `ResponseEntity`, `HttpHeaders`, `HttpStatus`,
///   `HttpMethod`, `MediaType`, `ProblemDetail` and the errors that carry
///   a response (`ResponseStatusException`, ...), multipart bodies and
///   uploaded files, path patterns;
/// - the server's request and response (`ServerHttpRequest`,
///   `ServerHttpResponse`);
/// - the client transports that send HTTP and WebSocket traffic
///   (`HttpTransport`, `WebSocketTransport`; `platformHttpTransport()`
///   picks the right one for the VM, Flutter or the browser);
/// - server-sent events (`EventStream<T>`, `ServerSentEvent<T>`).
///
/// ```dart
/// // The server side: GET /books/978-0 answers with the book as JSON.
/// @RestController()
/// @RequestMapping('/books')
/// class BookController {
///   BookController(this.books);
///   final BookService books;
///
///   @GetMapping('/{isbn}')
///   Future<Book> find(@PathVariable() String isbn) => books.find(isbn);
/// }
///
/// // The client side: calling find sends that same request.
/// @FeignClient('catalog', url: r'${catalog.url}')
/// abstract interface class CatalogClient {
///   @GetMapping('/books/{isbn}')
///   Future<Book> find(@PathVariable() String isbn);
/// }
/// ```
///
/// Platform transports are in `package:spring_web_dart/io.dart`
/// (`IoHttpTransport`, `IoWebSocketTransport`) and
/// `package:spring_web_dart/browser.dart` (`FetchHttpTransport`,
/// `BrowserWebSocketTransport`); test doubles in
/// `package:spring_web_dart/testing.dart` (`MockHttpTransport`,
/// `MockWebSocketTransport`, ...).
///
/// Spring (Java): `spring-web` (`org.springframework.web.bind.annotation`,
/// `org.springframework.http`, `org.springframework.http.client`).
library;

// Who sent a request (spring_core_dart's, shared with Spring Security).
export 'package:spring_core_dart/core.dart' show Principal;

export 'package:spring_web_dart/src/annotations.dart';
export 'package:spring_web_dart/src/client/http_request.dart';
export 'package:spring_web_dart/src/client/http_response.dart';
export 'package:spring_web_dart/src/client/http_transport.dart';
export 'package:spring_web_dart/src/client/streamed_http_response.dart';
export 'package:spring_web_dart/src/controller_annotations.dart';
export 'package:spring_web_dart/src/http_headers.dart';
export 'package:spring_web_dart/src/http_method.dart';
export 'package:spring_web_dart/src/http_status.dart';
export 'package:spring_web_dart/src/media_type.dart';
export 'package:spring_web_dart/src/multipart/multipart.dart';
export 'package:spring_web_dart/src/path_pattern.dart';
export 'package:spring_web_dart/src/problem_detail.dart';
export 'package:spring_web_dart/src/response_entity.dart';
export 'package:spring_web_dart/src/server/http_handler.dart';
export 'package:spring_web_dart/src/server/server_http_request.dart';
export 'package:spring_web_dart/src/server/server_http_response.dart';
export 'package:spring_web_dart/src/sse/event_stream.dart';
export 'package:spring_web_dart/src/sse/server_sent_event.dart';
export 'package:spring_web_dart/src/sse/sse_connection.dart';
export 'package:spring_web_dart/src/sse/sse_decoder.dart';
export 'package:spring_web_dart/src/websocket/web_socket_transport.dart';
