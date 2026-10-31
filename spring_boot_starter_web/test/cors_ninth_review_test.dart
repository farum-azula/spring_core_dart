// Regression tests of the ninth review before 0.5.0 that need no socket:
// the method of an actual CORS request checked against the rules, the
// methods of @CrossOrigin defaulting to the handler's, a
// CorsConfigurationSource bean deciding alone where it has rules,
// allowPrivateNetwork, and the conditional requests of a ResponseEntity
// (ETag, Last-Modified). The expected values are Spring 7.0.10's (Spring
// MVC on Tomcat 11, the same controllers, October 2026).
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

const _corsVary = [
  'Origin',
  'Access-Control-Request-Method',
  'Access-Control-Request-Headers',
];
const _shop = 'https://shop.example';

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

  Future<MockServerHttpResponse> send(
    HttpMethod method,
    String path, [
    Map<String, String> headers = const {},
  ]) async {
    final request = MockRequestBuilder(method, path);
    request.headers.addAll(headers);
    return (await app.mockMvc.perform(request)).response;
  }

  Future<MockServerHttpResponse> preFlight(
    String path,
    String method, {
    String origin = _shop,
    Map<String, String> headers = const {},
  }) => send(HttpMethod.options, path, {
    'Origin': origin,
    'Access-Control-Request-Method': method,
    ...headers,
  });

  group('an actual CORS request is checked against the allowed methods, as '
      "Spring's DefaultCorsProcessor.handleInternal", () {
    // Global rules: /glob/** GET and POST from the shop, /star/** any.
    test('DELETE, PUT, HEAD and OPTIONS the rules do not list: 403 '
        '"Invalid CORS request", the handler not called', () async {
      for (final (method, path) in [
        (HttpMethod.delete, '/glob/del'),
        (HttpMethod.put, '/glob/put'),
        (HttpMethod.head, '/glob/x'),
        (HttpMethod.options, '/glob/x'),
      ]) {
        final response = await send(method, path, {'Origin': _shop});
        final reason = '${method.value} $path';
        expect(response.statusCode, 403, reason: reason);
        if (method != HttpMethod.head) {
          expect(response.bodyText, 'Invalid CORS request', reason: reason);
        }
        expect(response.headers['Access-Control-Allow-Origin'], isNull);
        expect(response.headers['Allow'], isNull, reason: reason);
        expect(response.headers.getAll('Vary'), _corsVary, reason: reason);
      }
      expect(_Glob.calls, isEmpty);
    });

    test('GET and POST are allowed; with `*` any method, OPTIONS too (with '
        'Allow)', () async {
      for (final (method, path) in [
        (HttpMethod.get, '/glob/x'),
        (HttpMethod.post, '/glob/post'),
        (HttpMethod.delete, '/star/del'),
        (HttpMethod.head, '/star/x'),
        (HttpMethod.options, '/star/x'),
      ]) {
        final response = await send(method, path, {'Origin': _shop});
        final reason = '${method.value} $path';
        expect(response.statusCode, 200, reason: reason);
        expect(
          response.headers['Access-Control-Allow-Origin'],
          _shop,
          reason: reason,
        );
        expect(response.headers.getAll('Vary'), _corsVary, reason: reason);
      }
      expect(
        (await send(HttpMethod.options, '/star/x', {
          'Origin': _shop,
        })).headers['Allow'],
        'GET, HEAD, OPTIONS',
      );
    });

    test('not a CORS request (no Origin, or the own origin): handled, with '
        'Vary; an OPTIONS gets Allow and Vary', () async {
      for (final headers in [
        const <String, String>{},
        {'Origin': 'http://localhost'},
      ]) {
        final delete = await send(HttpMethod.delete, '/glob/del', headers);
        expect(delete.statusCode, 200, reason: '$headers');
        expect(delete.bodyText, 'gd');
        expect(delete.headers.getAll('Vary'), _corsVary);
        final options = await send(HttpMethod.options, '/glob/x', headers);
        expect(options.statusCode, 200);
        expect(options.headers['Allow'], 'GET, HEAD, OPTIONS');
        expect(options.headers.getAll('Vary'), _corsVary);
      }
      // A path without rules: OPTIONS as before, no Vary.
      final plain = await send(HttpMethod.options, '/co/plain', {
        'Origin': _shop,
      });
      expect(plain.statusCode, 200);
      expect(plain.headers['Allow'], 'GET, HEAD, OPTIONS');
      expect(plain.headers.getAll('Vary'), isEmpty);
    });

    test('processCors itself: the method of a request that is not a '
        'pre-flight', () {
      final config = CorsConfiguration(
        allowedOrigins: [_shop],
        allowedMethods: ['GET'],
      );
      bool allowed(HttpMethod method) => processCors(
        config,
        MockServerHttpRequest(method, '/x')..headers.set('Origin', _shop),
        MockServerHttpResponse(),
        preFlight: false,
      );
      expect(allowed(HttpMethod.get), isTrue);
      expect(allowed(HttpMethod.delete), isFalse);
      expect(allowed(HttpMethod.head), isFalse);
      // Empty allowedMethods: GET and HEAD.
      config.allowedMethods.clear();
      expect(allowed(HttpMethod.head), isTrue);
      expect(allowed(HttpMethod.post), isFalse);
    });
  });

  group('@CrossOrigin without methods allows the method the handler is '
      'mapped to, as Spring', () {
    test('a DELETE and a PUT handler: their pre-flights and requests are '
        'allowed, Allow-Methods lists that method', () async {
      for (final (path, method) in [
        ('/co/del', HttpMethod.delete),
        ('/co/put', HttpMethod.put),
      ]) {
        final pre = await preFlight(path, method.value);
        expect(pre.statusCode, 200, reason: path);
        expect(pre.headers['Access-Control-Allow-Methods'], method.value);
        expect(pre.headers['Access-Control-Max-Age'], '1800');
        final actual = await send(method, path, {'Origin': _shop});
        expect(actual.statusCode, 200, reason: path);
        expect(actual.headers['Access-Control-Allow-Origin'], _shop);
      }
    });

    test('a GET handler: GET only, so a HEAD or its pre-flight is a '
        '403', () async {
      final pre = await preFlight('/co/plain', 'GET');
      expect(pre.headers['Access-Control-Allow-Methods'], 'GET');
      expect((await preFlight('/co/plain', 'HEAD')).statusCode, 403);
      expect(
        (await send(HttpMethod.head, '/co/plain', {
          'Origin': _shop,
        })).statusCode,
        403,
      );
      expect(
        (await send(HttpMethod.get, '/co/plain', {'Origin': _shop})).statusCode,
        200,
      );
    });

    test('methods: [POST] on a GET handler: a cross-origin GET is a '
        '403', () async {
      expect(
        (await send(HttpMethod.get, '/co/post-only', {
          'Origin': _shop,
        })).statusCode,
        403,
      );
      expect((await preFlight('/co/post-only', 'GET')).statusCode, 403);
      expect((await send(HttpMethod.get, '/co/post-only')).statusCode, 200);
    });

    test('CorsConfiguration.fromAnnotation takes the mapped methods', () {
      expect(
        CorsConfiguration.fromAnnotation(
          const CrossOrigin(),
          mappedMethods: ['DELETE'],
        ).allowedMethods,
        ['DELETE'],
      );
      expect(
        CorsConfiguration.fromAnnotation(
          const CrossOrigin(methods: ['PUT']),
          mappedMethods: ['DELETE'],
        ).allowedMethods,
        ['PUT'],
      );
      expect(
        CorsConfiguration.fromAnnotation(const CrossOrigin()).allowedMethods,
        ['GET', 'HEAD', 'POST'],
      );
    });
  });

  group('a CorsConfigurationSource bean decides alone where it has rules, as '
      "Spring Security's CorsFilter applies it before Spring MVC", () {
    // The bean: /api/** from https://trusted.example, GET and POST, with
    // credentials. /api/cors and /open/cors: @CrossOrigin(app.example).
    test("@CrossOrigin does not widen the bean's rules: its origin is "
        'refused, and so are its default headers and max age', () async {
      final actual = await send(HttpMethod.get, '/api/cors', {
        'Origin': 'https://app.example',
      });
      expect(actual.statusCode, 403);
      expect(actual.headers['Access-Control-Allow-Origin'], isNull);
      expect(
        (await preFlight(
          '/api/cors',
          'GET',
          origin: 'https://app.example',
        )).statusCode,
        403,
      );
      final headers = await preFlight(
        '/api/cors',
        'GET',
        origin: 'https://trusted.example',
        headers: {'Access-Control-Request-Headers': 'authorization'},
      );
      expect(headers.statusCode, 403);
    });

    test("the bean's origin, with the bean's headers only", () async {
      final actual = await send(HttpMethod.get, '/api/cors', {
        'Origin': 'https://trusted.example',
      });
      expect(actual.statusCode, 200);
      expect(
        actual.headers['Access-Control-Allow-Origin'],
        'https://trusted.example',
      );
      expect(actual.headers['Access-Control-Allow-Credentials'], 'true');
      final pre = await preFlight(
        '/api/cors',
        'GET',
        origin: 'https://trusted.example',
      );
      expect(pre.statusCode, 200);
      expect(pre.headers['Access-Control-Allow-Methods'], 'GET,POST');
      expect(pre.headers['Access-Control-Max-Age'], isNull);
    });

    test('where the bean has no rules, @CrossOrigin applies', () async {
      final actual = await send(HttpMethod.get, '/open/cors', {
        'Origin': 'https://app.example',
      });
      expect(actual.statusCode, 200);
      expect(
        actual.headers['Access-Control-Allow-Origin'],
        'https://app.example',
      );
      expect(
        (await preFlight(
          '/open/cors',
          'GET',
          origin: 'https://app.example',
        )).statusCode,
        200,
      );
    });
  });

  group('allowPrivateNetwork, as Spring 7.0.10', () {
    const pna = {'Access-Control-Request-Private-Network': 'true'};

    test('a pre-flight asking for the private network gets '
        'Access-Control-Allow-Private-Network: true where it is on', () async {
      for (final path in ['/pn/x', '/pna/x']) {
        for (final value in ['true', 'TRUE']) {
          final response = await preFlight(
            path,
            'GET',
            headers: {'Access-Control-Request-Private-Network': value},
          );
          expect(response.statusCode, 200, reason: path);
          expect(
            response.headers['Access-Control-Allow-Private-Network'],
            'true',
            reason: '$path $value',
          );
        }
        for (final headers in [
          const <String, String>{},
          {'Access-Control-Request-Private-Network': 'false'},
        ]) {
          final response = await preFlight(path, 'GET', headers: headers);
          expect(response.statusCode, 200);
          expect(
            response.headers['Access-Control-Allow-Private-Network'],
            isNull,
          );
        }
      }
      // An actual request with the header gets it too (Spring).
      final actual = await send(HttpMethod.get, '/pn/x', {
        'Origin': _shop,
        ...pna,
      });
      expect(actual.headers['Access-Control-Allow-Private-Network'], 'true');
      // A refused origin gets nothing.
      final evil = await preFlight(
        '/pn/x',
        'GET',
        origin: 'https://evil.example',
        headers: pna,
      );
      expect(evil.statusCode, 403);
      expect(evil.headers['Access-Control-Allow-Private-Network'], isNull);
    });

    test("the handler's allowPrivateNetwork: false wins over the global "
        'true; a pattern with credentials is allowed', () async {
      final off = await preFlight('/pnoff/x', 'GET', headers: pna);
      expect(off.statusCode, 200);
      expect(off.headers['Access-Control-Allow-Private-Network'], isNull);
      expect(off.headers['Access-Control-Allow-Methods'], 'GET');
      final pattern = await preFlight(
        '/pnb/x',
        'GET',
        origin: 'https://a.example',
        headers: pna,
      );
      expect(pattern.statusCode, 200);
      expect(pattern.headers['Access-Control-Allow-Credentials'], 'true');
      expect(pattern.headers['Access-Control-Allow-Private-Network'], 'true');
    });

    test('with "*" in the global origins every request to the path fails '
        '(500), as Spring validates the configuration', () async {
      for (final headers in [
        const <String, String>{},
        {'Origin': _shop},
      ]) {
        expect(
          (await send(HttpMethod.get, '/pnstar/x', headers)).statusCode,
          500,
          reason: '$headers',
        );
      }
      expect(
        (await preFlight('/pnstar/x', 'GET', headers: pna)).statusCode,
        500,
      );
    });

    test('CorsConfiguration: combine, checkOrigin and the validations', () {
      final global = CorsConfiguration(
        allowedOrigins: [_shop],
        allowPrivateNetwork: true,
      );
      expect(global.combine(CorsConfiguration()).allowPrivateNetwork, isTrue);
      expect(
        global
            .combine(CorsConfiguration(allowPrivateNetwork: false))
            .allowPrivateNetwork,
        isFalse,
      );
      expect(
        CorsConfiguration.fromAnnotation(
          const CrossOrigin(origins: [_shop], allowPrivateNetwork: true),
        ).allowPrivateNetwork,
        isTrue,
      );
      final star = CorsConfiguration(
        allowedOrigins: ['https://a.example, *'],
        allowPrivateNetwork: true,
      );
      expect(() => star.checkOrigin(_shop), throwsStateError);
      expect(star.validateAllowPrivateNetwork, throwsStateError);
      expect(star.validateAllowCredentials, returnsNormally);
      star.allowPrivateNetwork = false;
      expect(star.checkOrigin(_shop), '*');
      final registry = CorsRegistry();
      registry.addMapping('/x/**').allowPrivateNetwork(true);
      final config = registry.toSource().getCorsConfiguration(
        MockServerHttpRequest(HttpMethod.get, '/x/y'),
      );
      expect(config!.allowPrivateNetwork, isTrue);
    });

    test('@CrossOrigin(allowPrivateNetwork: true) without origins stops the '
        'startup, as Spring validates it', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<_Pn>(
            name: 'open',
            create: (_) => _Pn(),
            annotations: const [
              RestController(),
              CrossOrigin(allowPrivateNetwork: true),
            ],
            annotatedMethods: [
              BeanMethod<_Pn>(
                'get',
                invoke: (bean, arguments) => 'open',
                annotations: const [GetMapping('/open')],
              ),
            ],
          ),
        );
      final mapping = RequestMappingHandlerMapping(
        beanFactory: factory,
        writer: ResponseWriter(mapper: ObjectMapper()),
        environment: StandardEnvironment(),
      );
      expect(
        mapping.initialize,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('@CrossOrigin(allowPrivateNetwork: true) needs origins'),
          ),
        ),
      );
    });

    test('Access-Control-Expose-Headers on pre-flights too, as '
        'Spring', () async {
      final pre = await preFlight('/pnexp/x', 'GET');
      expect(pre.headers['Access-Control-Expose-Headers'], 'X-Total');
      final actual = await send(HttpMethod.get, '/pnexp/x', {'Origin': _shop});
      expect(actual.headers['Access-Control-Expose-Headers'], 'X-Total');
    });
  });

  group("a ResponseEntity's ETag and Last-Modified answer conditional "
      "requests, as Spring's HttpEntityMethodProcessor", () {
    const lastModified = 'Thu, 01 Jan 2026 00:00:00 GMT';

    // (path, method, request headers, status, ETag, Last-Modified), each
    // as Spring 7.0.10 answered.
    const cases =
        <(String, HttpMethod, Map<String, String>, int, String?, String?)>[
          ('/c/etag', HttpMethod.get, {}, 200, '"v1"', null),
          (
            '/c/etag',
            HttpMethod.get,
            {'If-None-Match': '"v1"'},
            304,
            '"v1"',
            null,
          ),
          (
            '/c/etag',
            HttpMethod.head,
            {'If-None-Match': '"v1"'},
            304,
            '"v1"',
            null,
          ),
          (
            '/c/etag',
            HttpMethod.get,
            {'If-None-Match': 'W/"v1"'},
            304,
            '"v1"',
            null,
          ),
          (
            '/c/etag',
            HttpMethod.get,
            {'If-None-Match': '"a", "v1"'},
            304,
            '"v1"',
            null,
          ),
          (
            '/c/etag',
            HttpMethod.get,
            {'If-None-Match': '*'},
            200,
            '"v1"',
            null,
          ),
          (
            '/c/etag',
            HttpMethod.get,
            {'If-None-Match': 'v1'},
            200,
            '"v1"',
            null,
          ),
          (
            '/c/etag',
            HttpMethod.get,
            {'If-None-Match': '"v2"'},
            200,
            '"v1"',
            null,
          ),
          ('/c/etag', HttpMethod.get, {'If-None-Match': ''}, 200, '"v1"', null),
          ('/c/etag', HttpMethod.get, {'If-Match': '"v2"'}, 200, '"v1"', null),
          (
            '/c/weak',
            HttpMethod.get,
            {'If-None-Match': '"v1"'},
            304,
            'W/"v1"',
            null,
          ),
          ('/c/raw', HttpMethod.get, {}, 200, '"v1"', null),
          (
            '/c/raw',
            HttpMethod.get,
            {'If-None-Match': '"v1"'},
            304,
            '"v1"',
            null,
          ),
          (
            '/c/created',
            HttpMethod.get,
            {'If-None-Match': '"v1"'},
            201,
            '"v1"',
            null,
          ),
          ('/c/lm', HttpMethod.get, {}, 200, null, lastModified),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': lastModified},
            304,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.head,
            {'If-Modified-Since': lastModified},
            304,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': 'Fri, 02 Jan 2026 00:00:00 GMT'},
            304,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': 'Wed, 31 Dec 2025 00:00:00 GMT'},
            200,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': 'Thursday, 01-Jan-26 00:00:00 GMT'},
            304,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': 'Thu Jan  1 00:00:00 2026'},
            304,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': '$lastModified; length=13774'},
            304,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Modified-Since': 'yesterday'},
            200,
            null,
            lastModified,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Unmodified-Since': 'Wed, 31 Dec 2025 00:00:00 GMT'},
            412,
            null,
            null,
          ),
          (
            '/c/lm',
            HttpMethod.head,
            {'If-Unmodified-Since': 'Wed, 31 Dec 2025 00:00:00 GMT'},
            412,
            null,
            null,
          ),
          (
            '/c/lm',
            HttpMethod.get,
            {'If-Unmodified-Since': lastModified},
            200,
            null,
            lastModified,
          ),
          (
            '/c/both',
            HttpMethod.get,
            {'If-None-Match': '"v1"'},
            304,
            '"v1"',
            lastModified,
          ),
          (
            '/c/both',
            HttpMethod.get,
            {
              'If-None-Match': '"v2"',
              'If-Modified-Since': 'Fri, 02 Jan 2026 00:00:00 GMT',
            },
            200,
            '"v1"',
            lastModified,
          ),
          (
            '/c/both',
            HttpMethod.get,
            {'If-Modified-Since': 'Fri, 02 Jan 2026 00:00:00 GMT'},
            304,
            '"v1"',
            lastModified,
          ),
          (
            '/c/both',
            HttpMethod.get,
            {
              'If-Unmodified-Since': 'Fri, 02 Jan 2026 00:00:00 GMT',
              'If-None-Match': '"v1"',
            },
            200,
            '"v1"',
            lastModified,
          ),
          (
            '/c/both',
            HttpMethod.get,
            {'If-Unmodified-Since': 'Wed, 31 Dec 2025 00:00:00 GMT'},
            412,
            null,
            null,
          ),
          // Not for other methods (Spring checks GET and HEAD only).
          (
            '/c/put',
            HttpMethod.put,
            {'If-Match': '"v2"'},
            200,
            '"v1"',
            lastModified,
          ),
          (
            '/c/put',
            HttpMethod.put,
            {'If-None-Match': '*'},
            200,
            '"v1"',
            lastModified,
          ),
          (
            '/c/put',
            HttpMethod.put,
            {'If-Unmodified-Since': 'Wed, 31 Dec 2025 00:00:00 GMT'},
            200,
            '"v1"',
            lastModified,
          ),
        ];

    test('all of them', () async {
      for (final (path, method, headers, status, eTag, modified) in cases) {
        final response = await send(method, path, headers);
        final reason = '${method.value} $path $headers';
        expect(response.statusCode, status, reason: reason);
        expect(response.headers['ETag'], eTag, reason: reason);
        expect(response.headers['Last-Modified'], modified, reason: reason);
        final bodyless = status == 304 || status == 412;
        expect(
          response.bodyText,
          bodyless || method == HttpMethod.head ? isEmpty : 'x',
          reason: reason,
        );
      }
    });

    test('a 304 keeps the other headers: Cache-Control, Vary, the CORS '
        'ones', () async {
      final response = await send(HttpMethod.get, '/c/both', {
        'If-None-Match': '"v1"',
        'Origin': _shop,
      });
      expect(response.statusCode, 304);
      expect(response.headers['Cache-Control'], 'max-age=60');
      expect(response.headers.getAll('Vary'), [
        ..._corsVary,
        'Accept-Language',
      ]);
      expect(response.headers['Access-Control-Allow-Origin'], _shop);
      final failed = await send(HttpMethod.get, '/c/both', {
        'If-Unmodified-Since': 'Wed, 31 Dec 2025 00:00:00 GMT',
      });
      expect(failed.statusCode, 412);
      expect(failed.headers['Cache-Control'], 'max-age=60');
    });
  });
}

