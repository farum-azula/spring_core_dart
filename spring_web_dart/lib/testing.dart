/// Test support: `MockHttpTransport` answers requests with prepared
/// responses (also event streams) and records what was sent, like
/// Spring's `MockRestServiceServer`; `MockWebSocketTransport` plays the
/// server of WebSocket connections.
///
/// ```dart
/// import 'package:spring_web_dart/testing.dart';
///
/// final transport = MockHttpTransport()
///   ..when(HttpMethod.get, '/books/1').respond(200, json: {'isbn': '1'});
/// ```
///
/// Spring (Java): `MockRestServiceServer`.
library;

export 'package:spring_web_dart/src/testing/mock_http_transport.dart';
export 'package:spring_web_dart/src/testing/mock_web_socket_transport.dart';
