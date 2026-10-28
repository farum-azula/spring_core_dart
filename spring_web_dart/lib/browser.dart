/// The HTTP and WebSocket clients for code that runs in a browser (Flutter
/// web, Dart compiled to JavaScript or WebAssembly): `FetchHttpTransport`
/// on the browser's `fetch`, and `BrowserWebSocketTransport` on its
/// `WebSocket`.
///
/// Most applications never import this library. `platformHttpTransport()`
/// and `platformWebSocketTransport()` from
/// `package:spring_web_dart/spring_web_dart.dart` already pick these
/// transports on the web, and the Feign and WebSocket starters call those
/// functions. Import it when you want to create a browser transport
/// yourself, for example to declare it as a bean.
///
/// ```dart
/// import 'package:spring_web_dart/browser.dart';
///
/// // The web build of a Flutter app talks to its own origin.
/// final transport = FetchHttpTransport();
/// ```
///
/// Spring (Java): no equivalent, since Java does not run in a browser.
library;

export 'package:spring_web_dart/src/client/fetch_transport.dart';
export 'package:spring_web_dart/src/websocket/browser_web_socket_transport.dart';
