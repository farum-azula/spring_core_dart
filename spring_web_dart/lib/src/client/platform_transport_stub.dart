import 'package:spring_web_dart/src/client/http_transport.dart';

/// Stands in for `platformHttpTransport` on a platform with neither
/// `dart:io` nor `dart:js_interop`: always throws an [UnsupportedError],
/// since there is no HTTP client to build on. Pass your own transport
/// there.
HttpTransport createTransport({
  Duration? connectTimeout,
  FetchCredentials credentials = FetchCredentials.sameOrigin,
}) => throw UnsupportedError(
  'No HTTP transport for this platform; pass your own HttpTransport',
);
