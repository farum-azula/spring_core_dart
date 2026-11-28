/// The web vocabulary shared by the Spring Dart server and HTTP client:
/// the annotations that map HTTP calls to methods, and the types that
/// describe requests and responses.
///
/// Import it to write a web API or to call one. On a `@RestController`
/// class (with `spring_boot_starter_web`) the mapping annotations say
/// which requests a method answers; on an HTTP service interface (with
/// `spring_boot_starter_restclient`) the exchange annotations say which
/// request calling a method sends. The parameter annotations serve both.
/// It holds:
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
///   `ServerHttpResponse`), and the origins a server allows
///   (`AllowedOrigins`, shared by CORS and WebSocket handshakes);
/// - `RestClient`, which calls an HTTP API and gives the answer back as
///   objects (URI templates, bodies through the `ObjectMapper`, 4xx and
///   5xx as `RestClientResponseException` instances, interceptors);
/// - the client transports that send HTTP and WebSocket traffic
///   (`HttpTransport`, `WebSocketTransport`; `platformHttpTransport()`
///   picks the right one for the VM, Flutter or the browser), and the
///   outgoing addresses they may call (`AllowedAddresses`,
///   `InetAddressFilter`);
/// - server-sent events (`EventStream<T>`, `ServerSentEvent<T>`), and the
///   `EventStreamRetryAdapter` that keeps a retried `@Retryable` method's
///   `EventStream` one;
/// - the annotations of HTTP service interfaces (`@HttpExchange`,
///   `@GetExchange`, `@PostExchange`, `@PutExchange`, `@PatchExchange`,
///   `@DeleteExchange`), `@ImportHttpServices` that puts them into
///   groups, and `HttpRequestAttribute`, the base of an annotation that
///   sets a request attribute on their calls;
/// - the `RequestDeadline` that limits the total time of a request and
///   the calls it makes (`spring_core_dart`'s, re-exported; an extension,
///   Spring has no counterpart).
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
/// @HttpExchange('/books')
/// abstract interface class CatalogClient {
///   @GetExchange('/{isbn}')
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
/// `org.springframework.http`, `org.springframework.http.client`,
/// `org.springframework.web.client`, `org.springframework.web.service`).
library;

// Who sent a request (spring_core_dart's, shared with Spring Security).
export 'package:spring_core_dart/core.dart' show Principal;

export 'package:spring_web_dart/src/annotations.dart';
export 'package:spring_web_dart/src/cache_control.dart';
export 'package:spring_web_dart/src/client/address/allowed_addresses.dart';
export 'package:spring_web_dart/src/client/address/inet_address_filter.dart';
export 'package:spring_web_dart/src/client/address/ip_address.dart';
export 'package:spring_web_dart/src/client/http_request.dart';
export 'package:spring_web_dart/src/client/http_response.dart';
export 'package:spring_web_dart/src/client/http_transport.dart';
export 'package:spring_web_dart/src/client/rest/client_http_request_interceptor.dart';
export 'package:spring_web_dart/src/client/rest/http_message_converter.dart';
export 'package:spring_web_dart/src/client/rest/rest_client.dart'
    hide StatusHandler;
export 'package:spring_web_dart/src/client/rest/rest_client_exception.dart';
export 'package:spring_web_dart/src/client/rest/uri_builder.dart';
export 'package:spring_web_dart/src/client/streamed_http_response.dart';
export 'package:spring_web_dart/src/controller_annotations.dart';
export 'package:spring_web_dart/src/http_headers.dart';
export 'package:spring_web_dart/src/http_method.dart';
export 'package:spring_web_dart/src/http_secrets.dart';
export 'package:spring_web_dart/src/http_status.dart';
export 'package:spring_web_dart/src/mapping_descriptions.dart';
export 'package:spring_web_dart/src/media_type.dart';
export 'package:spring_web_dart/src/multipart/multipart.dart';
export 'package:spring_web_dart/src/path_pattern.dart';
export 'package:spring_web_dart/src/problem_detail.dart';
export 'package:spring_web_dart/src/request_deadline.dart';
export 'package:spring_web_dart/src/response_entity.dart';
export 'package:spring_web_dart/src/server/allowed_origins.dart'
    hide matchesOriginPattern;
export 'package:spring_web_dart/src/server/http_handler.dart';
export 'package:spring_web_dart/src/server/server_http_request.dart';
export 'package:spring_web_dart/src/server/server_http_response.dart';
export 'package:spring_web_dart/src/service/http_exchange.dart';
export 'package:spring_web_dart/src/service/http_request_attribute.dart';
export 'package:spring_web_dart/src/service/import_http_services.dart';
export 'package:spring_web_dart/src/sse/event_stream.dart';
export 'package:spring_web_dart/src/sse/event_stream_retry_adapter.dart';
export 'package:spring_web_dart/src/sse/server_sent_event.dart';
export 'package:spring_web_dart/src/sse/sse_connection.dart';
export 'package:spring_web_dart/src/sse/sse_decoder.dart';
export 'package:spring_web_dart/src/websocket/web_socket_transport.dart';
