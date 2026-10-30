// Regression tests of the eighth review before 0.5.0 that need no socket:
// a handler's own Vary next to the CORS processing's, CORS values outside
// visible US-ASCII, and pre-flights to a mapped path without CORS rules.
// The expected values are Spring 7.0.10's (Spring MVC on Tomcat 11, the
// same controllers, October 2026).
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
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
      ],
    ),
    properties: {'logging.level.root': 'off'},
  );

  Future<MockServerHttpResponse> get(String path, [String? origin]) async {
    final request = MockRequestBuilder(HttpMethod.get, path);
    if (origin != null) {
      request.headers['Origin'] = origin;
    }
    return (await app.mockMvc.perform(request)).response;
  }

  Future<MockServerHttpResponse> preFlight(
    String path,
    String method,
    String origin, {
    String? headers,
  }) async {
    final request = MockRequestBuilder(HttpMethod.options, path)
      ..headers['Origin'] = origin
      ..headers['Access-Control-Request-Method'] = method;
    if (headers != null) {
      request.headers['Access-Control-Request-Headers'] = headers;
    }
    return (await app.mockMvc.perform(request)).response;
  }

  group("a handler's own Vary joins the CORS names, as Spring's "
      'HttpEntityMethodProcessor merges them', () {
    test('a ResponseEntity with Vary: Accept-Language, with and without '
        'Origin', () async {
      for (final origin in [null, 'https://shop.example']) {
        final response = await get('/vary/entity', origin);
        expect(response.statusCode, 200);
        expect(response.headers.getAll('Vary'), [
          ..._corsVary,
          'Accept-Language',
        ], reason: '$origin');
      }
      expect(
        (await get(
          '/vary/entity',
          'https://shop.example',
        )).headers['Access-Control-Allow-Origin'],
        'https://shop.example',
      );
    });

    test('a name already there, in another case, is not repeated', () async {
      final response = await get('/vary/duplicate', 'https://shop.example');
      expect(response.headers.getAll('Vary'), [
        ..._corsVary,
        'Accept-Language',
      ]);
    });

    test('Vary: * of the entity is added, as in Spring', () async {
      final response = await get('/vary/star', 'https://shop.example');
      expect(response.headers.getAll('Vary'), [..._corsVary, '*']);
    });

    test("an ErrorResponse's Vary, the same way", () async {
      final response = await get('/vary/error', 'https://shop.example');
      expect(response.statusCode, 406);
      expect(response.headers.getAll('Vary'), [..._corsVary, 'Accept']);
    });

    test(
      'without CORS rules the Vary of the entity is written as it is',
      () async {
        final response = await get('/nocors/entity', 'https://shop.example');
        expect(response.headers.getAll('Vary'), ['Accept-Language, Accept']);
      },
    );

    test('nothing is added to a Vary: * already there', () async {
      final response = MockServerHttpResponse()..headers.set('Vary', '*');
      await ResponseWriter(mapper: ObjectMapper()).writeResult(
        ResponseEntity.status(200).header('Vary', ['Accept']).body('x'),
        MockServerHttpRequest(HttpMethod.get, '/x'),
        response,
      );
      expect(response.headers.getAll('Vary'), ['*']);
    });
  });

  group('CORS values outside visible US-ASCII are refused (403), never '
      'echoed', () {
    final star = CorsConfiguration(
      allowedOrigins: ['*'],
      allowedMethods: ['*'],
      allowedHeaders: ['*'],
    );
    final pattern = CorsConfiguration(
      allowedOriginPatterns: ['https://*.example.com'],
      allowedMethods: ['*'],
      allowedHeaders: ['*'],
    );

    (bool, MockServerHttpResponse) process(
      CorsConfiguration config, {
      required String origin,
      String? method,
      String? headers,
    }) {
      final request = MockServerHttpRequest(
        method == null ? HttpMethod.get : HttpMethod.options,
        '/api',
      )..headers.set('Origin', origin);
      if (method != null) {
        request.headers.set('Access-Control-Request-Method', method);
      }
      if (headers != null) {
        request.headers.set('Access-Control-Request-Headers', headers);
      }
      final response = MockServerHttpResponse();
      final allowed = processCors(
        config,
        request,
        response,
        preFlight: method != null,
      );
      return (allowed, response);
    }

    test('an Origin with a letter beyond ASCII, a space or a control '
        'character, even one a pattern or * matches', () {
      for (final config in [pattern, star]) {
        for (final origin in [
          'https://\u00e9.example.com',
          'https://a b.example.com',
          'https://a\u0001.example.com',
          'https://a\u007f.example.com',
        ]) {
          final (allowed, response) = process(config, origin: origin);
          expect(allowed, isFalse, reason: Uri.encodeComponent(origin));
          expect(response.headers['Access-Control-Allow-Origin'], isNull);
          expect(response.headers.getAll('Vary'), _corsVary);
        }
      }
      // The same host in punycode, as a browser sends it: allowed.
      final (allowed, response) = process(
        pattern,
        origin: 'https://xn--9ca.example.com',
      );
      expect(allowed, isTrue);
      expect(
        response.headers['Access-Control-Allow-Origin'],
        'https://xn--9ca.example.com',
      );
    });

    test('a pre-flight asking for such a method or header, with * '
        'allowing any', () {
      for (final (method, headers) in [
        ('G\u00e9T', 'x-a'),
        ('GET', 'x-\u00e9'),
        ('GET', 'x-a, x-\u00e9'),
        ('GET', 'x\ta'),
      ]) {
        final (allowed, response) = process(
          pattern,
          origin: 'https://a.example.com',
          method: method,
          headers: headers,
        );
        expect(allowed, isFalse, reason: '$method $headers');
        expect(response.headers['Access-Control-Allow-Origin'], isNull);
        expect(response.headers['Access-Control-Allow-Methods'], isNull);
        expect(response.headers['Access-Control-Allow-Headers'], isNull);
      }
      final (allowed, response) = process(
        pattern,
        origin: 'https://a.example.com',
        method: 'GET',
        headers: 'x-a, X-B',
      );
      expect(allowed, isTrue);
      expect(response.headers['Access-Control-Allow-Methods'], 'GET');
      expect(response.headers['Access-Control-Allow-Headers'], 'x-a, X-B');
    });

    test('through the router: 403 "Invalid CORS request"', () async {
      final refused = await get('/pattern', 'https://\u00e9.example.com');
      expect(refused.statusCode, 403);
      expect(refused.bodyText, 'Invalid CORS request');
      expect(refused.headers['Access-Control-Allow-Origin'], isNull);
      final echoed = await preFlight(
        '/star/x',
        'GET',
        'https://shop.example',
        headers: 'x-\u00e9',
      );
      expect(echoed.statusCode, 403);
      expect(echoed.headers['Access-Control-Allow-Headers'], isNull);
      final method = await preFlight(
        '/star/x',
        'G\u00e9T',
        'https://shop.example',
      );
      expect(method.statusCode, 403);
      expect(method.headers['Access-Control-Allow-Methods'], isNull);
      expect(
        (await get(
          '/pattern',
          'https://xn--9ca.example.com',
        )).headers['Access-Control-Allow-Origin'],
        'https://xn--9ca.example.com',
      );
    });
  });

  group('pre-flights: the twelve cases of Spring 7.0.10', () {
    // OPTIONS with Origin and Access-Control-Request-Method, then two
    // GETs; Spring's answers (status, Allow-Origin, number of Vary
    // headers), from the same mappings and global rules.
    const self = 'http://localhost';
    const cases = [
      ('/nocors', 'GET', self, 200, null, 0),
      ('/nocors', 'GET', 'https://other.example', 200, null, 0),
      ('/nocors', 'DELETE', 'https://other.example', 200, null, 0),
      (
        '/glob/x',
        'GET',
        'https://shop.example',
        200,
        'https://shop.example',
        3,
      ),
      ('/glob/x', 'DELETE', 'https://shop.example', 403, null, 3),
      (
        '/glob/x',
        'POST',
        'https://shop.example',
        200,
        'https://shop.example',
        3,
      ),
      ('/glob/x', 'GET', 'https://other.example', 403, null, 3),
      ('/glob/x', 'DELETE', self, 200, null, 3),
      ('/nope', 'GET', 'https://shop.example', 404, null, 0),
      ('/glob/nope', 'GET', 'https://shop.example', 404, null, 0),
    ];

    test('a mapped path without CORS rules: 200, with no CORS header and no '
        'Vary (the browser blocks the request it announced)', () async {
      for (final (path, method, origin, _, _, _) in cases.take(3)) {
        final response = await preFlight(path, method, origin);
        expect(response.statusCode, 200, reason: '$path $method $origin');
        expect(
          response.headers.names.where(
            (name) => name.toLowerCase().startsWith('access-control-'),
          ),
          isEmpty,
        );
        expect(response.headers.getAll('Vary'), isEmpty);
      }
    });

    test('all of them', () async {
      for (final (path, method, origin, status, allowOrigin, vary) in cases) {
        final response = await preFlight(path, method, origin);
        final reason = '$path $method $origin';
        expect(response.statusCode, status, reason: reason);
        expect(
          response.headers['Access-Control-Allow-Origin'],
          allowOrigin,
          reason: reason,
        );
        expect(
          response.headers.getAll('Vary'),
          hasLength(vary),
          reason: reason,
        );
      }
      final noRules = await get('/nocors', 'https://other.example');
      expect(noRules.statusCode, 200);
      expect(noRules.headers['Access-Control-Allow-Origin'], isNull);
      final refused = await get('/glob/x', 'https://other.example');
      expect(refused.statusCode, 403);
      expect(refused.headers['Access-Control-Allow-Origin'], isNull);
    });
  });
}

