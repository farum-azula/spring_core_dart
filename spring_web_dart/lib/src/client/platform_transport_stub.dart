import 'package:spring_web_dart/src/client/http_transport.dart';

/// No transport on platforms without `dart:io` or `dart:js_interop`.
HttpTransport createTransport({Duration? connectTimeout}) =>
    throw UnsupportedError(
      'No HTTP transport for this platform; pass your own HttpTransport',
    );
