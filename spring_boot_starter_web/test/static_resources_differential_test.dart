// Differential test of the static resources against Spring Boot itself
// (roadmap/security_verification.md): the reference application
// (tool/security_reference, built with `mvn -q -DskipTests package`) runs
// with the profile `static` and serves the same directory as a Dart
// application; both get the same raw requests. Statuses and the compared
// headers must match, or the difference is listed in [knownDifferences]
// with its reason. The attack catalog (static_resources_attack_test.dart)
// must be refused by both, and the Dart side must never be the one that
// serves when Spring refuses. Without the built jar the test is skipped (it
// fails instead with SECURITY_REFERENCE_REQUIRED set, as in CI).
//
//   (cd tool/security_reference && mvn -q -DskipTests package)
//   dart test spring_boot_starter_web/test/static_resources_differential_test.dart
@Tags(['differential'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

import 'static_resources_attack_test.dart' show attackCatalog;
import 'support.dart';

/// [path] in this package (the tests also run from the workspace root).
File _packageFile(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_web/'),
  )!.resolve('../$path'),
);

final File _jar = _packageFile(
  '../tool/security_reference/target/security-reference-0.0.0.jar',
);

const _secret = 'TOP-SECRET-CONTENT';

/// The site both serve, and a secret next to it.
const _files = <String, String>{
  'site/index.html': '<h1>home</h1>',
  'site/app.js': 'console.log(1);',
  'site/app.js.gz': 'GZIP',
  'site/style.css': 'body{}',
  'site/logo.svg': '<svg/>',
  'site/data.json': '{}',
  'site/sub/page.html': '<p>page</p>',
  'site/.env': _secret,
  'site/.well-known/assetlinks.json': '[]',
  'site/.well-known/apple-app-site-association': '{}',
  'secret.txt': _secret,
};

/// One answer, reduced to what is compared.
final class Answer {
  Answer(this.status, this.headers, this.body);

  final int status;
  final Map<String, String> headers;
  final String body;

  /// The compared fields. Of an error, the status and the headers that
  /// say how to go on (`Allow`, `Content-Range`): the bodies are each
  /// side's error format (Spring Boot's `/error` JSON, a `ProblemDetail`
  /// here).
  Map<String, String> compared() => {
    'status': '$status',
    for (final name in status < 400 ? _comparedHeaders : _errorHeaders)
      if (headers[name] case final value?) name: _normalize(name, value),
    if (status == 200 || status == 206) 'body': body,
  };

  static const _errorHeaders = ['allow', 'content-range'];

  static const _comparedHeaders = [
    'content-type',
    'content-length',
    'content-range',
    'accept-ranges',
    'cache-control',
    'allow',
    'content-encoding',
  ];

  // The media type without parameters (Tomcat may add a charset).
  static String _normalize(String name, String value) => name == 'content-type'
      ? value.split(';').first.trim().toLowerCase()
      : value;
}

/// A raw HTTP/1.1 exchange with [port]: [target] is written as it is.
Future<Answer> send(
  int port,
  String method,
  String target, {
  Map<String, String> headers = const {},
}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final head = StringBuffer('$method $target HTTP/1.1\r\n')
    ..write('Host: localhost:$port\r\n')
    ..write('Connection: close\r\n');
  headers.forEach((name, value) => head.write('$name: $value\r\n'));
  head.write('\r\n');
  socket.add(utf8.encode('$head'));
  await socket.flush();
  final bytes = await socket
      .fold<List<int>>([], (all, chunk) => all..addAll(chunk))
      .timeout(const Duration(seconds: 10));
  socket.destroy();
  final text = latin1.decode(bytes);
  final end = text.indexOf('\r\n\r\n');
  final lines = (end < 0 ? text : text.substring(0, end)).split('\r\n');
  final status = int.parse(lines.first.split(' ')[1]);
  final parsed = <String, String>{};
  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    if (colon > 0) {
      final name = line.substring(0, colon).trim().toLowerCase();
      final value = line.substring(colon + 1).trim();
      parsed[name] = parsed.containsKey(name)
          ? '${parsed[name]}, $value'
          : value;
    }
  }
  var body = end < 0 ? '' : text.substring(end + 4);
  if ((parsed['transfer-encoding'] ?? '').contains('chunked')) {
    body = _unchunk(body);
  }
  return Answer(status, parsed, body);
}

