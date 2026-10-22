import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/io_transport.dart';

/// `IoHttpTransport` on platforms with `dart:io`.
HttpTransport createTransport({Duration? connectTimeout}) =>
    IoHttpTransport(connectTimeout: connectTimeout);
