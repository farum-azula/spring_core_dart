@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// FetchHttpTransport runs on the web: test/js/fetch_main.dart is compiled
// to JavaScript and run with node (whose fetch supports data: URLs). This
// also proves the main library compiles for the web.
void main() {
  test('FetchHttpTransport under node', () async {
    final node = await _hasNode();
    if (!node) {
      markTestSkipped('node is not on the PATH');
      return;
    }
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:spring_web_dart/'),
    );
    final package = Directory.fromUri(lib!).parent.path;
    final temp = Directory.systemTemp.createTempSync('spring_web_fetch_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final output = '${temp.path}/fetch_main.js';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-o',
      output,
      'test/js/fetch_main.dart',
    ], workingDirectory: package);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    // A server for the streaming and WebSocket checks.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/ws' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((message) {
          if (message == 'bye') {
            unawaited(socket.close(4000, 'asked'));
          } else {
            socket.add(message);
          }
        });
        return;
      }
      if (request.uri.path == '/redirect') {
        request.response
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..statusCode = HttpStatus.found
          ..headers.set('Location', '/target');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/target') {
        request.response
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..write('there');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/stall') {
        // A first chunk, then silence: the read timeout runs out.
        final response = request.response
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..bufferOutput = false
          ..write('first');
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 600));
        response.write('late');
        await response.close();
        return;
      }
      final response = request.response
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..headers.contentType = ContentType('text', 'event-stream')
        ..bufferOutput = false;
      for (var i = 1; i <= 3; i++) {
        response.write('id: $i\ndata: tick $i\n\n');
        await response.flush();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await response.close();
    });
    final run = await Process.run('node', [
      '-e',
      // One script, written on several lines to stay within 80 columns.
      // ignore: no_adjacent_strings_in_list
      'globalThis.self = globalThis; '
          'globalThis.testServer = "127.0.0.1:${server.port}"; '
          'require(${jsonEncode(output)})',
    ]);
    expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
    final line = (run.stdout as String)
        .split('\n')
        .firstWhere((l) => l.startsWith('RESULT '));
    final result = jsonDecode(line.substring(7)) as Map<String, Object?>;
    expect(result, {
      'platform': true,
      'status': 200,
      'body': {'isbn': '1'},
      'contentType': 'application/json',
      'credentials': ['same-origin', 'include', 'omit'],
      // Node's fetch gives the redirect itself; a browser, status 0.
      'manual': 302,
      'manualStream': 302,
      'followed': '200:there',
      'refused': 'error',
      'events': ['1:tick 1', '2:tick 2', '3:tick 3'],
      'readTimeout': 'timeout',
      'steady': 'tick 3',
      'webSocket': {
        'platform': true,
        'echo': ['hello', '[1,2,3]'],
        'closeCode': 4000,
        'headers': 'rejected',
      },
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<bool> _hasNode() async {
  try {
    return (await Process.run('node', ['--version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
