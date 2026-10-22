import 'package:spring_web_dart/src/client/fetch_transport.dart';
import 'package:spring_web_dart/src/client/http_transport.dart';

/// `FetchHttpTransport` on the web (`connectTimeout` does not apply).
HttpTransport createTransport({Duration? connectTimeout}) =>
    FetchHttpTransport();
