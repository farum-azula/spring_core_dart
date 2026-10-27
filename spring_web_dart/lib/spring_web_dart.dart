/// Spring Web for Dart: request mapping annotations shared by Feign
/// clients (`spring_boot_starter_feign`) and the coming web server,
/// `ResponseEntity`, `HttpHeaders`, `HttpStatus`, `MediaType`, HTTP and
/// WebSocket client transports for the VM, Flutter and the web, and
/// server-sent events (`EventStream<T>`, `ServerSentEvent<T>`).
///
/// ```dart
/// @FeignClient('catalog', url: r'${catalog.url}')
/// abstract interface class CatalogClient {
///   @GetMapping('/books/{isbn}')
///   Future<Book> find(@PathVariable('isbn') String isbn);
/// }
///
/// final transport = platformHttpTransport();
/// ```
///
/// Platform transports: `package:spring_web_dart/io.dart`
/// (`IoHttpTransport`, `IoWebSocketTransport`),
/// `package:spring_web_dart/browser.dart` (`FetchHttpTransport`,
/// `BrowserWebSocketTransport`); for tests
/// `package:spring_web_dart/testing.dart` (`MockHttpTransport`,
/// `MockWebSocketTransport`).
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
