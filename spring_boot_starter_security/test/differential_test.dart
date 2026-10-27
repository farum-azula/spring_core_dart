// Differential tests against Spring Security itself
// (roadmap/security_verification.md, section 3): the Spring Boot twin of the
// rules application (tool/security_reference, built with
// `mvn -q -DskipTests package`) and the Dart one get the same raw requests;
// statuses, challenges, redirects, security and CORS headers and cookie
// flags must match, or the difference is listed in [knownDifferences] with
// its reason. Without the built jar the test is skipped (it fails instead
// with SECURITY_REFERENCE_REQUIRED set, as in CI).
//
//   (cd tool/security_reference && mvn -q -DskipTests package)
//   dart test spring_boot_starter_security/test/differential_test.dart
@Tags(['differential'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:test/test.dart';

import 'app/rules/rules.dart';
import 'support.dart';

/// [path] in this package (the tests also run from the workspace root).
File _packageFile(String path) => File.fromUri(
  Isolate.resolvePackageUriSync(
    Uri.parse('package:spring_boot_starter_security/'),
  )!.resolve('../$path'),
);

final File _jar = _packageFile(
  '../tool/security_reference/target/security-reference-0.0.0.jar',
);

/// One answer, reduced to what is compared.
final class Answer {
  Answer(this.status, this.headers, this.body);

  final int status;
  final Map<String, List<String>> headers;
  final String body;

  String? header(String name) => headers[name]?.join(', ');

  /// The compared fields (absent ones omitted).
  Map<String, String> compared() => {
    'status': '$status',
    for (final name in _comparedHeaders)
      if (header(name) case final value?) name: _normalize(name, value),
    if (_cookies().isNotEmpty) 'set-cookie': _cookies(),
  };

  static const _comparedHeaders = [
    'www-authenticate',
    'location',
    'x-frame-options',
    'x-content-type-options',
    'x-xss-protection',
    'cache-control',
    'pragma',
    'expires',
    'strict-transport-security',
    'access-control-allow-origin',
    'access-control-allow-credentials',
  ];

  // Cookie names and flags, never values.
  String _cookies() {
    final cookies = [
      for (final cookie in headers['set-cookie'] ?? const <String>[])
        () {
          final parts = cookie.split(';').map((p) => p.trim()).toList();
          final name = parts.first.split('=').first;
          final flags = [
            for (final p in parts.skip(1)) p.split('=').first.toLowerCase(),
          ]..sort();
          final sameSite = parts
              .where((p) => p.toLowerCase().startsWith('samesite='))
              .map((p) => p.toLowerCase())
              .join();
          return '$name[${flags.join(',')}'
              "${sameSite.isEmpty ? '' : ' $sameSite'}]";
        }(),
    ]..sort();
    return cookies.join(' ');
  }

  // Locations without the origin (Spring writes absolute URLs).
  static String _normalize(String name, String value) => name == 'location'
      ? value.replaceFirst(RegExp('^https?://[^/]+'), '')
      : value;
}

/// A raw HTTP/1.1 exchange with [port].
Future<Answer> send(
  int port,
  String method,
  String target, {
  List<(String, String)> headers = const [],
  String? body,
}) async {
  final socket = await Socket.connect('127.0.0.1', port);
  final bodyBytes = body == null ? const <int>[] : utf8.encode(body);
  final head = StringBuffer('$method $target HTTP/1.1\r\n')
    ..write('Host: localhost:$port\r\n')
    ..write('Connection: close\r\n');
  for (final (name, value) in headers) {
    head.write('$name: $value\r\n');
  }
  if (body != null) {
    head.write('Content-Length: ${bodyBytes.length}\r\n');
  }
  head.write('\r\n');
  socket
    ..add(latin1.encode('$head'))
    ..add(bodyBytes);
  await socket.flush();
  final bytes = await socket
      .fold<List<int>>([], (all, chunk) => all..addAll(chunk))
      .timeout(const Duration(seconds: 10));
  socket.destroy();
  final text = utf8.decode(bytes, allowMalformed: true);
  final split = text.indexOf('\r\n\r\n');
  final lines = text
      .substring(0, split < 0 ? text.length : split)
      .split('\r\n');
  final status = int.parse(lines.first.split(' ')[1]);
  final values = <String, List<String>>{};
  for (final line in lines.skip(1)) {
    final colon = line.indexOf(':');
    if (colon > 0) {
      (values[line.substring(0, colon).toLowerCase()] ??= []).add(
        line.substring(colon + 1).trim(),
      );
    }
  }
  var payload = split < 0 ? '' : text.substring(split + 4);
  if (values['transfer-encoding']?.contains('chunked') ?? false) {
    payload = _dechunk(payload);
  }
  return Answer(status, values, payload);
}

String _dechunk(String body) {
  final out = StringBuffer();
  var rest = body;
  while (rest.isNotEmpty) {
    final end = rest.indexOf('\r\n');
    if (end < 0) {
      break;
    }
    final size =
        int.tryParse(rest.substring(0, end).split(';').first, radix: 16) ?? 0;
    if (size == 0) {
      break;
    }
    out.write(rest.substring(end + 2, end + 2 + size));
    rest = rest.substring(end + 2 + size + 2);
  }
  return '$out';
}

String _basic(String user, String password) =>
    'Basic ${base64.encode(utf8.encode('$user:$password'))}';

/// A request of the catalog.
final class Probe {
  const Probe(
    this.name,
    this.method,
    this.target, {
    this.headers = const [],
    this.body,
  });

  final String name;
  final String method;
  final String target;
  final List<(String, String)> headers;
  final String? body;
}

final (String, String) _ada = ('Authorization', _basic('ada', 'ada-pw'));
final (String, String) _root = ('Authorization', _basic('root', 'root-pw'));

/// The requests sent to both applications.
final catalog = <Probe>[
  // Anonymous access.
  const Probe('public', 'GET', '/public/hello'),
  const Probe('root path', 'GET', '/'),
  const Probe('protected */*', 'GET', '/api/me', headers: [('Accept', '*/*')]),
  const Probe('protected no Accept', 'GET', '/api/me'),
  const Probe(
    'protected json',
    'GET',
    '/api/me',
    headers: [('Accept', 'application/json')],
  ),
  const Probe(
    'protected html',
    'GET',
    '/api/me',
    headers: [('Accept', 'text/html')],
  ),
  const Probe(
    'protected browser',
    'GET',
    '/api/me',
    headers: [
      (
        'Accept',
        'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      ),
    ],
  ),
  const Probe(
    'protected xhr',
    'GET',
    '/api/me',
    headers: [('Accept', 'text/html'), ('X-Requested-With', 'XMLHttpRequest')],
  ),
  const Probe('admin anonymous', 'GET', '/api/admin'),
  const Probe('unknown path anonymous', 'GET', '/api/nothing-here'),
  const Probe(
    'login page',
    'GET',
    '/login',
    headers: [('Accept', 'text/html')],
  ),
  const Probe(
    'logout page',
    'GET',
    '/logout',
    headers: [('Accept', 'text/html')],
  ),
  const Probe('form page', 'GET', '/form'),
  // Logged in with Basic.
  Probe('me as ada', 'GET', '/api/principal', headers: [_ada]),
  Probe('user as ada', 'GET', '/api/user', headers: [_ada]),
  Probe('context as ada', 'GET', '/api/context', headers: [_ada]),
  Probe('admin as ada', 'GET', '/api/admin', headers: [_ada]),
  Probe('admin as root', 'GET', '/api/admin', headers: [_root]),
  Probe('own user', 'GET', '/api/users/ada', headers: [_ada]),
  Probe('other user', 'GET', '/api/users/root', headers: [_ada]),
  Probe('other user as admin', 'GET', '/api/users/ada', headers: [_root]),
  Probe('method security denied', 'GET', '/api/reports/q1', headers: [_ada]),
  Probe('method security granted', 'GET', '/api/reports/q1', headers: [_root]),
  Probe('own cache-control', 'GET', '/api/cached', headers: [_ada]),
  Probe(
    'post without csrf',
    'POST',
    '/api/data',
    headers: [_ada, ('Content-Type', 'text/plain')],
    body: 'x',
  ),
  Probe('unknown path logged in', 'GET', '/api/nothing-here', headers: [_ada]),
  // Bad credentials.
  Probe(
    'wrong password',
    'GET',
    '/api/me',
    headers: [('Authorization', _basic('ada', 'nope'))],
  ),
  Probe(
    'unknown user',
    'GET',
    '/api/me',
    headers: [('Authorization', _basic('nobody', 'x'))],
  ),
  const Probe(
    'empty basic',
    'GET',
    '/api/me',
    headers: [('Authorization', 'Basic')],
  ),
  const Probe(
    'garbage basic',
    'GET',
    '/api/me',
    headers: [('Authorization', 'Basic !!!')],
  ),
  Probe(
    'no colon',
    'GET',
    '/api/me',
    headers: [('Authorization', 'Basic ${base64.encode(utf8.encode('ada'))}')],
  ),
  const Probe(
    'other scheme',
    'GET',
    '/api/me',
    headers: [('Authorization', 'Digest username="ada"')],
  ),
  const Probe(
    'other scheme on public',
    'GET',
    '/public/hello',
    headers: [('Authorization', 'Digest x')],
  ),
  // Ambiguous paths.
  Probe('semicolon', 'GET', '/api/admin;x=1', headers: [_root]),
  Probe('encoded slash', 'GET', '/api%2Fadmin', headers: [_root]),
  Probe('double slash', 'GET', '/api//admin', headers: [_root]),
  Probe('leading double slash', 'GET', '//admin/api/admin', headers: [_root]),
  Probe('encoded null', 'GET', '/api/admin%00', headers: [_root]),
  Probe('encoded backslash', 'GET', '/api/%5Cadmin', headers: [_root]),
  Probe('encoded percent', 'GET', '/api/admin%25', headers: [_root]),
  Probe('dot dot', 'GET', '/public/../api/admin', headers: [_ada]),
  Probe('encoded dot dot', 'GET', '/public/%2e%2e/api/admin', headers: [_ada]),
  const Probe('trace', 'TRACE', '/public/hello'),
  // CORS.
  const Probe(
    'preflight trusted',
    'OPTIONS',
    '/api/me',
    headers: [
      ('Origin', 'https://trusted.example'),
      ('Access-Control-Request-Method', 'GET'),
    ],
  ),
  const Probe(
    'preflight evil',
    'OPTIONS',
    '/api/me',
    headers: [
      ('Origin', 'https://evil.example'),
      ('Access-Control-Request-Method', 'GET'),
    ],
  ),
  const Probe(
    'preflight @CrossOrigin',
    'OPTIONS',
    '/api/cors',
    headers: [
      ('Origin', 'https://app.example'),
      ('Access-Control-Request-Method', 'GET'),
    ],
  ),
  Probe(
    'cors actual',
    'GET',
    '/api/principal',
    headers: [('Origin', 'https://trusted.example'), _ada],
  ),
  const Probe(
    'cors actual anonymous',
    'GET',
    '/api/me',
    headers: [('Origin', 'https://trusted.example')],
  ),
  // Methods.
  const Probe('post public without csrf', 'POST', '/public/hello'),
  Probe('delete as root', 'DELETE', '/api/admin', headers: [_root]),
];

// Why a difference is on purpose (see the README's differences).
const _sameSite =
    'the session cookie is SameSite=Lax by default here; Spring Boot '
    '(Tomcat) sends none';
const _errorDispatch =
    'Spring Boot re-dispatches a 400 or 403 to /error through the security '
    'chain, where the request is anonymous (Basic is not run again): the '
    'client gets 401 and a session for /error. Here the rejection itself is '
    'answered (400 from the firewall, 403 from CSRF)';
const _rejected =
    "the firewall's 400 carries X-Frame-Options and X-Content-Type-Options "
    "here; Spring's (through /error) carries none";
const _normalized =
    'dart:io normalizes `..` and `%2e%2e` before the application (RFC 3986): '
    'the rules see /api/admin, as the router does, and deny ada (403). '
    "Spring's firewall refuses the raw path (400, then 401 through /error)";
const _crossOrigin =
    "with a CorsConfigurationSource bean, Spring's CorsFilter reads only that "
    "bean and refuses pre-flights allowed by @CrossOrigin; here the router's "
    'whole CORS configuration answers them';
const _failedBasicSession =
    'a failed Basic login creates no session here; Spring creates one '
    'through the /error dispatch';

/// Differences that are on purpose: `name/field` → why.
final knownDifferences = <String, String>{
  for (final probe in catalog) '${probe.name}/set-cookie': _sameSite,
  for (final name in [
    'post without csrf',
    'semicolon',
    'double slash',
    'leading double slash',
    'encoded percent',
    'trace',
    'post public without csrf',
    'delete as root',
  ]) ...{
    '$name/status': _errorDispatch,
    '$name/www-authenticate': _errorDispatch,
    '$name/set-cookie': _errorDispatch,
  },
  for (final name in [
    'semicolon',
    'encoded slash',
    'double slash',
    'leading double slash',
    'encoded null',
    'encoded backslash',
    'encoded percent',
    'trace',
  ]) ...{
    '$name/x-frame-options': _rejected,
    '$name/x-content-type-options': _rejected,
  },
  for (final name in ['dot dot', 'encoded dot dot']) ...{
    for (final field in [
      'status',
      'www-authenticate',
      'set-cookie',
      'x-frame-options',
      'x-content-type-options',
      'x-xss-protection',
      'cache-control',
      'pragma',
      'expires',
    ])
      '$name/$field': _normalized,
  },
  for (final field in [
    'status',
    'access-control-allow-origin',
    'access-control-allow-credentials',
  ])
    'preflight @CrossOrigin/$field': _crossOrigin,
  for (final name in [
    'wrong password',
    'unknown user',
    'empty basic',
    'garbage basic',
    'no colon',
  ])
    '$name/set-cookie': _failedBasicSession,
};

/// A browser on one server: cookies kept, the CSRF field read from pages.
final class _Session {
  _Session(this.port);

  final int port;
  final cookies = <String, String>{};

  Future<Answer> call(
    String method,
    String target, {
    Map<String, String>? form,
    String accept = 'text/html',
  }) async {
    final answer = await send(
      port,
      method,
      target,
      headers: [
        ('Accept', accept),
        if (cookies.isNotEmpty)
          (
            'Cookie',
            [for (final e in cookies.entries) '${e.key}=${e.value}'].join('; '),
          ),
        if (form != null) ('Content-Type', 'application/x-www-form-urlencoded'),
      ],
      body: form == null
          ? null
          : [
              for (final e in form.entries)
                [
                  Uri.encodeQueryComponent(e.key),
                  Uri.encodeQueryComponent(e.value),
                ].join('='),
            ].join('&'),
    );
    for (final cookie in answer.headers['set-cookie'] ?? const <String>[]) {
      final pair = cookie.split(';').first;
      final eq = pair.indexOf('=');
      final value = pair.substring(eq + 1);
      if (cookie.toLowerCase().contains('max-age=0') || value.isEmpty) {
        cookies.remove(pair.substring(0, eq));
      } else {
        cookies[pair.substring(0, eq)] = value;
      }
    }
    return answer;
  }

  static String csrf(String html) =>
      RegExp('name="_csrf" type="hidden" value="([^"]+)"')
          .firstMatch(html)![1]!;
}

/// The form login flow, step by step; each step's status and Location.
Future<List<String>> _loginFlow(int port) async {
  final browser = _Session(port);
  String step(String name, Answer a) =>
      '$name: ${a.status} ${a.compared()['location'] ?? ''}'.trim();
  final steps = <String>[
    step('protected page', await browser('GET', '/api/me')),
  ];
  final page = await browser('GET', '/login');
  steps.add(step('login page', page));
  final token = _Session.csrf(page.body);
  steps
    ..add(
      step(
        'no token',
        await browser(
          'POST',
          '/login',
          form: {'username': 'ada', 'password': 'ada-pw'},
        ),
      ),
    )
    ..add(
      step(
        'wrong password',
        await browser(
          'POST',
          '/login',
          form: {'username': 'ada', 'password': 'x', '_csrf': token},
        ),
      ),
    );
  final before = browser.cookies['JSESSIONID'];
  steps
    ..add(
      step(
        'login',
        await browser(
          'POST',
          '/login',
          form: {'username': 'ada', 'password': 'ada-pw', '_csrf': token},
        ),
      ),
    )
    ..add('session id changed: ${browser.cookies['JSESSIONID'] != before}')
    ..add(
      step(
        'saved page',
        await browser('GET', '/api/me?continue', accept: 'application/json'),
      ),
    );
  final form = await browser('GET', '/form', accept: '*/*');
  final formToken = form.body.substring(form.body.indexOf('=') + 1);
  steps
    ..add(
      step(
        'form post',
        await browser(
          'POST',
          '/form',
          form: {'text': 'hi', '_csrf': formToken},
        ),
      ),
    )
    ..add(
      step(
        'form post, old token',
        await browser('POST', '/form', form: {'text': 'hi', '_csrf': token}),
      ),
    );
  final confirm = await browser('GET', '/logout');
  steps.add(step('logout page', confirm));
  final session = browser.cookies['JSESSIONID'];
  steps.add(
    step(
      'logout',
      await browser(
        'POST',
        '/logout',
        form: {'_csrf': _Session.csrf(confirm.body)},
      ),
    ),
  );
  final stale = await send(
    port,
    'GET',
    '/api/me',
    headers: [
      ('Cookie', 'JSESSIONID=$session'),
      ('Accept', 'application/json'),
    ],
  );
  steps.add(step('old session after logout', stale));
  return steps;
}

void main() {
  Process? spring;
  late int springPort;

  setUpAll(() async {
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
      '--server.port=$springPort',
      '--server.address=127.0.0.1',
    ]);
    unawaited(spring!.stderr.drain<void>());
    unawaited(spring!.stdout.drain<void>());
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    while (DateTime.now().isBefore(deadline)) {
      try {
        await send(springPort, 'GET', '/public/hello');
        return;
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    throw StateError('The Spring reference did not start');
  });

  tearDownAll(() => spring?.kill());

  Future<void> withDart(Future<void> Function(int port) body) =>
      securityRunner(rulesSecurityBeans, [
        'spring.test.web-environment=random-port',
        'server.address=127.0.0.1',
      ]).runAsync((started) async {
        final server = (await started.context
            .getBean<WebServerStartStopLifecycle>()
            .started)!;
        await body(server.port);
      });

  test('the catalog answers like Spring Security', () async {
    if (spring == null) {
      markTestSkipped('Build tool/security_reference first (mvn package)');
      return;
    }
    await withDart((dartPort) async {
      final report = StringBuffer();
      var unexpected = 0;
      for (final probe in catalog) {
        final fromSpring = await send(
          springPort,
          probe.method,
          probe.target,
          headers: probe.headers,
          body: probe.body,
        );
        final fromDart = await send(
          dartPort,
          probe.method,
          probe.target,
          headers: probe.headers,
          body: probe.body,
        );
        final s = fromSpring.compared();
        final d = fromDart.compared();
        for (final field in {...s.keys, ...d.keys}) {
          if (s[field] == d[field]) {
            continue;
          }
          final key = '${probe.name}/$field';
          final known = knownDifferences[key];
          report.writeln(
            '${known == null ? 'DIFF ' : 'known'} $key\n'
            '      Spring: ${s[field]}\n'
            '      Dart:   ${d[field]}'
            "${known == null ? '' : '\n      why:    $known'}",
          );
          if (known == null) {
            unexpected++;
          }
        }
      }
      // The report of the comparison is this test's output.
      // ignore: avoid_print
      print(report);
      expect(unexpected, 0, reason: 'unexplained differences (see above)');
    });
  });

  test('the form login flow steps like Spring Security', () async {
    if (spring == null) {
      markTestSkipped('Build tool/security_reference first (mvn package)');
      return;
    }
    await withDart((dartPort) async {
      final fromSpring = await _loginFlow(springPort);
      final fromDart = await _loginFlow(dartPort);
      // The two flows side by side are this test's output.
      // ignore: avoid_print
      print('Spring: $fromSpring\nDart:   $fromDart');
      // Both come from Spring Boot's /error dispatch: the CSRF 403 is
      // re-dispatched to /error, where the anonymous browser is sent to the
      // login page — and /error is saved as the page to come back to, so
      // Spring sends the user to /error after the login. Here the 403 is
      // answered and the user gets back to the page they wanted.
      const known = {
        'no token: 302 /login': 'no token: 403',
        'login: 302 /error?continue': 'login: 302 /api/me?continue',
      };
      expect(fromDart, [for (final step in fromSpring) known[step] ?? step]);
    });
  });
}