final class _Glob {
  static final calls = <String>[];

  String x() => 'g';
  String post() => 'gp';
  String del() {
    calls.add('del');
    return 'gd';
  }

  String put() {
    calls.add('put');
    return 'gput';
  }

  String starX() => 's';
  String starDel() => 'sdel';
}

final class _Co {
  String plain() => 'p';
  String del() => 'deleted';
  String put() => 'put';
  String postOnly() => 'po';
}

final class _Api {
  String cors() => 'cors';
  String open() => 'open';
}

final class _Pn {
  String pn() => 'pn';
}

final _lastModified = DateTime.utc(2026);

final class _Cond {
  ResponseEntity<String> etag() =>
      ResponseEntity.status(200).eTag('"v1"').body('x');
  ResponseEntity<String> lm() =>
      ResponseEntity.status(200).lastModified(_lastModified).body('x');
  ResponseEntity<String> both() =>
      ResponseEntity.status(200)
          .eTag('"v1"')
          .lastModified(_lastModified)
          .header('Cache-Control', ['max-age=60'])
          .header('Vary', ['Accept-Language'])
          .body('x');
  ResponseEntity<String> weak() =>
      ResponseEntity.status(200).eTag('W/"v1"').body('x');
  ResponseEntity<String> raw() =>
      ResponseEntity.status(200).header('ETag', ['v1']).body('x');
  ResponseEntity<String> created() =>
      ResponseEntity.status(201).eTag('"v1"').body('x');
  ResponseEntity<String> put() =>
      ResponseEntity.status(200)
          .eTag('"v1"')
          .lastModified(_lastModified)
          .body('x');
}

