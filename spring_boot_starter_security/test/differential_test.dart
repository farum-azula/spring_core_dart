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
//
// oauth2Login() too: a second Spring process (profile `oauth2`,
// OAuth2LoginReference) and a Dart application with the same chain log in
// at the same fake OpenID Connect provider (differential_provider.dart);
// the same browser steps (the redirect to the provider, callbacks with
// good, wrong and missing state, provider errors, replays, mix-ups, a
// provider that misbehaves, the logout) must end the same way.
//
// And the DPoP resource server (RFC 9449): a third Spring process (profile
// `dpop`, Spring Boot's resource server chain with `dPoP()`) and the
// starter's default chain check tokens of the same JWK Set; the same
// DPoP requests (the attacks of dpop_test.dart) must get the same status
// and challenge.
@Tags(['differential'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:test/test.dart';

import 'app/jwt/keys.dart';
import 'app/rules/rules.dart';
import 'app/web/web.dart';
import 'differential_provider.dart';
import 'dpop_support.dart';
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
  // Under the bean's paths its rules alone apply, @CrossOrigin(app.example)
  // of the handler neither (the ninth review).
  const Probe(
    'preflight @CrossOrigin',
    'OPTIONS',
    '/api/cors',
    headers: [
      ('Origin', 'https://app.example'),
      ('Access-Control-Request-Method', 'GET'),
    ],
  ),
  // No CORS rules for these paths: Spring's CorsFilter ends every
  // pre-flight, here with a 200 and no CORS header (the eighth review).
  const Probe(
    'preflight no rules',
    'OPTIONS',
    '/public/hello',
    headers: [
      ('Origin', 'https://evil.example'),
      ('Access-Control-Request-Method', 'GET'),
    ],
  ),
  const Probe(
    'preflight no rules protected',
    'OPTIONS',
    '/',
    headers: [
      ('Origin', 'https://evil.example'),
      ('Access-Control-Request-Method', 'DELETE'),
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
  Probe(
    'cors actual @CrossOrigin',
    'GET',
    '/api/cors',
    headers: [('Origin', 'https://app.example'), _ada],
  ),
  const Probe(
    'preflight @CrossOrigin headers',
    'OPTIONS',
    '/api/cors',
    headers: [
      ('Origin', 'https://trusted.example'),
      ('Access-Control-Request-Method', 'GET'),
      ('Access-Control-Request-Headers', 'authorization'),
    ],
  ),
  // The method of an actual request is checked too: the bean allows GET
  // and POST (the ninth review).
  Probe(
    'cors HEAD',
    'HEAD',
    '/api/me',
    headers: [('Origin', 'https://trusted.example'), _ada],
  ),
  Probe(
    'cors HEAD @CrossOrigin',
    'HEAD',
    '/api/cors',
    headers: [('Origin', 'https://trusted.example'), _ada],
  ),
  const Probe(
    'cors HEAD anonymous',
    'HEAD',
    '/api/cors',
    headers: [('Origin', 'https://trusted.example')],
  ),
  Probe(
    'cors OPTIONS',
    'OPTIONS',
    '/api/cors',
    headers: [('Origin', 'https://trusted.example'), _ada],
  ),
  const Probe(
    'cors OPTIONS anonymous',
    'OPTIONS',
    '/api/cors',
    headers: [('Origin', 'https://trusted.example')],
  ),
  Probe(
    'cors PUT',
    'PUT',
    '/api/data',
    headers: [('Origin', 'https://trusted.example'), _ada],
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

// oauth2Login(): the same chain on both sides, the same fake provider.

/// The registration both applications have (Spring's is in its
/// application-oauth2.properties); the issuer is the fake provider's.
const _fake = 'spring.security.oauth2.client.registration.fake';

List<String> _oauth2Properties(String issuer) => [
  '$_fake.client-id=$differentialClientId',
  '$_fake.client-secret=$differentialClientSecret',
  '$_fake.scope=openid,profile',
  'spring.security.oauth2.client.provider.fake.issuer-uri=$issuer',
];

/// The Dart twin of tool/security_reference's OAuth2LoginReference.
final BeanModule _oauth2LoginBeans = BeanModule('oauth2LoginReference', [
  BeanDefinition<SecurityFilterChain>(
    name: 'oauth2FilterChain',
    types: const [SecurityFilterChain],
    source: 'differential_test#oauth2FilterChain',
    create: (r) => r
        .dependency<HttpSecurity>()
        .authorizeHttpRequests(
          (auth) => auth
              .requestMatchers('/public/**')
              .permitAll()
              .anyRequest()
              .authenticated(),
        )
        .oauth2Login()
        .logout(
          (logout) => logout.logoutSuccessHandler(
            OidcClientInitiatedLogoutSuccessHandler(
              r.dependency<ClientRegistrationRepository>(),
              postLogoutRedirectUri: '{baseUrl}/public/hello',
            ),
          ),
        )
        .build(),
  ),
]);

/// The values that differ on every run (or are secrets) are compared as
/// `*`.
const _randomParameters = {'state', 'nonce', 'code_challenge', 'id_token_hint'};

/// A Location without its origin and session id, its parameters sorted,
/// the random ones `*`, and URLs inside it without their origin (the
/// ports differ).
String _normalizedLocation(String? location) {
  if (location == null) {
    return '';
  }
  final uri = Uri.parse(location);
  // Tomcat's session id in the URL (no cookie yet) differs on every run.
  final path = uri.path.replaceFirst(RegExp(r';jsessionid=[^/]*$'), '');
  if (!uri.hasQuery) {
    return path;
  }
  final parameters = [
    for (final part in uri.query.split('&'))
      () {
        final eq = part.indexOf('=');
        if (eq < 0) {
          return part;
        }
        final name = part.substring(0, eq);
        final value = Uri.decodeQueryComponent(part.substring(eq + 1));
        return _randomParameters.contains(name)
            ? '$name=*'
            : '$name=${value.replaceFirst(RegExp('^https?://[^/]+'), '')}';
      }(),
  ]..sort();
  return '$path?${parameters.join('&')}';
}

/// Cookie names and flags; SameSite left out (Lax here, none in Spring
/// Boot: the catalog's known difference).
String _cookieFlags(Answer answer) {
  final cookies = [
    for (final cookie in answer.headers['set-cookie'] ?? const <String>[])
      () {
        final parts = cookie.split(';').map((p) => p.trim()).toList();
        final flags = [
          for (final p in parts.skip(1))
            if (!p.toLowerCase().startsWith('samesite'))
              p.split('=').first.toLowerCase(),
        ]..sort();
        return '${parts.first.split('=').first}[${flags.join(',')}]';
      }(),
  ]..sort();
  return cookies.join(' ');
}

/// One run of a scenario against one application: its browsers and the
/// steps they saw.
final class _OAuth2Run {
  _OAuth2Run(this.port, this.provider);

  final int port;
  final HttpOidcProvider provider;
  final List<String> steps = [];

  _Session browser() => _Session(port);

  Future<Answer> step(String name, Future<Answer> pending) async {
    final answer = await pending;
    final location = _normalizedLocation(answer.header('location'));
    steps.add(
      '$name: ${answer.status} $location ${_cookieFlags(answer)}'.trim(),
    );
    return answer;
  }

  void note(String text) => steps.add(text);

  /// `GET /oauth2/authorization/fake` in [browser]: the provider's URL.
  Future<Uri> start(_Session browser) async => Uri.parse(
    (await browser('GET', '/oauth2/authorization/fake')).header('location')!,
  );

  /// A whole login in [browser]; the callback it used.
  Future<Uri> login(_Session browser) async {
    final callback = provider.approve(await start(browser));
    await browser('GET', _target(callback));
    return callback;
  }
}

String _target(Uri uri) => uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

Uri _with(Uri uri, Map<String, String?> changes) => uri.replace(
  queryParameters: {
    for (final MapEntry(:key, :value) in {
      ...uri.queryParameters,
      ...changes,
    }.entries)
      key: ?value,
  },
);

/// The browser steps sent to both applications, by scenario.
final _oauth2Scenarios = <String, Future<void> Function(_OAuth2Run run)>{
  // /api/principal answers text: Spring replays the saved request's own
  // headers (Accept: text/html) when the browser comes back.
  'login, the saved page, a replayed callback': (run) async {
    final browser = run.browser();
    await run.step('protected page', browser('GET', '/api/principal'));
    final start = await run.step(
      'authorization redirect',
      browser('GET', '/oauth2/authorization/fake'),
    );
    final before = browser.cookies['JSESSIONID'];
    final callback = run.provider.approve(
      Uri.parse(start.header('location')!),
    );
    await run.step('callback', browser('GET', _target(callback)));
    run.note('session id changed: ${browser.cookies['JSESSIONID'] != before}');
    await run.step('saved page', browser('GET', '/api/principal?continue'));
    await run.step('replayed callback', browser('GET', _target(callback)));
    await run.step(
      'after the replay',
      browser('GET', '/api/me', accept: 'application/json'),
    );
  },
  'protected page, json': (run) => run.step(
    'protected page',
    run.browser()('GET', '/api/me', accept: 'application/json'),
  ),
  'login page': (run) => run.step('login page', run.browser()('GET', '/login')),
  'unknown registration': (run) => run.step(
    'authorization redirect',
    run.browser()('GET', '/oauth2/authorization/nope'),
  ),
  'wrong state': (run) async {
    final browser = run.browser();
    final callback = run.provider.approve(await run.start(browser));
    await run.step(
      'callback',
      browser('GET', _target(_with(callback, {'state': 'forged'}))),
    );
  },
  'missing state': (run) async {
    final browser = run.browser();
    final callback = run.provider.approve(await run.start(browser));
    await run.step(
      'callback',
      browser('GET', _target(_with(callback, {'state': null}))),
    );
  },
  'the callback in another browser (login CSRF)': (run) async {
    final callback = run.provider.approve(await run.start(run.browser()));
    await run.step('callback', run.browser()('GET', _target(callback)));
  },
  'a callback without a login': (run) => run.step(
    'callback',
    run.browser()('GET', '/login/oauth2/code/fake?code=x&state=y'),
  ),
  'provider error': (run) async {
    final browser = run.browser();
    final state = (await run.start(browser)).queryParameters['state']!;
    await run.step(
      'callback',
      browser(
        'GET',
        '/login/oauth2/code/fake?error=access_denied&state=$state',
      ),
    );
  },
  'provider error without state': (run) async {
    final browser = run.browser();
    await run.start(browser);
    await run.step(
      'callback',
      browser('GET', '/login/oauth2/code/fake?error=access_denied'),
    );
  },
  'a used code in another login': (run) async {
    final used = await run.login(run.browser());
    final browser = run.browser();
    final state = (await run.start(browser)).queryParameters['state']!;
    await run.step(
      'callback',
      browser('GET', _target(_with(used, {'state': state}))),
    );
  },
  "another login's unused code (code injection)": (run) async {
    final stolen = run.provider.approve(await run.start(run.browser()));
    final browser = run.browser();
    final state = (await run.start(browser)).queryParameters['state']!;
    await run.step(
      'callback',
      browser('GET', _target(_with(stolen, {'state': state}))),
    );
  },
  'mix-up: another iss (RFC 9207)': (run) async {
    final browser = run.browser();
    final callback = run.provider.approve(await run.start(browser));
    await run.step(
      'callback',
      browser(
        'GET',
        _target(_with(callback, {'iss': 'http://evil.example'})),
      ),
    );
  },
  'mix-up: the callback of another registration': (run) async {
    final browser = run.browser();
    final callback = run.provider.approve(await run.start(browser));
    await run.step(
      'callback',
      browser(
        'GET',
        _target(callback.replace(path: '/login/oauth2/code/other')),
      ),
    );
  },
  'an ID token for another audience': (run) async {
    run.provider.audience = 'another-client';
    final browser = run.browser();
    final callback = run.provider.approve(await run.start(browser));
    await run.step('callback', browser('GET', _target(callback)));
  },
  'an ID token with another nonce': (run) async {
    run.provider.forcedNonce = 'forged';
    final browser = run.browser();
    final callback = run.provider.approve(await run.start(browser));
    await run.step('callback', browser('GET', _target(callback)));
  },
  'logout': (run) async {
    final browser = run.browser();
    await run.login(browser);
    final page = await run.step('logout page', browser('GET', '/logout'));
    await run.step('logout without csrf', browser('POST', '/logout', form: {}));
    final session = browser.cookies['JSESSIONID'];
    await run.step(
      'logout',
      browser('POST', '/logout', form: {'_csrf': _Session.csrf(page.body)}),
    );
    await run.step(
      'old session after logout',
      send(
        run.port,
        'GET',
        '/api/me',
        headers: [
          ('Cookie', 'JSESSIONID=$session'),
          ('Accept', 'application/json'),
        ],
      ),
    );
  },
};

// Why an oauth2Login() difference is on purpose (see the README's
// differences).
const _unknownRegistration =
    'an unknown registration id: Spring answers 500, which Spring Boot '
    're-dispatches to /error, where the anonymous browser is sent to the '
    'login (a new session); here a 400 is answered';
const _failureSession =
    "Spring's failure handler keeps the exception in the session for its "
    'login page and so creates one for a browser that had none; a failed '
    'login creates no session here';
const _issParameter =
    'RFC 9207: the `iss` of the redirect back must be the issuer here when '
    'the provider announces it '
    '(authorization_response_iss_parameter_supported), against mix-up '
    'attacks; Spring Security 7.1 ignores the parameter';
const _otherRedirect =
    'the redirect back must arrive at the redirect URI of the registration '
    'that started the login here; Spring Security 7.1 takes the '
    'registration from the saved request and accepts any '
    '/login/oauth2/code/*';

const _noSession =
    'no session before a login: the authorization request and the page to '
    'come back to are signed cookies (their flags are in '
    'web_attacks_test.dart), the CSRF token a cookie; the login still '
    'starts a session with a new id';

// The cookies the starter sets where Spring Security uses the session.
final _signedCookies = RegExp(
  r' ?(REDIRECT_URI|OAUTH2_AUTHORIZATION_REQUEST|XSRF-TOKEN)\[[^\]]*\]',
);

/// [step] without the cookies of [_signedCookies].
String _withoutSignedCookies(String step) =>
    step.replaceAll(_signedCookies, '').trimRight();

/// Differences of the oauth2Login() steps that are on purpose:
/// `scenario/Spring's step` → (Dart's step, why).
final _oauth2KnownDifferences = <String, (String, String)>{
  'login, the saved page, a replayed callback/protected page: 302 '
      '/oauth2/authorization/fake JSESSIONID[httponly,path]': (
    'protected page: 302 /oauth2/authorization/fake',
    _noSession,
  ),
  'unknown registration/authorization redirect: 302 '
      '/oauth2/authorization/fake JSESSIONID[httponly,path]': (
    'authorization redirect: 400',
    _unknownRegistration,
  ),
  for (final scenario in [
    'the callback in another browser (login CSRF)',
    'a callback without a login',
  ])
    '$scenario/callback: 302 /login?error JSESSIONID[httponly,path]': (
      'callback: 302 /login?error',
      _failureSession,
    ),
  'mix-up: another iss (RFC 9207)/callback: 302 / '
      'JSESSIONID[httponly,path]': (
    'callback: 302 /login?error',
    _issParameter,
  ),
  'mix-up: the callback of another registration/callback: 302 / '
      'JSESSIONID[httponly,path]': (
    'callback: 302 /login?error',
    _otherRedirect,
  ),
};

// DPoP (RFC 9449): Spring Boot's resource server chain on both sides
// (Spring's with `dPoP()`, DPoPResourceServerReference), the keys from the
// fake provider's JWK Set.

const _jwkSetUri = 'spring.security.oauth2.resourceserver.jwt.jwk-set-uri';

final _client = ProofSigner.ec();
final _otherKey = ProofSigner.ec();
final String _bound = boundToken(_client);
final String _unbound = testKeys.token();

List<(String, String)> _dPoP(String token, String proof) => [
  ('Authorization', 'DPoP $token'),
  ('DPoP', proof),
];

/// The requests of a probe for the URL `http://localhost:<port>/api/me`;
/// the last answer is compared.
final _dPoPProbes = <String, List<List<(String, String)>> Function(String)>{
  'a valid proof': (url) => [
    _dPoP(_bound, _client.proof(url: url, accessToken: _bound)),
  ],
  'an unbound token as Bearer': (url) => [
    [('Authorization', 'Bearer $_unbound')],
  ],
  'a replayed proof': (url) {
    final proof = _client.proof(url: url, accessToken: _bound);
    return [_dPoP(_bound, proof), _dPoP(_bound, proof)];
  },
  'a bound token as Bearer': (url) => [
    [('Authorization', 'Bearer $_bound')],
  ],
  'a bound token as Bearer, with a proof': (url) => [
    [
      ('Authorization', 'Bearer $_bound'),
      ('DPoP', _client.proof(url: url, accessToken: _bound)),
    ],
  ],
  'the DPoP scheme without a proof': (url) => [
    [('Authorization', 'DPoP $_bound')],
  ],
  'a proof without a token': (url) => [
    [('DPoP', _client.proof(url: url))],
  ],
  'an unbound token with a proof': (url) => [
    _dPoP(_unbound, _client.proof(url: url, accessToken: _unbound)),
  ],
  'a proof of another key': (url) => [
    _dPoP(_bound, _otherKey.proof(url: url, accessToken: _bound)),
  ],
  "the client's jwk, signed by another key": (url) => [
    _dPoP(
      _bound,
      _client.proof(url: url, accessToken: _bound, signWith: _otherKey),
    ),
  ],
  'another htm': (url) => [
    _dPoP(
      _bound,
      _client.proof(method: 'POST', url: url, accessToken: _bound),
    ),
  ],
  'htm in lower case': (url) => [
    _dPoP(
      _bound,
      _client.proof(method: 'get', url: url, accessToken: _bound),
    ),
  ],
  'another htu path': (url) => [
    _dPoP(
      _bound,
      _client.proof(url: '${url}x', accessToken: _bound),
    ),
  ],
  'htu with the host in capitals': (url) => [
    _dPoP(
      _bound,
      _client.proof(
        url: url.replaceFirst('localhost', 'LOCALHOST'),
        accessToken: _bound,
      ),
    ),
  ],
  'htu with a query': (url) => [
    _dPoP(_bound, _client.proof(url: '$url?x=1', accessToken: _bound)),
  ],
  'a stale iat': (url) => [
    _dPoP(
      _bound,
      _client.proof(
        url: url,
        accessToken: _bound,
        iat: TokenFactory.now() - 3600,
      ),
    ),
  ],
  'an iat in the future': (url) => [
    _dPoP(
      _bound,
      _client.proof(
        url: url,
        accessToken: _bound,
        iat: TokenFactory.now() + 3600,
      ),
    ),
  ],
  'no ath': (url) => [_dPoP(_bound, _client.proof(url: url))],
  'a wrong ath': (url) => [
    _dPoP(
      _bound,
      _client.proof(
        url: url,
        accessToken: _bound,
        claims: {'ath': sha256Base64Url('another token')},
      ),
    ),
  ],
  'alg none': (url) => [
    _dPoP(_bound, _client.proof(url: url, accessToken: _bound, alg: 'none')),
  ],
  'HS256': (url) => [
    _dPoP(_bound, _client.proof(url: url, accessToken: _bound, alg: 'HS256')),
  ],
  'a private d in the jwk': (url) => [
    _dPoP(
      _bound,
      _client.proof(
        url: url,
        accessToken: _bound,
        header: {
          'jwk': {..._client.publicJwk, 'd': _client.privateD},
        },
      ),
    ),
  ],
  'typ JWT': (url) => [
    _dPoP(
      _bound,
      _client.proof(url: url, accessToken: _bound, header: {'typ': 'JWT'}),
    ),
  ],
  'two DPoP headers': (url) => [
    [
      ..._dPoP(_bound, _client.proof(url: url, accessToken: _bound)),
      ('DPoP', _client.proof(url: url, accessToken: _bound)),
    ],
  ],
  'no Authorization': (url) => [const []],
  // The type of the access token (Spring 7's JwtTypeValidator.jwt()):
  // JWT in any case or none; other JWTs of the issuer are refused.
  'typ logout+jwt as Bearer': (url) => [
    [('Authorization', 'Bearer ${_typed('logout+jwt')}')],
  ],
  'typ secevent+jwt as Bearer': (url) => [
    [('Authorization', 'Bearer ${_typed('secevent+jwt')}')],
  ],
  'typ dpop+jwt as Bearer': (url) => [
    [('Authorization', 'Bearer ${_typed('dpop+jwt')}')],
  ],
  'typ at+jwt as Bearer': (url) => [
    [('Authorization', 'Bearer ${_typed('at+jwt')}')],
  ],
  'typ jwt in lower case as Bearer': (url) => [
    [('Authorization', 'Bearer ${_typed('jwt')}')],
  ],
  'no typ as Bearer': (url) => [
    [('Authorization', 'Bearer ${_typed(null)}')],
  ],
  // Bound to a client certificate (RFC 8705), sent without one.
  'a certificate-bound token as Bearer': (url) => [
    [('Authorization', 'Bearer $_certificateBound')],
  ],
  'a certificate-bound DPoP token with a valid proof': (url) {
    final token = boundToken(
      _client,
      claims: {
        'cnf': {'jkt': _client.thumbprint, 'x5t#S256': _x5t},
      },
    );
    return [_dPoP(token, _client.proof(url: url, accessToken: token))];
  },
};

String _typed(String? type) => testKeys.token(header: {'typ': type});

final String _x5t = sha256Base64Url('a client certificate');
final String _certificateBound = testKeys.token(
  claims: {
    'cnf': {'x5t#S256': _x5t},
  },
);

/// A challenge reduced to its scheme and error code (the descriptions and
/// the algorithm lists are worded differently).
String _challenge(String? header) {
  if (header == null) {
    return '';
  }
  final scheme = header.split(' ').first;
  final error = RegExp('error="([^"]*)"').firstMatch(header)?[1];
  return error == null ? scheme : '$scheme error=$error';
}

// Why a DPoP difference is on purpose (see the README's differences).
const _htmCase =
    'htm is compared case-sensitively here, as HTTP methods are; Spring '
    'ignores its case';
const _htuNormalized =
    'htu is compared as RFC 9449 §4.3 says here: after RFC 3986 '
    "normalization (the host's case does not matter) and without its query "
    'and fragment; Spring compares the text';

/// Differences of the DPoP probes that are on purpose: `probe/field`.
final _dPoPKnownDifferences = <String, String>{
  for (final field in ['status', 'www-authenticate']) ...{
    'htm in lower case/$field': _htmCase,
    'htu with the host in capitals/$field': _htuNormalized,
    'htu with a query/$field': _htuNormalized,
  },
};

/// The reference jar started with [arguments] on a free port, once it
/// answers.
Future<(Process, int)> _startReference(List<String> arguments) async {
  final probe = await ServerSocket.bind('127.0.0.1', 0);
  final port = probe.port;
  await probe.close();
  final process = await Process.start('java', [
    '-jar',
    _jar.path,
    '--server.port=$port',
    '--server.address=127.0.0.1',
    ...arguments,
  ]);
  final output = StringBuffer();
  process.stdout.transform(utf8.decoder).listen(output.write, onError: (_) {});
  unawaited(process.stderr.drain<void>());
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (DateTime.now().isBefore(deadline)) {
    try {
      await send(port, 'GET', '/public/hello');
      return (process, port);
    } on Object {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }
  process.kill();
  throw StateError('The Spring reference ($arguments) did not start:\n$output');
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

  group('oauth2Login()', () {
    HttpOidcProvider? provider;
    Process? springOAuth2;
    late int springOAuth2Port;

    setUpAll(() async {
      if (!_jar.existsSync()) {
        return; // the catalog's setUpAll already failed in CI
      }
      provider = await HttpOidcProvider.start();
      (springOAuth2, springOAuth2Port) = await _startReference([
        '--spring.profiles.active=oauth2',
        '--${_oauth2Properties(provider!.issuer).last}',
      ]);
    });

    tearDownAll(() async {
      springOAuth2?.kill();
      await provider?.close();
    });

    Future<void> withDartOAuth2(Future<void> Function(int port) body) =>
        const ApplicationContextRunner()
            .withUserConfiguration(securityWebBeans)
            .withUserConfiguration(_oauth2LoginBeans)
            .withAutoConfiguration(springBootAutoConfiguration)
            .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
            .withAutoConfiguration(springBootStarterWebAutoConfiguration)
            .withAutoConfiguration(springBootStarterFeignAutoConfiguration)
            .withAutoConfiguration(springSecurityCoreAutoConfiguration)
            .withAutoConfiguration(
              springBootStarterOauth2ClientAutoConfiguration,
            )
            .withAutoConfiguration(
              springBootStarterSecurityAutoConfiguration,
              const AutoConfigurationModule(
                after: ['springBootStarterOauth2ClientAutoConfiguration'],
              ),
            )
            .withAutoConfiguration(
              springBootStarterSecurityOAuth2ClientAutoConfiguration,
              const AutoConfigurationModule(
                before: ['springBootStarterOauth2ClientAutoConfiguration'],
              ),
            )
            .withPropertyValues([
              'spring.test.web-environment=random-port',
              'server.address=127.0.0.1',
              'logging.level.root=warn',
              ..._oauth2Properties(provider!.issuer),
            ])
            .runAsync((started) async {
              final failure = started.startupFailure;
              if (failure != null) {
                fail('The application failed to start: $failure');
              }
              final server = (await started.context
                  .getBean<WebServerStartStopLifecycle>()
                  .started)!;
              await body(server.port);
            });

    test('the login steps end like Spring Security', () async {
      if (springOAuth2 == null) {
        markTestSkipped('Build tool/security_reference first (mvn package)');
        return;
      }
      await withDartOAuth2((dartPort) async {
        final report = StringBuffer();
        var unexpected = 0;
        for (final MapEntry(key: name, value: scenario)
            in _oauth2Scenarios.entries) {
          Future<List<String>> run(int port) async {
            final run = _OAuth2Run(port, provider!);
            try {
              await scenario(run);
            } finally {
              provider!.reset();
            }
            return run.steps;
          }

          final fromSpring = await run(springOAuth2Port);
          final fromDart = await run(dartPort);
          report.writeln(name);
          for (var i = 0; i < fromSpring.length || i < fromDart.length; i++) {
            final s = i < fromSpring.length ? fromSpring[i] : '(none)';
            final d = i < fromDart.length ? fromDart[i] : '(none)';
            if (s == d) {
              report.writeln('  same   $s');
              continue;
            }
            final plain = _withoutSignedCookies(d);
            final known = plain == s && plain != d
                ? (plain, _noSession)
                : _oauth2KnownDifferences['$name/$s'];
            if (known != null && known.$1 == plain) {
              report.writeln(
                '  known  Spring: $s\n         Dart:   $d\n'
                '         why:    ${known.$2}',
              );
            } else {
              unexpected++;
              report.writeln('  DIFF   Spring: $s\n         Dart:   $d');
            }
          }
        }
        // The report of the comparison is this test's output.
        // ignore: avoid_print
        print(report);
        expect(unexpected, 0, reason: 'unexplained differences (see above)');
      });
    });
  });

  group('DPoP resource server', () {
    HttpOidcProvider? provider;
    Process? springDPoP;
    late int springDPoPPort;

    setUpAll(() async {
      if (!_jar.existsSync()) {
        return; // the catalog's setUpAll already failed in CI
      }
      provider = await HttpOidcProvider.start();
      (springDPoP, springDPoPPort) = await _startReference([
        '--spring.profiles.active=dpop',
        '--$_jwkSetUri=${provider!.issuer}/jwks',
      ]);
    });

    tearDownAll(() async {
      springDPoP?.kill();
      await provider?.close();
    });

    test('the DPoP requests answer like Spring Security', () async {
      if (springDPoP == null) {
        markTestSkipped('Build tool/security_reference first (mvn package)');
        return;
      }
      await securityRunner(null, [
        'spring.test.web-environment=random-port',
        'server.address=127.0.0.1',
        '$_jwkSetUri=${provider!.issuer}/jwks',
      ]).runAsync((started) async {
        final failure = started.startupFailure;
        if (failure != null) {
          fail('The application failed to start: $failure');
        }
        final dartPort =
            (await started.context
                    .getBean<WebServerStartStopLifecycle>()
                    .started)!
                .port;
        Future<Map<String, String>> answer(
          int port,
          List<List<(String, String)>> Function(String) probe,
        ) async {
          Answer? last;
          for (final headers in probe('http://localhost:$port/api/me')) {
            last = await send(
              port,
              'GET',
              '/api/me',
              headers: [('Accept', 'application/json'), ...headers],
            );
          }
          return {
            'status': '${last!.status}',
            'www-authenticate': _challenge(last.header('www-authenticate')),
          };
        }

        final report = StringBuffer();
        var unexpected = 0;
        for (final MapEntry(key: name, value: probe) in _dPoPProbes.entries) {
          final s = await answer(springDPoPPort, probe);
          final d = await answer(dartPort, probe);
          for (final field in s.keys) {
            final key = '$name/$field';
            final known = _dPoPKnownDifferences[key];
            if (s[field] == d[field]) {
              report.writeln('same   $key: ${s[field]}');
              continue;
            }
            report.writeln(
              '${known == null ? 'DIFF ' : 'known'}  $key\n'
              '       Spring: ${s[field]}\n'
              '       Dart:   ${d[field]}'
              "${known == null ? '' : '\n       why:    $known'}",
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

    // Both chains keep CSRF protection on (Spring Boot's default):
    // Spring's registerDefaultCsrfOverride exempts requests with a Bearer
    // token, not those with a DPoP one; the starter exempts both.
    test('token requests that change state, with CSRF on', () async {
      if (springDPoP == null) {
        markTestSkipped('Build tool/security_reference first (mvn package)');
        return;
      }
      await securityRunner(null, [
        'spring.test.web-environment=random-port',
        'server.address=127.0.0.1',
        '$_jwkSetUri=${provider!.issuer}/jwks',
      ]).runAsync((started) async {
        final failure = started.startupFailure;
        if (failure != null) {
          fail('The application failed to start: $failure');
        }
        final dartPort =
            (await started.context
                    .getBean<WebServerStartStopLifecycle>()
                    .started)!
                .port;
        Future<int> status(
          int port,
          String method,
          List<(String, String)> Function(String url) headers, {
          String path = '/api/data',
        }) async => (await send(
          port,
          method,
          path,
          headers: [
            ('Accept', 'application/json'),
            ('Content-Type', 'text/plain'),
            ...headers('http://localhost:$port$path'),
          ],
          body: 'order',
        )).status;

        final probes =
            <String, (String, List<(String, String)> Function(String), String)>{
              'POST with a Bearer token': (
                'POST',
                (_) => [('Authorization', 'Bearer $_unbound')],
                '/api/data',
              ),
              'PUT with a Bearer token': (
                'PUT',
                (_) => [('Authorization', 'Bearer $_unbound')],
                '/api/data',
              ),
              'POST with a DPoP token': (
                'POST',
                (url) => _dPoP(
                  _bound,
                  _client.proof(method: 'POST', url: url, accessToken: _bound),
                ),
                '/api/data',
              ),
              'POST /logout with a Bearer token': (
                'POST',
                (_) => [('Authorization', 'Bearer $_unbound')],
                '/logout',
              ),
            };
        const known = {
          'POST with a DPoP token':
              'Spring exempts Bearer tokens from CSRF, not DPoP ones (its '
              '403 goes through /error as an anonymous 401); the starter '
              'exempts both: a browser never sends either header by itself',
          'POST /logout with a Bearer token':
              'Spring exempts the token request from CSRF and its logout '
              'filter, which runs before the token is checked, answers; '
              'the starter keeps the CSRF check at the logout and login '
              'URLs, where a token would decide nothing',
        };
        final report = StringBuffer();
        var unexpected = 0;
        for (final MapEntry(key: name, value: (method, headers, path))
            in probes.entries) {
          final s = await status(springDPoPPort, method, headers, path: path);
          final d = await status(dartPort, method, headers, path: path);
          if (s == d) {
            report.writeln('same   $name: $s');
            continue;
          }
          final why = known[name];
          report.writeln(
            '${why == null ? 'DIFF ' : 'known'}  $name\n'
            '       Spring: $s\n'
            '       Dart:   $d'
            "${why == null ? '' : '\n       why:    $why'}",
          );
          if (why == null) {
            unexpected++;
          }
        }
        // The report of the comparison is this test's output.
        // ignore: avoid_print
        print(report);
        expect(unexpected, 0, reason: 'unexplained differences (see above)');
        // The starter's own answer to the DPoP POST: accepted.
        expect(
          await status(
            dartPort,
            'POST',
            (url) => _dPoP(
              _bound,
              _client.proof(method: 'POST', url: url, accessToken: _bound),
            ),
          ),
          200,
        );
      });
    });
  });
}
