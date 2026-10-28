import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/io_transport.dart';

/// Creates the transport for `platformHttpTransport` where `dart:io`
/// exists: an `IoHttpTransport` with [connectTimeout].
HttpTransport createTransport({Duration? connectTimeout}) =>
    IoHttpTransport(connectTimeout: connectTimeout);