final class _Cors with WebMvcConfigurer {
  @override
  void addCorsMappings(CorsRegistry registry) {
    registry.addMapping('/glob/**').allowedOrigins([_shop]).allowedMethods([
      'GET',
      'POST',
    ]);
    registry
        .addMapping('/star/**')
        .allowedOrigins([_shop])
        .allowedMethods(['*'])
        .allowedHeaders(['*']);
    registry
        .addMapping('/pn/**')
        .allowedOrigins([_shop])
        .allowPrivateNetwork(true);
    registry
        .addMapping('/pnoff/**')
        .allowedOrigins([_shop])
        .allowPrivateNetwork(true);
    registry
        .addMapping('/pnstar/**')
        .allowedOrigins(['*'])
        .allowPrivateNetwork(true);
  }
}

final class _Config {
  CorsConfigurationSource cors() =>
      UrlBasedCorsConfigurationSource()..registerCorsConfiguration(
        '/api/**',
        CorsConfiguration(
          allowedOrigins: ['https://trusted.example'],
          allowedMethods: ['GET', 'POST'],
          allowCredentials: true,
        ),
      );
}

BeanMethod<T> _map<T extends Object>(
  String name,
  Function Function(T bean) method,
  List<Object> annotations, {
  TypeInfo<Object?> returns = const ClassType<String>(),
}) => BeanMethod<T>(
  name,
  returnTypeInfo: returns,
  invoke: (bean, arguments) => Function.apply(method(bean), arguments),
  annotations: annotations,
);

