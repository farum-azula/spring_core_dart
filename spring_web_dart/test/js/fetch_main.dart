// Compiled to JavaScript and run with node by fetch_transport_test.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:spring_web_dart/browser.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

@JS('testServer')
external JSString get _testServer;

@JS('globalThis')
external JSObject get _global;

Future<void> main() async {
  final host = _testServer.toDart;
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
  // The credentials option reaches fetch: a wrapper records it.
  final fetch = _global.getProperty<JSFunction>('fetch'.toJS);
  final credentials = <String?>[];
  _global.setProperty(
    'fetch'.toJS,
    ((JSAny resource, JSObject init) {
      credentials.add(
        init.getProperty<JSString?>('credentials'.toJS)?.toDart,
      );
      return fetch.callAsFunction(null, resource, init);
    }).toJS,
  );
  final data = HttpRequest(
    method: HttpMethod.get,
    url: Uri.parse('data:text/plain,x'),
  );
  await transport.send(data);
  await FetchHttpTransport(credentials: FetchCredentials.include).send(data);
  await platformHttpTransport(credentials: FetchCredentials.omit).send(data);
  _global.setProperty('fetch'.toJS, fetch);
  result['credentials'] = credentials;
  // Redirects not followed: a browser gives an opaque redirect (status 0,
  // accepted by HttpResponse); node's fetch gives the 302 itself.
  final manual = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('http://$host/redirect'),
      followRedirects: false,
    ),
  );
  result['manual'] = manual.statusCode;
  final manualStream = await transport.stream(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('http://$host/redirect'),
      followRedirects: false,
    ),
  );
  result['manualStream'] = manualStream.statusCode;
  await manualStream.discard();
  final followed = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('http://$host/redirect'),
    ),
  );
  result['followed'] = '${followed.statusCode}:${followed.bodyText}';
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
  final events = await transport.stream(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('http://$host/events'),
      headers: HttpHeaders({'Accept': MediaType.textEventStream}),
    ),
  );
  result['events'] = [
    await for (final event in events.body.transform(const SseDecoder()))
      '${event.id}:${event.data}',
  ];

  try {
    await transport.send(
      HttpRequest(
        method: HttpMethod.get,
        url: Uri.parse('http://$host/stall'),
        readTimeout: const Duration(milliseconds: 150),
      ),
    );
    result['readTimeout'] = 'no error';
  } on HttpTransportException catch (error) {
    result['readTimeout'] = error.isTimeout ? 'timeout' : 'error: $error';
  }
  // Data every 20 ms: a read timeout of 150 ms does not run out.
  final steady = await transport.send(
    HttpRequest(
      method: HttpMethod.get,
      url: Uri.parse('http://$host/events'),
      readTimeout: const Duration(milliseconds: 150),
    ),
  );
  result['steady'] = steady.bodyText
      .split('\n')
      .lastWhere((line) => line.startsWith('data: '))
      .substring(6);

  final sockets = platformWebSocketTransport();
  final socket = await sockets.connect(
    Uri.parse('ws://$host/ws'),
    timeout: const Duration(seconds: 5),
  );
  final messages = StreamIterator(socket.messages);
  final echo = <String>[];
  socket.sendMessage('hello');
  await messages.moveNext();
  echo.add(messages.current as String);
  socket.sendMessage(Uint8List.fromList([1, 2, 3]));
  await messages.moveNext();
  echo.add(jsonEncode(messages.current as Uint8List));
  socket.sendMessage('bye');
  await messages.moveNext();
  String headers;
  try {
    await sockets.connect(
      Uri.parse('ws://$host/ws'),
      headers: HttpHeaders({'Authorization': 'x'}),
    );
    headers = 'sent';
  } on WebSocketException {
    headers = 'rejected';
  }
  result['webSocket'] = {
    'platform': sockets is BrowserWebSocketTransport,
    'echo': echo,
    'closeCode': socket.closeStatus?.code,
    'headers': headers,
  };
  // The test reads this line from the output of the node process.
  // ignore: avoid_print
  print('RESULT ${jsonEncode(result)}');
}
