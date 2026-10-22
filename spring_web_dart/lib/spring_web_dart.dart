/// Spring Web for Dart: request mapping annotations shared by Feign
/// clients (`spring_boot_starter_feign`) and the coming web server,
/// `ResponseEntity`, `HttpHeaders`, `HttpStatus`, `MediaType`, and an HTTP
/// client transport for the VM, Flutter and the web.
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
/// (`IoHttpTransport`), `package:spring_web_dart/browser.dart`
/// (`FetchHttpTransport`); for tests `package:spring_web_dart/testing.dart`
/// (`MockHttpTransport`).
///
/// Spring (Java): `spring-web` (`org.springframework.web.bind.annotation`,
/// `org.springframework.http`, `org.springframework.http.client`).
library;

export 'package:spring_web_dart/src/annotations.dart';
export 'package:spring_web_dart/src/client/http_request.dart';
export 'package:spring_web_dart/src/client/http_response.dart';
export 'package:spring_web_dart/src/client/http_transport.dart';
export 'package:spring_web_dart/src/http_headers.dart';
export 'package:spring_web_dart/src/http_method.dart';
export 'package:spring_web_dart/src/http_status.dart';
export 'package:spring_web_dart/src/media_type.dart';
export 'package:spring_web_dart/src/response_entity.dart';
