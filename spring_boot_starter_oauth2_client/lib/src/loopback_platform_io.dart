// The dart:io side of LoopbackAuthorizationBrowser: the one-shot server on
// 127.0.0.1 and the system browser. Internal.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_oauth2_client/src/authorization_browser.dart';

/// Whether the loopback browser works here: yes with `dart:io`.
const bool supported = true;

const _page = '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Signed in</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 4em">
<p>You can close this window and return to the application.</p>
</body>
</html>
''';

/// Opens [uri] in the system's browser, without a shell.
Future<void> openSystemBrowser(Uri uri) async {
  if (uri.scheme != 'https' && uri.scheme != 'http') {
    throw ArgumentError.value(uri.scheme, 'uri', 'not http or https');
  }
  final url = uri.toString();
  final (executable, arguments) = switch (Platform.operatingSystem) {
    'macos' => ('open', [url]),
    'linux' => ('xdg-open', [url]),
    'windows' => ('rundll32', ['url.dll,FileProtocolHandler', url]),
    final other => throw UnsupportedError(
      'No system browser to open on $other: give the '
      'LoopbackAuthorizationBrowser an openBrowser function',
    ),
  };
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

/// The loopback round trip of `LoopbackAuthorizationBrowser.authorize`.
Future<Uri> authorize({
  required Uri redirectUri,
  required Uri Function(Uri redirectUri) authorizationUri,
  required Future<void> Function(Uri uri) open,
  required Duration timeout,
}) async {
  final path = redirectUri.path.isEmpty ? '/' : redirectUri.path;
  final explicitPort =
      redirectUri.scheme == 'http' &&
          const {'127.0.0.1', 'localhost', '[::1]', '::1'}.contains(
            redirectUri.host,
          ) &&
          redirectUri.hasPort
      ? redirectUri.port
      : 0;
  final server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    explicitPort,
  );
  final actual = Uri(
    scheme: 'http',
    host: '127.0.0.1',
    port: server.port,
    path: path,
  );
  final redirected = Completer<Uri>();
  // Set before any await: only the first matching request is taken.
  var taken = false;
  Future<void>? delivered;
  final subscription = server.listen((request) async {
    final response = request.response
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer');
    if (taken || request.method != 'GET' || request.uri.path != path) {
      response.statusCode = HttpStatus.notFound;
    } else {
      taken = true;
      response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..headers.set(
          'Content-Security-Policy',
          "default-src 'none'; style-src 'unsafe-inline'",
        )
        ..write(_page);
      redirected.complete(
        actual.replace(
          query: request.uri.hasQuery ? request.uri.query : null,
        ),
      );
    }
    // An error means the browser went away; nothing to do about it.
    final closed = response.close().then<void>((_) {}, onError: (_) {});
    if (taken) {
      delivered ??= closed; // the first taken one: the page
    }
    await closed;
  }, onError: (Object _) {});
  try {
    await open(authorizationUri(actual));
    return await redirected.future.timeout(
      timeout,
      onTimeout: () => throw AuthorizationCancelledException(
        'No redirect within ${timeout.inSeconds} seconds',
      ),
    );
  } finally {
    // The page reaches the browser before the server stops.
    await delivered?.timeout(const Duration(seconds: 2), onTimeout: () {});
    await subscription.cancel();
    await server.close(force: true);
  }
}
