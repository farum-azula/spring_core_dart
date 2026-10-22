/// `FetchHttpTransport`: the HTTP transport on the browser's `fetch`
/// (Flutter web, Dart on the web). `platformHttpTransport()` from
/// `package:spring_web_dart/spring_web_dart.dart` picks it by itself.
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
