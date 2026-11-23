// Compiled to JavaScript and run with node by fetch_transport_test.dart,
// behind stand-ins for a browser's `Request` and `fetch`.
import 'dart:convert';
import 'dart:js_interop';

import 'package:spring_web_dart/browser.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

@JS('modes')
external JSArray<JSString> get _modes;

Future<void> main() async {
  final transport = FetchHttpTransport();

  Future<String> send(
    Map<String, String> headers, {
    Set<String> sensitive = const {},
  }) async {
    try {
      final response = await transport.send(
        HttpRequest(
          method: HttpMethod.get,
          url: Uri.parse('https://api.example/books'),
          headers: HttpHeaders(headers),
          sensitiveHeaders: sensitive,
        ),
      );
      return response.bodyText;
    } on HttpTransportException catch (error) {
      return 'refused${error.isRetryable ? ' (retryable)' : ''}: '
          '${error.message.split(' ').last}';
    }
  }

  final result = <String, Object?>{
    'noCredentials': await send({'X-Plain': 'plain'}),
    'authorization': await send({'Authorization': 'Bearer a'}),
    'cookieAndAuthorization': await send({
      'Authorization': 'Bearer a',
      'Cookie': 'b=c',
    }),
    'apiKey': await send({'X-Api-Key': 'a'}),
    'declared': await send({'X-Grant': 'a'}, sensitive: const {'x-grant'}),
  };
  final notFollowing = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('https://api.example/books'),
      headers: HttpHeaders({'X-Api-Key': 'a'}),
      followRedirects: false,
    ),
  );
  result['notFollowing'] = notFollowing.statusCode;
  result['modes'] = [for (final mode in _modes.toDart) mode.toDart];
  // The test reads this line from the output of the node process.
  // ignore: avoid_print
  print('RESULT ${jsonEncode(result)}');
}
