/// `FetchHttpTransport` and `BrowserWebSocketTransport`: the HTTP and
/// WebSocket transports of the browser (Flutter web, Dart on the web).
/// `platformHttpTransport()` / `platformWebSocketTransport()` from
/// `package:spring_web_dart/spring_web_dart.dart` pick them by themselves.
///
/// ```dart
/// import 'package:spring_web_dart/browser.dart';
///
/// final transport = FetchHttpTransport();
/// ```
///
/// Spring (Java): no equivalent (no browser).
library;

export 'package:spring_web_dart/src/client/fetch_transport.dart';
export 'package:spring_web_dart/src/websocket/browser_web_socket_transport.dart';
