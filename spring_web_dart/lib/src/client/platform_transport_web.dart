import 'package:spring_web_dart/src/client/fetch_transport.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';

/// Creates the transport for `platformHttpTransport` in the browser: a
/// `FetchHttpTransport`. [connectTimeout] is ignored, since `fetch` has no
/// connection timeout.
HttpTransport createTransport({Duration? connectTimeout}) =>
    FetchHttpTransport();
