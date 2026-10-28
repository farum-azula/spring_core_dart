/// Test doubles for the web: fake HTTP and WebSocket connections, and
/// in-memory server requests and responses.
///
/// Import it in tests only. It holds what a test needs to run web code
/// without a network:
/// - `MockHttpTransport` replaces the HTTP connection of a client (a
///   Feign client): it answers with prepared responses, event streams or
///   failures, and records what was sent;
/// - `MockWebSocketTransport` replaces the WebSocket connection of a
///   client, and the test plays the server;
/// - `MockServerHttpRequest`, `MockServerHttpResponse` and
///   `MockMultipartFile` are the request, response and upload that
///   `MockMvc` (in `spring_boot_starter_test`) passes to the application;
/// - `RequestPostProcessor` changes a `MockMvc` request before it is sent
///   (a logged-in user, a CSRF token).
///
/// ```dart
/// import 'package:spring_web_dart/testing.dart';
///
/// // The remote catalog service answers without a network.
/// final transport = MockHttpTransport()
///   ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'});
/// ```
///
/// Spring (Java): `MockRestServiceServer`, and the mock request and
/// response of `spring-test` (`MockHttpServletRequest`,
/// `MockHttpServletResponse`, `MockMultipartFile`).
library;

export 'package:spring_web_dart/src/testing/mock_http_transport.dart';
export 'package:spring_web_dart/src/testing/mock_server_http.dart';
export 'package:spring_web_dart/src/testing/mock_web_socket_transport.dart';
export 'package:spring_web_dart/src/testing/request_post_processor.dart';
