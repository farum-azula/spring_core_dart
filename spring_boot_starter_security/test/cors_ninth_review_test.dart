// Regression tests of the ninth review before 0.5.0, through the default
// security chain and its CORS filter: the rules of the handler the router
// would call, chosen with its consumes / produces conditions too (Spring
// Security's CorsFilter asks Spring MVC's HandlerMappingIntrospector); the
// method of an actual request checked; a CorsConfigurationSource bean
// deciding alone where it has rules. The expected values are Spring
// Security 7.1.2's (Spring MVC 7.0.10, `.cors(withDefaults())`, the same
// controllers, October 2026).
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

  group('two GET /items handlers told apart by produces, each with its '
      '@CrossOrigin: the filter takes the rules of the one the router '
      'calls', () {
    test('each origin reads its own media type, and only that', () async {
      for (final (accept, origin, status, body) in [
        ('text/csv', 'https://b.example', 200, 'a,b'),
        ('application/json', 'https://a.example', 200, '{}'),
        ('text/csv', 'https://a.example', 403, 'Invalid CORS request'),
        ('application/json', 'https://b.example', 403, 'Invalid CORS request'),
      ]) {
        final response = await send(HttpMethod.get, '/items', {
          ...basic,
          'Accept': accept,
          'Origin': origin,
        });
        final reason = '$accept from $origin';
        expect(response.statusCode, status, reason: reason);
        expect(response.bodyText, body, reason: reason);
        expect(
          response.headers['Access-Control-Allow-Origin'],
          status == 200 ? origin : null,
          reason: reason,
        );
        expect(response.headers.getAll('Vary'), _corsVary, reason: reason);
      }
    });

    test('a media type no handler produces: the 406, without CORS headers, '
        'as in Spring', () async {
      final response = await send(HttpMethod.get, '/items', {
        ...basic,
        'Accept': 'application/xml',
        'Origin': 'https://a.example',
      });
      expect(response.statusCode, 406);
      expect(response.headers['Access-Control-Allow-Origin'], isNull);
      expect(response.headers.getAll('Vary'), isEmpty);
    });

    test("a pre-flight: the first handler's rules (Spring allows any origin "
        'for a pre-flight several handlers match; see the README)', () async {
      for (final (origin, status) in [
        ('https://a.example', 200),
        ('https://b.example', 403),
      ]) {
        final response = await send(HttpMethod.options, '/items', {
          'Origin': origin,
          'Access-Control-Request-Method': 'GET',
        });
        expect(response.statusCode, status, reason: origin);
      }
    });
  });

  group('the method of an actual request is checked by the filter, before '
      'the security checks', () {
    // Global rules: /g/** from https://a.example, GET only.
    test('GET is allowed; HEAD, POST and OPTIONS are a 403, logged in or '
        'not', () async {
      final get = await send(HttpMethod.get, '/g/x', {
        ...basic,
        'Origin': 'https://a.example',
      });
      expect(get.statusCode, 200);
      expect(get.headers['Access-Control-Allow-Origin'], 'https://a.example');
      for (final headers in [const <String, String>{}, basic]) {
        for (final (method, path) in [
          (HttpMethod.head, '/g/x'),
          (HttpMethod.post, '/g/post'),
          (HttpMethod.options, '/g/x'),
        ]) {
          final response = await send(method, path, {
            ...headers,
            'Origin': 'https://a.example',
          });
          final reason = '${method.value} $path $headers';
          expect(response.statusCode, 403, reason: reason);
          expect(response.headers['Access-Control-Allow-Origin'], isNull);
          expect(response.headers['WWW-Authenticate'], isNull, reason: reason);
        }
      }
    });
  });

  group('a CorsConfigurationSource bean: its rules alone where it has some, '
      'as Spring Security applies its corsConfigurationSource bean', () {
    test("@CrossOrigin's origin is refused under the bean's paths, actual "
        'requests and pre-flights', () async {
      final actual = await send(HttpMethod.get, '/api/cors', {
        ...basic,
        'Origin': 'https://app.example',
      });
      expect(actual.statusCode, 403);
      expect(actual.headers['Access-Control-Allow-Origin'], isNull);
      final preFlight = await send(HttpMethod.options, '/api/cors', {
        'Origin': 'https://app.example',
        'Access-Control-Request-Method': 'GET',
      });
      expect(preFlight.statusCode, 403);
      final trusted = await send(HttpMethod.get, '/api/cors', {
        ...basic,
        'Origin': 'https://trusted.example',
      });
      expect(trusted.statusCode, 200);
      expect(
        trusted.headers['Access-Control-Allow-Origin'],
        'https://trusted.example',
      );
      expect(trusted.headers['Access-Control-Allow-Credentials'], 'true');
    });

    test("elsewhere @CrossOrigin applies, as Spring MVC's after the "
        'filter', () async {
      final response = await send(HttpMethod.get, '/open/cors', {
        ...basic,
        'Origin': 'https://app.example',
      });
      expect(response.statusCode, 200);
      expect(
        response.headers['Access-Control-Allow-Origin'],
        'https://app.example',
      );
    });
  });
}

