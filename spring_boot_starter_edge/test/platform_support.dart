import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_edge/build.dart';

/// The directory of this package, wherever the tests are run from.
final String packageRoot = Directory.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_edge/build.dart'),
  )!.resolve('..'),
).path.replaceFirst(RegExp(r'/$'), '');

/// Whether `node` is on the PATH.
bool get hasNode {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

/// Builds the function of the tests (tool/edge_checks of the repository) for [platform]
/// into [output], or a new temporary directory.
Future<Directory> buildFunction(
  EdgePlatform platform, {
  String name = 'edge-test',
  String? output,
  bool streaming = false,
  EdgeTarget target = EdgeTarget.js,
}) async {
  final directory =
      output ?? Directory.systemTemp.createTempSync('spring_edge_').path;
  final result = await EdgeBuild(
    platform: platform,
    name: name,
    application: Directory('$packageRoot/../tool/edge_checks'),
    output: directory,
    streaming: streaming,
    target: target,
  ).run();
  return result.directory;
}

/// A free port of this machine.
Future<int> freePort() async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  await server.close();
  return port;
}

/// A response of a function.
final class Answer {
  Answer(this.status, this.headers, this.bytes);

  final int status;

  /// Lower-case names; a value for every header line.
  final Map<String, List<String>> headers;
  final List<int> bytes;

  String get text => utf8.decode(bytes);

  Object? get json => jsonDecode(text);

  String? header(String name) => headers[name.toLowerCase()]?.join(', ');
}

/// Requests to a function, however its platform takes them.
abstract class FunctionClient {
  Future<Answer> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  });

  /// The status of a request whose target is sent exactly as [target]
  /// (an HTTP client would tidy it first).
  Future<int> rawStatus(String target);

  Future<Answer> get(String path, {Map<String, String> headers = const {}}) =>
      send('GET', path, headers: headers);

  /// Waits until the function answers [path].
  Future<void> ready(
    String path, {
    Duration timeout = const Duration(minutes: 4),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        final answer = await get(path).timeout(const Duration(seconds: 15));
        if (answer.status == 200) {
          return;
        }
      } on Object {
        // Not listening yet.
      }
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('No answer for $path', timeout);
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  void close() {}
}

/// A function that listens at [base] (Supabase's gateway, `wrangler dev`).
final class HttpFunctionClient extends FunctionClient {
  HttpFunctionClient(this.base);

  final Uri base;

  final _client = HttpClient();

  @override
  Future<Answer> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = await _client.openUrl(method, Uri.parse('$base$path'));
    request.followRedirects = false;
    headers.forEach(request.headers.set);
    if (body != null) {
      request.add(body);
    }
    final response = await request.close();
    final bytes = await response.fold(
      <int>[],
      (all, chunk) => all..addAll(chunk),
    );
    final all = <String, List<String>>{};
    response.headers.forEach((name, values) => all[name] = values);
    return Answer(response.statusCode, all, bytes);
  }

  @override
  Future<int> rawStatus(String target) async {
    final socket = await Socket.connect(base.host, base.port);
    try {
      socket.write(
        'GET ${base.path}$target HTTP/1.1\r\n'
        'Host: ${base.host}:${base.port}\r\n'
        'Connection: close\r\n\r\n',
      );
      await socket.flush();
      final text = await utf8.decoder
          .bind(socket)
          .join()
          .timeout(const Duration(seconds: 30));
      final match = RegExp(r'^HTTP/1\.[01] (\d{3})').firstMatch(text);
      return match == null ? -1 : int.parse(match.group(1)!);
    } finally {
      socket.destroy();
    }
  }

  @override
  void close() => _client.close(force: true);
}

/// A function URL event (payload 2.0) for [method] and [target].
Map<String, Object?> lambdaEvent(
  String method,
  String target, {
  Map<String, String> headers = const {},
  List<int>? body,
  String sourceIp = '203.0.113.9',
}) {
  final query = target.indexOf('?');
  return {
    'version': '2.0',
    'rawPath': query < 0 ? target : target.substring(0, query),
    'rawQueryString': query < 0 ? '' : target.substring(query + 1),
    'headers': {
      'host': 'fn.example.com',
      for (final MapEntry(:key, :value) in headers.entries)
        key.toLowerCase(): value,
    },
    'requestContext': {
      'domainName': 'fn.example.com',
      'http': {'method': method, 'sourceIp': sourceIp},
    },
    if (body != null) 'body': base64.encode(body),
    'isBase64Encoded': body != null,
  };
}

/// The result of a Lambda handler as an [Answer].
Answer lambdaAnswer(Map<String, Object?> result) {
  final body = result['body'] as String? ?? '';
  return Answer(
    result['statusCode']! as int,
    {
      for (final MapEntry(:key, :value)
          in (result['headers'] as Map? ?? const {}).entries)
        '$key'.toLowerCase(): ['$value'],
      if (result['cookies'] case final List<Object?> cookies
          when cookies.isNotEmpty)
        'set-cookie': [for (final cookie in cookies) '$cookie'],
    },
    result['isBase64Encoded'] == true ? base64.decode(body) : utf8.encode(body),
  );
}

/// A function in the Lambda runtime: every request is an invocation with
/// a function URL event, posted to the runtime's [invocations] address.
final class LambdaFunctionClient extends FunctionClient {
  LambdaFunctionClient(this.invocations);

  /// Where events are posted.
  final Uri invocations;

  final _client = HttpClient();

  /// The handler's result for [event], as it returned it.
  Future<Map<String, Object?>> invoke(Map<String, Object?> event) async {
    final request = await _client.postUrl(invocations);
    request.add(utf8.encode(jsonEncode(event)));
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    final result = jsonDecode(text);
    if (result is! Map<String, Object?> || result['statusCode'] is! int) {
      throw StateError('The invocation failed: $text');
    }
    return result;
  }

  Future<Answer> _invoke(Map<String, Object?> event) async =>
      lambdaAnswer(await invoke(event));

  @override
  Future<Answer> send(
    String method,
    String path, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) => _invoke(lambdaEvent(method, path, headers: headers, body: body));

  @override
  Future<int> rawStatus(String target) async =>
      (await _invoke(lambdaEvent('GET', target))).status;

  @override
  void close() => _client.close(force: true);
}

/// A process that prints a line it is asked to wait for when it is up; its
/// output is kept for a failure's message.
final class Background {
  Background._(this.process, this.output);

  final Process process;
  final StringBuffer output;

  /// Starts [executable] and waits for a line that matches [ready]; gives
  /// the match.
  static Future<(Background, Match)> start(
    String executable,
    List<String> arguments, {
    required RegExp ready,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration timeout = const Duration(minutes: 5),
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );
    final output = StringBuffer();
    final found = Completer<Match>();
    void read(Stream<List<int>> stream) {
      stream.transform(utf8.decoder).transform(const LineSplitter()).listen((
        line,
      ) {
        output.writeln(line);
        final match = ready.firstMatch(line);
        if (match != null && !found.isCompleted) {
          found.complete(match);
        }
      });
    }

    read(process.stdout);
    read(process.stderr);
    unawaited(
      process.exitCode.then((code) {
        if (!found.isCompleted) {
          found.completeError(
            StateError('$executable ended with $code:\n$output'),
          );
        }
      }),
    );
    try {
      final match = await found.future.timeout(timeout);
      return (Background._(process, output), match);
    } on Object {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }

  Future<void> stop() async {
    process.kill();
    await process.exitCode.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}