String _unchunk(String body) {
  final out = StringBuffer();
  var rest = body;
  while (true) {
    final line = rest.indexOf('\r\n');
    if (line < 0) {
      return out.toString();
    }
    final size = int.tryParse(rest.substring(0, line).trim(), radix: 16) ?? 0;
    if (size == 0) {
      return out.toString();
    }
    out.write(rest.substring(line + 2, line + 2 + size));
    rest = rest.substring(line + 2 + size + 2);
  }
}

/// The requests whose answers are compared: (name, method, target,
/// headers).
const _requests = <(String, String, String, Map<String, String>)>[
  ('a file', 'GET', '/app.js', {}),
  ('a stylesheet', 'GET', '/style.css', {}),
  ('an image', 'GET', '/logo.svg', {}),
  ('JSON', 'GET', '/data.json', {}),
  ('a page below /', 'GET', '/sub/page.html', {}),
  ('HEAD', 'HEAD', '/app.js', {}),
  ('a range', 'GET', '/app.js', {'Range': 'bytes=0-6'}),
  ('a suffix range', 'GET', '/app.js', {'Range': 'bytes=-3'}),
  ('a range past the end', 'GET', '/app.js', {'Range': 'bytes=500-'}),
  ('a missing file', 'GET', '/missing.js', {}),
  ('a directory', 'GET', '/sub/', {}),
  ('a directory without slash', 'GET', '/sub', {}),
  ('the welcome page', 'GET', '/', {'Accept': 'text/html'}),
  ('the welcome page for JSON', 'GET', '/', {'Accept': 'application/json'}),
  ('POST to a file', 'POST', '/app.js', {'Content-Length': '0'}),
  ('POST to a missing file', 'POST', '/missing.js', {'Content-Length': '0'}),
  ('DELETE to a file', 'DELETE', '/app.js', {}),
  ('OPTIONS of a file', 'OPTIONS', '/app.js', {}),
  ('a matrix parameter', 'GET', '/app.js;v=1', {}),
  ('a double slash', 'GET', '//sub//page.html', {}),
  ('a precompressed file asked for', 'GET', '/app.js.gz', {}),
  ('deep links', 'GET', '/.well-known/assetlinks.json', {}),
  ('a hidden file', 'GET', '/.env', {}),
  ('iOS deep links', 'GET', '/.well-known/apple-app-site-association', {}),
];

/// Differences on purpose, by request name, with the reason (the docs
/// list them as well).
const knownDifferences = <String, String>{
  // Spring serves dot files; this starter hides them (except
  // .well-known/), so a stray .env or .git in a location is not served.
  'a hidden file': 'dot files are not served',
  // Spring answers application/octet-stream (no extension); deep links of
  // iOS want JSON.
  'iOS deep links': 'apple-app-site-association is application/json',
  // The reference application has a controller at / (its home page), so
  // its welcome page cannot be compared; the MockMvc tests cover it.
  'the welcome page': 'the reference maps / to a controller',
  'the welcome page for JSON': 'the reference maps / to a controller',
  // Both refuse: Spring Security's firewall with a 400, the static
  // resources here with a 404 (no file of that name is looked for).
  'a matrix parameter': 'refused by both (400 there, 404 here)',
  'a double slash': 'refused by both (400 there, 404 here)',
  // Tomcat's mime mapping says application/x-gzip; RFC 6713 registers
  // application/gzip.
  'a precompressed file asked for': 'application/gzip, the IANA type',
};

