// The dart:io side of LoopbackAuthorizationWindow: the one-shot server on
// 127.0.0.1 and the system browser. Internal.
import 'dart:async';
import 'dart:io';

import 'package:spring_boot_starter_flutter_security/src/window/authorization_window.dart';

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
      'LoopbackAuthorizationWindow an openBrowser function',
    ),
  };
  await Process.start(executable, arguments, mode: ProcessStartMode.detached);
}

const _notThisLogin = '''
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Not this sign-in</title></head>
<body style="font-family: sans-serif; text-align: center; margin-top: 4em">
<p>This is not the sign-in the application is waiting for.</p>
</body>
</html>
''';

/// The loopback round trip of `LoopbackAuthorizationWindow.authorize`.
Future<Uri> authorize({
  required Uri redirectUri,
  required Uri Function(Uri redirectUri) authorizationUri,
  required Future<void> Function(Uri uri) open,
  required Duration timeout,
}) async {
  final path = redirectUri.path.isEmpty ? '/' : redirectUri.path;
  // The host the registration names, when it is a loopback one: a
  // provider may want `localhost` exactly. Anything else (a template's
  // `{baseUrl}` left as another host) becomes 127.0.0.1 (RFC 8252 §7.3).
  final named = redirectUri.scheme == 'http'
      ? switch (redirectUri.host.toLowerCase()) {
          '127.0.0.1' => '127.0.0.1',
          'localhost' => 'localhost',
          '::1' || '[::1]' => '::1',
          _ => null,
        }
      : null;
  final host = named ?? '127.0.0.1';
  final explicitPort = named != null && redirectUri.hasPort
      ? redirectUri.port
      : 0;
  final servers = host == 'localhost'
      ? await _bindLocalhost(explicitPort)
      : [
          await HttpServer.bind(
            host == '::1'
                ? InternetAddress.loopbackIPv6
                : InternetAddress.loopbackIPv4,
            explicitPort,
          ),
        ];
  final actual = Uri(
    scheme: 'http',
    host: host,
    port: servers.first.port,
    path: path,
  );
  final page = authorizationUri(actual);
  // Only the redirect of this login ends the wait: the provider sends the
  // request's `state` back (RFC 6749 §4.1.2, errors too). Another request
  // on the path (a page of another site sending the browser here) is
  // answered and ignored. Without a `state` (a logout page), the first
  // request on the path is taken.
  final states = page.queryParametersAll['state'];
  final expectedState = states != null && states.length == 1
      ? states.single
      : null;
  final redirected = Completer<Uri>();
  // Set before any await: only the first matching request is taken.
  var taken = false;
  Future<void>? delivered;
  Future<void> handle(HttpRequest request) async {
    final response = request.response
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..headers.set('Referrer-Policy', 'no-referrer');
    var mine = false;
    if (taken || request.method != 'GET' || request.uri.path != path) {
      response.statusCode = HttpStatus.notFound;
    } else if (expectedState != null &&
        !_hasState(request.uri, expectedState)) {
      response
        ..statusCode = HttpStatus.badRequest
        ..headers.contentType = ContentType.html
        ..headers.set(
          'Content-Security-Policy',
          "default-src 'none'; style-src 'unsafe-inline'",
        )
        ..write(_notThisLogin);
    } else {
      taken = true;
      mine = true;
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
    if (mine) {
      delivered ??= closed; // the taken one: the page
    }
    await closed;
  }

  final subscriptions = [
    for (final server in servers) server.listen(handle, onError: (Object _) {}),
  ];
  try {
    await open(page);
    return await redirected.future.timeout(
      timeout,
      onTimeout: () => throw AuthorizationCancelledException(
        'No redirect within ${timeout.inSeconds} seconds',
      ),
    );
  } finally {
    // The page reaches the browser before the server stops.
    await delivered?.timeout(const Duration(seconds: 2), onTimeout: () {});
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    for (final server in servers) {
      await server.close(force: true);
    }
  }
}

/// The servers of `localhost`: 127.0.0.1 and, where the system has IPv6,
/// ::1 on the same port. The browser may resolve `localhost` to either,
/// so the port must be this window's on both: another program listening
/// on ::1 there would get the redirect, and the login would wait for
/// nothing. With a free port (`port` 0) ::1 is bound first and 127.0.0.1
/// takes its port, another pair when that one is taken on 127.0.0.1;
/// ::1 failing on a free port means the system has no IPv6 loopback,
/// and 127.0.0.1 serves alone. With an explicit port taken on ::1 by
/// another program (and IPv6 there), the login fails rather than
/// sending the redirect to that program.
Future<List<HttpServer>> _bindLocalhost(int port) async {
  if (port != 0) {
    final ipv4 = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    try {
      return [
        ipv4,
        await HttpServer.bind(InternetAddress.loopbackIPv6, port, v6Only: true),
      ];
    } on SocketException catch (e) {
      if (!await _hasIPv6Loopback()) {
        return [ipv4];
      }
      await ipv4.close(force: true);
      throw SocketException(
        'The redirect port $port of localhost is taken on ::1 by another '
        'program: the browser could send the redirect there',
        osError: e.osError,
        address: InternetAddress.loopbackIPv6,
        port: port,
      );
    }
  }
  SocketException? taken;
  for (var attempt = 0; attempt < 8; attempt++) {
    final HttpServer ipv6;
    try {
      ipv6 = await HttpServer.bind(
        InternetAddress.loopbackIPv6,
        0,
        v6Only: true,
      );
    } on SocketException {
      // No IPv6 loopback: 127.0.0.1 alone.
      return [await HttpServer.bind(InternetAddress.loopbackIPv4, 0)];
    }
    try {
      return [
        await HttpServer.bind(InternetAddress.loopbackIPv4, ipv6.port),
        ipv6,
      ];
    } on SocketException catch (e) {
      // That port is taken on 127.0.0.1: another pair.
      taken = e;
      await ipv6.close(force: true);
    }
  }
  throw taken!;
}

Future<bool> _hasIPv6Loopback() async {
  try {
    final probe = await ServerSocket.bind(
      InternetAddress.loopbackIPv6,
      0,
      v6Only: true,
    );
    await probe.close();
    return true;
  } on SocketException {
    return false;
  }
}

// Whether [uri] carries exactly one `state`, [expected], compared in
// constant time.
bool _hasState(Uri uri, String expected) {
  final List<String>? states;
  try {
    states = uri.queryParametersAll['state'];
  } on FormatException {
    return false; // a malformed query
  }
  if (states == null || states.length != 1) {
    return false;
  }
  final actual = states.single;
  if (actual.length != expected.length) {
    return false;
  }
  var difference = 0;
  for (var i = 0; i < actual.length; i++) {
    difference |= actual.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return difference == 0;
}