final class _VaryController {
  ResponseEntity<String> entity() =>
      ResponseEntity.status(200).header('Vary', ['Accept-Language']).body('x');
  ResponseEntity<String> duplicate() => ResponseEntity.status(
    200,
  ).header('Vary', ['origin, Accept-Language']).body('x');
  ResponseEntity<String> star() =>
      ResponseEntity.status(200).header('Vary', ['*']).body('x');
  String error() => throw ErrorResponseException(
    HttpStatus.notAcceptable,
    headers: HttpHeaders()..set('Vary', 'Accept'),
  );
}

final class _NoCors {
  String plain() => 'n';
  ResponseEntity<String> entity() => ResponseEntity.status(
    200,
  ).header('Vary', ['Accept-Language, Accept']).body('x');
}

final class _Pattern {
  String plain() => 'p';
}

final class _Glob {
  String glob() => 'g';
  String star() => 's';
}

final class _Cors with WebMvcConfigurer {
  @override
  void addCorsMappings(CorsRegistry registry) {
    registry
        .addMapping('/glob/**')
        .allowedOrigins(['https://shop.example'])
        .allowedMethods(['GET', 'POST']);
    registry
        .addMapping('/star/**')
        .allowedOrigins(['https://shop.example'])
        .allowedMethods(['*'])
        .allowedHeaders(['*']);
  }
}

