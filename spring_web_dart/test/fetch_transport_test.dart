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
    // Another origin, which answers with the headers it was given.
    final otherOrigin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => otherOrigin.close(force: true));
    otherOrigin.listen(_answerSeen);
    // A server for the streaming and WebSocket checks.
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      if (request.uri.path == '/seen') {
        await _answerSeen(request);
        return;
      }
      if (request.uri.path == '/hop') {
        await request.drain<void>();
        request.response
          ..statusCode = int.parse(request.uri.queryParameters['code'] ?? '302')
          ..headers.set('Location', request.uri.queryParameters['to']!);
        await request.response.close();
        return;
      }
      if (request.uri.path == '/upload') {
        var size = 0;
        await for (final chunk in request) {
          size += chunk.length;
        }
        final chunked = request.headers.chunkedTransferEncoding;
        request.response
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..write('$size ${chunked ? 'chunked' : 'length'}');
        await request.response.close();
        return;
      }
      if (request.uri.path == '/loop') {
        request.response
          ..statusCode = HttpStatus.found
          ..headers.set('Location', '/loop');
        await request.response.close();
        return;
      }
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
          'globalThis.testOtherOrigin = "localhost:${otherOrigin.port}"; '
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
      'redirectSameOrigin': 'GET Bearer a|b|c|d=e|plain',
      'redirectOtherOrigin': 'GET -|-|-|-|plain',
      'redirectStream': 'GET -|-|-|-|plain',
      // A POST is not repeated at the target of a 307.
      'redirectPost307': 307,
      'redirectPost303': 'GET -|-|-|-|plain',
      // After the most redirects, the last 3xx is the answer.
      'redirectLoop': 302,
      'allowedRedirect': 'there',
      'deniedRedirect': 'denied localhost',
      'deniedDirect': 'denied 169.254.169.254',
      'restClient': 'there',
      'refused': 'error',
      'events': ['1:tick 1', '2:tick 2', '3:tick 3'],
      'readTimeout': 'timeout',
      'steady': 'tick 3',
      'streamed303': '0 length',
      // Node's fetch streams a body without Content-Length.
      'streamed': [
        '100000 chunked',
        '100000 chunked',
        'not repeatable',
        '100000 chunked',
      ],
      'webSocket': {
        'platform': true,
        'echo': ['hello', '[1,2,3]'],
        'closeCode': 4000,
        'headers': 'rejected',
      },
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('in a browser, a redirect never carries a custom credential', () async {
    if (!await _hasNode()) {
      markTestSkipped('node is not on the PATH');
      return;
    }
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:spring_web_dart/'),
    );
    final package = Directory.fromUri(lib!).parent.path;
    final temp = Directory.systemTemp.createTempSync('spring_web_fetch_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final output = '${temp.path}/fetch_browser_main.js';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-o',
      output,
      'test/js/fetch_browser_main.dart',
    ], workingDirectory: package);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    // What a browser does: `Request` drops the forbidden Cookie, and
    // `redirect: 'manual'` gives an opaque response without the Location.
    final run = await Process.run('node', [
      '-e',
      '$_browserStandIn require(${jsonEncode(output)})',
    ]);
    expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
    final line = (run.stdout as String)
        .split('\n')
        .firstWhere((l) => l.startsWith('RESULT '));
    expect(jsonDecode(line.substring(7)), {
      'noCredentials': 'followed',
      'authorization': 'followed',
      'cookieAndAuthorization': 'followed',
      'apiKey': 'refused: X-Api-Key',
      'declared': 'refused: X-Grant',
      'notFollowing': 0,
      'modes': ['follow', 'follow', 'follow', 'manual', 'manual', 'manual'],
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('a streamed body: a stream where fetch takes one, else read whole '
      'first', () async {
    if (!await _hasNode()) {
      markTestSkipped('node is not on the PATH');
      return;
    }
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:spring_web_dart/'),
    );
    final package = Directory.fromUri(lib!).parent.path;
    final temp = Directory.systemTemp.createTempSync('spring_web_fetch_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final output = '${temp.path}/fetch_stream_main.js';
    final compiled = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'js',
      '-o',
      output,
      'test/js/fetch_stream_main.dart',
    ], workingDirectory: package);
    expect(
      compiled.exitCode,
      0,
      reason: '${compiled.stdout}${compiled.stderr}',
    );
    Future<Object?> run(String standIn) async {
      final run = await Process.run('node', [
        '-e',
        '$standIn require(${jsonEncode(output)})',
      ]);
      expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
      final line = (run.stdout as String)
          .split('\n')
          .firstWhere((l) => l.startsWith('RESULT '));
      return jsonDecode(line.substring(7));
    }

    // A fetch that takes streams (detected through Request), and refuses
    // one from h1.example before reading it, as Chromium over HTTP/1.1.
    expect(await run(_streamFetchStandIn), {
      'refused': 'ok',
      'refusedAgain': 'ok',
      'streams': 'ok',
      'broken': 'error',
      'brokenAgain': 'not repeatable',
      'calls': [
        'h1.example refused',
        'h1.example bytes 4000',
        // The origin's bodies are read whole from then on.
        'h1.example bytes 4000',
        'h2.example stream half 4000',
        'broken.example broke after 1000',
      ],
    });
    // A browser whose Request turns a stream into text: read whole first.
    expect(await run('$_noRequestStreams $_streamFetchStandIn'), {
      'refused': 'ok',
      'refusedAgain': 'ok',
      'streams': 'ok',
      'broken': 'ok',
      'brokenAgain': 'not repeatable',
      'calls': [
        'h1.example bytes 4000',
        'h1.example bytes 4000',
        'h2.example bytes 4000',
        'broken.example bytes 4000',
      ],
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

const _streamFetchStandIn = '''
globalThis.self = globalThis;
globalThis.calls = [];
globalThis.fetch = async (url, init) => {
  const host = new URL(url).host;
  const body = init.body;
  if (body instanceof ReadableStream) {
    if (host === "h1.example") {
      calls.push(host + " refused");
      throw new TypeError("Failed to fetch");
    }
    const reader = body.getReader();
    let size = 0;
    if (host === "broken.example") {
      size += (await reader.read()).value.length;
      calls.push(host + " broke after " + size);
      throw new TypeError("network error");
    }
    for (;;) {
      const chunk = await reader.read();
      if (chunk.done) break;
      size += chunk.value.length;
    }
    calls.push(host + " stream " + init.duplex + " " + size);
  } else {
    calls.push(host + " bytes " + (body ? body.length : 0));
  }
  return new Response("ok");
};
''';

const _noRequestStreams = '''
const RealRequest = Request;
globalThis.Request = class extends RealRequest {
  constructor(url, init) {
    const copy = {};
    for (const key of ["method", "headers", "body", "signal", "redirect"]) {
      if (init && key in init) {
        copy[key] = key === "body" && init.body instanceof ReadableStream
          ? String(init.body)
          : init[key];
      }
    }
    super(url, copy);
  }
};
''';

const _browserStandIn = '''
globalThis.self = globalThis;
globalThis.modes = [];
const Real = Request;
globalThis.Request = class extends Real {
  constructor(url, init) {
    super(url, init);
    this.headers.delete("cookie");
  }
};
globalThis.fetch = async (url, init) => {
  modes.push(init.redirect);
  if (init.redirect !== "manual") return new Response("followed");
  const response = new Response(null);
  Object.defineProperty(response, "type", { value: "opaqueredirect" });
  Object.defineProperty(response, "status", { value: 0 });
  return response;
};
''';

Future<void> _answerSeen(HttpRequest request) async {
  await request.drain<void>();
  String seen(String name) => request.headers.value(name) ?? '-';
  request.response.write(
    '${request.method} ${seen('authorization')}|${seen('x-api-key')}|'
    '${seen('x-grant')}|${seen('cookie')}|${seen('x-plain')}',
  );
  await request.response.close();
}

Future<bool> _hasNode() async {
  try {
    return (await Process.run('node', ['--version'])).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
