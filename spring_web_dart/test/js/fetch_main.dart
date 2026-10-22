// Compiled to JavaScript and run with node by fetch_transport_test.dart.
import 'dart:convert';

import 'package:spring_web_dart/browser.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

Future<void> main() async {
  final result = <String, Object?>{};
  final transport = platformHttpTransport();
  result['platform'] = transport is FetchHttpTransport;
  final response = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('data:application/json,{"isbn":"1"}'),
      headers: HttpHeaders({'Accept': 'application/json'}),
    ),
  );
  result['status'] = response.statusCode;
  result['body'] = jsonDecode(response.bodyText);
  result['contentType'] = response.headers['content-type'];
  try {
    await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('http://127.0.0.1:1/'),
      ),
    );
    result['refused'] = 'no error';
  } on HttpTransportException catch (error) {
    result['refused'] = error.isTimeout ? 'timeout' : 'error';
  }
  print('RESULT ${jsonEncode(result)}');
}