const _entity = GenericType<ResponseEntity<String>>([ClassType<String>()]);

final _module = BeanModule('cors_ninth_review', [
  BeanDefinition<_Glob>(
    name: 'glob',
    types: const [_Glob],
    create: (_) => _Glob(),
    annotatedMethods: [
      _map<_Glob>('x', (b) => b.x, const [GetMapping('/glob/x')]),
      _map<_Glob>('post', (b) => b.post, const [PostMapping('/glob/post')]),
      _map<_Glob>('del', (b) => b.del, const [DeleteMapping('/glob/del')]),
      _map<_Glob>('put', (b) => b.put, const [PutMapping('/glob/put')]),
      _map<_Glob>('starX', (b) => b.starX, const [GetMapping('/star/x')]),
      _map<_Glob>('starDel', (b) => b.starDel, const [
        DeleteMapping('/star/del'),
      ]),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Co>(
    name: 'co',
    types: const [_Co],
    create: (_) => _Co(),
    annotatedMethods: [
      _map<_Co>('plain', (b) => b.plain, const [GetMapping('/co/plain')]),
      _map<_Co>('del', (b) => b.del, const [DeleteMapping('/co/del')]),
      _map<_Co>('put', (b) => b.put, const [PutMapping('/co/put')]),
      _map<_Co>('postOnly', (b) => b.postOnly, const [
        GetMapping('/co/post-only'),
        CrossOrigin(methods: ['POST']),
      ]),
    ],
    annotations: const [
      RestController(),
      CrossOrigin(origins: [_shop]),
    ],
  ),
  BeanDefinition<_Api>(
    name: 'api',
    types: const [_Api],
    create: (_) => _Api(),
    annotatedMethods: [
      _map<_Api>('cors', (b) => b.cors, const [
        GetMapping('/api/cors'),
        CrossOrigin(origins: ['https://app.example']),
      ]),
      _map<_Api>('open', (b) => b.open, const [
        GetMapping('/open/cors'),
        CrossOrigin(origins: ['https://app.example']),
      ]),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Pn>(
    name: 'pn',
    types: const [_Pn],
    create: (_) => _Pn(),
    annotatedMethods: [
      _map<_Pn>('pn', (b) => b.pn, const [GetMapping('/pn/x')]),
      _map<_Pn>('off', (b) => b.pn, const [
        GetMapping('/pnoff/x'),
        CrossOrigin(allowPrivateNetwork: false),
      ]),
      _map<_Pn>('a', (b) => b.pn, const [
        GetMapping('/pna/x'),
        CrossOrigin(origins: [_shop], allowPrivateNetwork: true),
      ]),
      _map<_Pn>('b', (b) => b.pn, const [
        GetMapping('/pnb/x'),
        CrossOrigin(
          originPatterns: ['https://*.example'],
          allowPrivateNetwork: true,
          allowCredentials: true,
        ),
      ]),
      _map<_Pn>('star', (b) => b.pn, const [GetMapping('/pnstar/x')]),
      _map<_Pn>('exp', (b) => b.pn, const [
        GetMapping('/pnexp/x'),
        CrossOrigin(origins: [_shop], exposedHeaders: ['X-Total']),
      ]),
    ],
    annotations: const [RestController()],
  ),
  BeanDefinition<_Cond>(
    name: 'cond',
    types: const [_Cond],
    create: (_) => _Cond(),
    annotatedMethods: [
      _map<_Cond>('etag', (b) => b.etag, const [
        GetMapping('/c/etag'),
      ], returns: _entity),
      _map<_Cond>('lm', (b) => b.lm, const [
        GetMapping('/c/lm'),
      ], returns: _entity),
      _map<_Cond>('both', (b) => b.both, const [
        GetMapping('/c/both'),
      ], returns: _entity),
      _map<_Cond>('weak', (b) => b.weak, const [
        GetMapping('/c/weak'),
      ], returns: _entity),
      _map<_Cond>('raw', (b) => b.raw, const [
        GetMapping('/c/raw'),
      ], returns: _entity),
      _map<_Cond>('created', (b) => b.created, const [
        GetMapping('/c/created'),
      ], returns: _entity),
      _map<_Cond>('put', (b) => b.put, const [
        PutMapping('/c/put'),
      ], returns: _entity),
    ],
    annotations: const [
      RestController(),
      CrossOrigin(origins: [_shop]),
    ],
  ),
  BeanDefinition<_Cors>(
    name: 'corsConfigurer',
    types: const [_Cors, WebMvcConfigurer],
    create: (_) => _Cors(),
    annotations: const [Configuration()],
  ),
  BeanDefinition<_Config>(
    name: 'config',
    types: const [_Config],
    create: (_) => _Config(),
    annotations: const [Configuration()],
  ),
  BeanDefinition<CorsConfigurationSource>(
    name: 'corsConfigurationSource',
    types: const [CorsConfigurationSource],
    create: (r) => r.dependency<_Config>().cors(),
  ),
]);
