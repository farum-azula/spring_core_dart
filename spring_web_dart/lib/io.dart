/// `IoHttpTransport` and `IoWebSocketTransport`: the HTTP and WebSocket
/// transports on `dart:io` (VM, Flutter mobile and desktop).
/// `platformHttpTransport()` / `platformWebSocketTransport()` from
/// `package:spring_web_dart/spring_web_dart.dart` pick them by themselves.
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// final transport =
///     IoHttpTransport(connectTimeout: const Duration(seconds: 3));
/// ```
///
/// Spring (Java): `JdkClientHttpRequestFactory`.
library;

export 'package:spring_web_dart/src/client/io_transport.dart';
export 'package:spring_web_dart/src/websocket/io_web_socket_transport.dart';
