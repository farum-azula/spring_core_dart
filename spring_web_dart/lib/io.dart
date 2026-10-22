/// `IoHttpTransport`: the HTTP transport on `dart:io` (VM, Flutter mobile
/// and desktop). `platformHttpTransport()` from
/// `package:spring_web_dart/spring_web_dart.dart` picks it by itself.
///
/// ```dart
/// import 'package:spring_web_dart/io.dart';
///
/// final transport = IoHttpTransport(connectTimeout: const Duration(seconds: 3));
/// ```
///
/// Spring (Java): `JdkClientHttpRequestFactory`.
library;

export 'package:spring_web_dart/src/client/io_transport.dart';
