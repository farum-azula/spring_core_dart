/// The HTTP and WebSocket clients for platforms with `dart:io` (the Dart
/// VM, Flutter on mobile and desktop): `IoHttpTransport` on `HttpClient`,
/// and `IoWebSocketTransport` on `dart:io`'s `WebSocket`.
///
/// Most applications never import this library. `platformHttpTransport()`
/// and `platformWebSocketTransport()` from
/// `package:spring_web_dart/spring_web_dart.dart` already pick these
/// transports outside the browser, and the Feign and WebSocket starters
/// call those functions. Import it when you need what only these
/// transports offer: an `HttpClient` of your own (proxy, certificates) or
/// headers in a WebSocket handshake.
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// // Give up quickly when the server cannot be reached.
/// final transport =
///     IoHttpTransport(connectTimeout: const Duration(seconds: 3));
/// ```
///
/// Spring (Java): `JdkClientHttpRequestFactory`, the client on the JDK's
/// `HttpClient`.
library;

export 'package:spring_web_dart/src/client/io_transport.dart';
export 'package:spring_web_dart/src/websocket/io_web_socket_transport.dart';
