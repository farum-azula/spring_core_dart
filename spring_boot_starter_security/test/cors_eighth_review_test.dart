// Regression tests of the eighth review before 0.5.0, through the default
// security chain and its CORS filter: a handler's own Vary next to the CORS
// names, an Origin outside visible US-ASCII, and a pre-flight to a mapped
// path without CORS rules (Spring Security's CorsFilter ends every
// pre-flight; without rules, with a 200 and no CORS header).
import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

const _corsVary = [
  'Origin',
  'Access-Control-Request-Method',
  'Access-Control-Request-Headers',
];

void main() {
  final app = springBootTest(
    SpringApplication(
      [_module],
      autoConfigurations: [
        springBootAutoConfiguration,
        springBootStarterLoggingAutoConfiguration,
        springBootStarterWebAutoConfiguration,
        springSecurityCoreAutoConfiguration,
        springBootStarterOauth2ClientAutoConfiguration,
        springBootStarterSecurityAutoConfiguration,
      ],
    ),
    properties: {
      'logging.level.root': 'off',
      'spring.security.user.password': 'pw',
    },
  );

  // user:pw
  const basic = {'Authorization': 'Basic dXNlcjpwdw=='};

  Future<MockServerHttpResponse> send(
    HttpMethod method,
    String path,
    Map<String, String> headers,
  ) async => (await app.mockMvc.perform(
    MockRequestBuilder(method, path)..headers.addAll(headers),
  )).response;

  test("a ResponseEntity's Vary joins the CORS names of the filter", () async {
    for (final origin in [null, 'https://a.example.com']) {
      final response = await send(HttpMethod.get, '/entity', {
        ...basic,
        'Origin': ?origin,
      });
      expect(response.statusCode, 200);
      expect(response.headers.getAll('Vary'), [
        ..._corsVary,
        'Accept-Language',
      ], reason: '$origin');
    }
  });

  test('an Origin outside visible US-ASCII that the pattern matches: 403 '
      'before the security checks, nothing echoed', () async {
    for (final headers in [
      <String, String>{},
      basic,
    ]) {
      final response = await send(HttpMethod.get, '/entity', {
        ...headers,
        'Origin': 'https://\u00e9.example.com',
      });
      expect(response.statusCode, 403);
      expect(response.bodyText, 'Invalid CORS request');
      expect(response.headers['Access-Control-Allow-Origin'], isNull);
    }
  });

  test('a pre-flight to a mapped path without CORS rules: 200 with no CORS '
      'header and no Vary, from another origin or its own, as in '
      'Spring', () async {
    for (final (origin, method) in [
      ('https://other.example', 'GET'),
      ('https://other.example', 'DELETE'),
      ('http://localhost', 'GET'),
    ]) {
      final response = await send(HttpMethod.options, '/nocors', {
        'Origin': origin,
        'Access-Control-Request-Method': method,
      });
      expect(response.statusCode, 200, reason: '$origin $method');
      expect(
        response.headers.names.where(
          (name) => name.toLowerCase().startsWith('access-control-'),
        ),
        isEmpty,
      );
      expect(response.headers.getAll('Vary'), isEmpty);
    }
    // The request itself still needs a login.
    final anonymous = await send(HttpMethod.get, '/nocors', {
      'Origin': 'https://other.example',
    });
    expect(anonymous.statusCode, 401);
  });
}

final class _Patterns {
  ResponseEntity<String> entity() =>
      ResponseEntity.status(200).header('Vary', ['Accept-Language']).body('x');
}

final class _NoCors {
  String plain() => 'n';
}

final _module = BeanModule('security_cors_eighth_review', [
  BeanDefinition<_Patterns>(
    name: 'patterns',
    types: const [_Patterns],
    create: (_) => _Patterns(),
    annotatedMethods: [
      BeanMethod<_Patterns>(
        'entity',
        returnTypeInfo: const GenericType<ResponseEntity<String>>([
          ClassType<String>(),
        ]),
        invoke: (bean, arguments) => Function.apply(bean.entity, arguments),
        annotations: const [GetMapping('/entity')],
      ),
    ],
    annotations: const [
      RestController(),
      CrossOrigin(originPatterns: ['https://*.example.com']),
    ],
  ),
  BeanDefinition<_NoCors>(
    name: 'noCors',
    types: const [_NoCors],
    create: (_) => _NoCors(),
    annotatedMethods: [
      BeanMethod<_NoCors>(
        'plain',
        returnTypeInfo: const ClassType<String>(),
        invoke: (bean, arguments) => Function.apply(bean.plain, arguments),
        annotations: const [GetMapping('/nocors')],
      ),
    ],
    annotations: const [RestController()],
  ),
]);