void main() {
  Process? spring;
  late int springPort;
  late Directory root;

  setUpAll(() async {
    root = Directory.systemTemp.createTempSync('static_differential_');
    for (final MapEntry(:key, :value) in _files.entries) {
      File('${root.path}/$key')
        ..createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    if (!_jar.existsSync()) {
      // CI's differential job builds it: there a missing jar is a failure.
      if (Platform.environment.containsKey('SECURITY_REFERENCE_REQUIRED')) {
        throw StateError('${_jar.path} is missing');
      }
      return;
    }
    final probe = await ServerSocket.bind('127.0.0.1', 0);
    springPort = probe.port;
    await probe.close();
    spring = await Process.start('java', [
      '-jar',
      _jar.path,
      '--spring.profiles.active=static',
      '--server.port=$springPort',
      '--server.address=127.0.0.1',
      '--spring.web.resources.static-locations=file:${root.path}/site/',
    ]);
    unawaited(spring!.stderr.drain<void>());
    unawaited(spring!.stdout.drain<void>());
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await send(springPort, 'GET', '/app.js');
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    spring!.kill();
    throw StateError('The Spring reference (profile static) did not start');
  });

  tearDownAll(() {
    spring?.kill();
    root.deleteSync(recursive: true);
  });

  Future<void> withDart(Future<void> Function(int port) body) =>
      webRunner([
        'spring.web.resources.static-locations=file:${root.path}/site/',
      ]).runAsync((context) async {
        expect(context.startupFailure, isNull);
        final client = await Client.of(context.context);
        client.close();
        await body(client.port);
      });

  test("the answers match Spring Boot's ResourceHttpRequestHandler", () async {
    if (spring == null) {
      markTestSkipped('Build tool/security_reference first (mvn package)');
      return;
    }
    await withDart((dartPort) async {
      final mismatches = <String>[];
      for (final (name, method, target, headers) in _requests) {
        final expected = await send(
          springPort,
          method,
          target,
          headers: headers,
        );
        final actual = await send(dartPort, method, target, headers: headers);
        final s = expected.compared();
        final d = actual.compared();
        if ('$s' != '$d' && !knownDifferences.containsKey(name)) {
          mismatches.add('$name ($method $target):\n  Spring $s\n  Dart   $d');
        }
      }
      expect(mismatches, isEmpty, reason: mismatches.join('\n'));
    });
  });

  test('the attack catalog: both refuse, Dart never serves more', () async {
    if (spring == null) {
      markTestSkipped('Build tool/security_reference first (mvn package)');
      return;
    }
    await withDart((dartPort) async {
      final problems = <String>[];
      for (final MapEntry(key: category, value: payloads)
          in attackCatalog.entries) {
        for (final payload in payloads) {
          if (payload.runes.any((r) => r <= 0x20 || r == 0x7F)) {
            continue;
          }
          final target = '/$payload';
          final expected = await send(springPort, 'GET', target);
          final actual = await send(dartPort, 'GET', target);
          final label = '$category: ${Uri.encodeFull(payload)}';
          if (expected.body.contains(_secret)) {
            // A finding about Spring itself: reported, not ours to fix.
            problems.add('Spring served the secret for $label');
          }
          if (actual.body.contains(_secret)) {
            problems.add('Dart served the secret for $label');
          }
          // dart:io resolves dot segments (raw, and `%2e` as an
          // unreserved character) before the server sees the target (the
          // server's documentation says so): `/sub/./page.html` arrives as
          // `/sub/page.html` and `/..` as `/` (the welcome page). That is
          // a file of the site, never one outside it.
          final normalizedInside =
              actual.status == 200 &&
              _files.entries.any(
                (f) =>
                    f.key.startsWith('site/') &&
                    f.value != _secret &&
                    f.value == actual.body,
              );
          if (actual.status < 400 &&
              expected.status >= 400 &&
              !normalizedInside) {
            problems.add(
              'Dart answered ${actual.status} where Spring refused with '
              '${expected.status}: $label',
            );
          }
        }
      }
      expect(
        problems.where((p) => p.startsWith('Dart')),
        isEmpty,
        reason: problems.join('\n'),
      );
    });
  });
}
