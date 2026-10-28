import 'package:spring_web_dart/src/client/http_transport.dart';
import 'package:spring_web_dart/src/client/io_transport.dart';

/// Creates the transport for `platformHttpTransport` where `dart:io`
/// exists: an `IoHttpTransport` with [connectTimeout]. [credentials] is a
/// browser setting and ignored here.
HttpTransport createTransport({
  Duration? connectTimeout,
  FetchCredentials credentials = FetchCredentials.sameOrigin,
}) => IoHttpTransport(connectTimeout: connectTimeout);