final class _Items {
  String json() => '{}';
  String csv() => 'a,b';
}

final class _Plain {
  String x() => 'gx';
  String post() => 'gpost';
  String cors() => 'cors';
}

final class _Cors with WebMvcConfigurer {
  @override
  void addCorsMappings(CorsRegistry registry) => registry
      .addMapping('/g/**')
      .allowedOrigins(['https://a.example'])
      .allowedMethods(['GET']);
}

BeanMethod<T> _map<T extends Object>(
  String name,
  Function Function(T bean) method,
  List<Object> annotations,
) => BeanMethod<T>(
  name,
  returnTypeInfo: const ClassType<String>(),
  invoke: (bean, arguments) => Function.apply(method(bean), arguments),
  annotations: annotations,
);

final _module = BeanModule('security_cors_ninth_review', [
  BeanDefinition<_Items>(
    name: 'items',
    types: const [_Items],
    create: (_) => _Items(),
    annotatedMethods: [
      _map<_Items>('json', (b) => b.json, const [
        GetMapping.of(path: '/items', produces: 'application/json'),
        CrossOrigin(origins: ['https://a.example']),
      ]),
      _map<_Items>('csv', (b) => b.csv, const [
        GetMapping.of(path: '/items', produces: 'text/csv'),
        CrossOrigin(origins: ['https://b.example']),
      ]),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Plain>(
    name: 'plain',
    types: const [_Plain],
    create: (_) => _Plain(),
    annotatedMethods: [
      _map<_Plain>('x', (b) => b.x, const [GetMapping('/g/x')]),
      _map<_Plain>('post', (b) => b.post, const [PostMapping('/g/post')]),
      _map<_Plain>('cors', (b) => b.cors, const [
        GetMapping('/api/cors'),
        CrossOrigin(origins: ['https://app.example']),
      ]),
      _map<_Plain>('open', (b) => b.cors, const [
        GetMapping('/open/cors'),
        CrossOrigin(origins: ['https://app.example']),
      ]),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Cors>(
    name: 'corsConfigurer',
    types: const [_Cors, WebMvcConfigurer],
    create: (_) => _Cors(),
    annotations: const [Configuration()],
  ),
  BeanDefinition<CorsConfigurationSource>(
    name: 'corsConfigurationSource',
    types: const [CorsConfigurationSource],
    create: (_) => UrlBasedCorsConfigurationSource()
      ..registerCorsConfiguration(
        '/api/**',
        CorsConfiguration(
          allowedOrigins: ['https://trusted.example'],
          allowedMethods: ['GET', 'POST'],
          allowCredentials: true,
        ),
      ),
  ),
]);
