// Compiled to JavaScript and run with node by fetch_transport_test.dart,
// behind a stand-in for `fetch` (and, for a browser without request
// streams, for `Request`): where a streamed body goes as a stream, where it
// is read whole first.
import 'dart:convert';
import 'dart:js_interop';

import 'package:spring_web_dart/browser.dart';
import 'package:spring_web_dart/spring_web_dart.dart';

@JS('calls')
external JSArray<JSString> get _calls;

Future<void> main() async {
  final transport = FetchHttpTransport();

  Stream<List<int>> chunks() async* {
    for (var i = 0; i < 4; i++) {
      yield List.filled(1000, i);
    }
  }

  Future<String> send(String host, StreamingBody body) async {
    try {
      final response = await transport.send(
        HttpRequest(
          method: HttpMethod.post,
          url: Uri.parse('https://$host/upload'),
          streamingBody: body,
        ),
      );
      return response.bodyText;
    } on HttpTransportException {
      return 'error';
    } on NonRepeatableBodyException {
      return 'not repeatable';
    }
  }

  final broken = StreamingBody(chunks());
  final result = <String, Object?>{
    // Chromium over HTTP/1.1: refused before any of it was read.
    'refused': await send('h1.example', StreamingBody(chunks())),
    'refusedAgain': await send('h1.example', StreamingBody(chunks())),
    'streams': await send('h2.example', StreamingBody(chunks(), length: 4000)),
    // Read in part, then the connection broke: not sent again.
    'broken': await send('broken.example', broken),
    'brokenAgain': await send('broken.example', broken),
    'calls': [for (final call in _calls.toDart) call.toDart],
  };
  // The test reads this line from the output of the node process.
  // ignore: avoid_print
  print('RESULT ${jsonEncode(result)}');
}