BeanMethod<T> _get<T extends Object>(
  String name,
  String path,
  Function Function(T bean) method, {
  TypeInfo<Object?> returns = const ClassType<String>(),
}) => BeanMethod<T>(
  name,
  returnTypeInfo: returns,
  invoke: (bean, arguments) => Function.apply(method(bean), arguments),
  annotations: [GetMapping(path)],
);

const _entity = GenericType<ResponseEntity<String>>([ClassType<String>()]);

final _module = BeanModule('cors_eighth_review', [
  BeanDefinition<_VaryController>(
    name: 'varyController',
    types: const [_VaryController],
    create: (_) => _VaryController(),
    annotatedMethods: [
      _get<_VaryController>(
        'entity',
        '/vary/entity',
        (b) => b.entity,
        returns: _entity,
      ),
      _get<_VaryController>(
        'duplicate',
        '/vary/duplicate',
        (b) => b.duplicate,
        returns: _entity,
      ),
      _get<_VaryController>(
        'star',
        '/vary/star',
        (b) => b.star,
        returns: _entity,
      ),
      _get<_VaryController>('error', '/vary/error', (b) => b.error),
    ],
    annotations: const [
      RestController(),
      CrossOrigin(origins: ['https://shop.example']),
    ],
  ),
  BeanDefinition<_NoCors>(
    name: 'noCors',
    types: const [_NoCors],
    create: (_) => _NoCors(),
    annotatedMethods: [
      _get<_NoCors>('plain', '/nocors', (b) => b.plain),
      _get<_NoCors>(
        'entity',
        '/nocors/entity',
        (b) => b.entity,
        returns: _entity,
      ),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Pattern>(
    name: 'pattern',
    types: const [_Pattern],
    create: (_) => _Pattern(),
    annotatedMethods: [_get<_Pattern>('plain', '/pattern', (b) => b.plain)],
    annotations: const [
      RestController(),
      CrossOrigin(originPatterns: ['https://*.example.com']),
    ],
  ),
  BeanDefinition<_Glob>(
    name: 'glob',
    types: const [_Glob],
    create: (_) => _Glob(),
    annotatedMethods: [
      _get<_Glob>('glob', '/glob/x', (b) => b.glob),
      _get<_Glob>('star', '/star/x', (b) => b.star),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Cors>(
    name: 'cors',
    types: const [_Cors, WebMvcConfigurer],
    create: (_) => _Cors(),
    annotations: const [Configuration()],
  ),
]);
