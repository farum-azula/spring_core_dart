// Regression tests of the review before 0.5.0 that need no socket: CORS
// defaults, pre-flights, the choice of advice beans, ResponseEntity streams.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  final app = springBootTest(
    testApplication,
    properties: {'logging.level.root': 'off'},
  );

  group('CORS: annotation defaults never override explicit values', () {
    test('combine keeps explicit origins over the defaults of an '
        'annotation', () {
      final global = CorsConfiguration(
        allowedOrigins: ['https://shop.example'],
        allowedMethods: ['GET', 'POST'],
        allowCredentials: true,
      );
      final handler = CorsConfiguration.fromAnnotation(
        const CrossOrigin(methods: ['PUT']),
      );
      final combined = global.combine(handler);
      expect(combined.allowedOrigins, ['https://shop.example']);
      expect(combined.allowedMethods, ['GET', 'POST', 'PUT']);
      expect(combined.allowedHeaders, ['*']);
      // No StateError: the origins are not "*".
      expect(
        combined.checkOrigin('https://shop.example'),
        'https://shop.example',
      );
      expect(combined.checkOrigin('https://evil.example'), isNull);
    });

    test('the defaults give way on both sides, and next to patterns', () {
      final defaults = CorsConfiguration().applyPermitDefaultValues();
      final explicit = CorsConfiguration(allowedOrigins: ['https://a.example']);
      expect(defaults.combine(explicit).allowedOrigins, ['https://a.example']);
      expect(explicit.combine(defaults).allowedOrigins, ['https://a.example']);
      // Both default: still the default, and still giving way afterwards.
      final both = defaults.combine(
        CorsConfiguration().applyPermitDefaultValues(),
      );
      expect(both.allowedOrigins, ['*']);
      expect(both.combine(explicit).allowedOrigins, ['https://a.example']);
      // Default origins next to patterns: the patterns alone.
      final patterns = CorsConfiguration(
        allowedOriginPatterns: ['https://*.shop.example'],
        allowCredentials: true,
      );
      final withPatterns = patterns.combine(defaults);
      expect(withPatterns.allowedOrigins, isEmpty);
      expect(
        withPatterns.checkOrigin('https://eu.shop.example'),
        'https://eu.shop.example',
      );
      // Explicit "*" still merges as "*".
      expect(
        CorsConfiguration(
          allowedOrigins: ['*'],
        ).combine(explicit).allowedOrigins,
        ['*'],
      );
    });

    test('a handler @CrossOrigin() keeps the global origins', () async {
      final mvc = app.mockMvc;
      await mvc
          .perform(
            MockRequestBuilder(HttpMethod.options, '/api/review/cors')
              ..headers['Origin'] = 'https://evil.example'
              ..headers['Access-Control-Request-Method'] = 'PUT',
          )
          .andExpect(status: 403);
      await mvc
          .perform(
            MockRequestBuilder(HttpMethod.options, '/api/review/cors')
              ..headers['Origin'] = 'https://shop.example'
              ..headers['Access-Control-Request-Method'] = 'PUT',
          )
          .andExpect(
            status: 200,
            headers: {
              'Access-Control-Allow-Origin': 'https://shop.example',
              'Access-Control-Allow-Credentials': 'true',
            },
          );
      // With the global allowCredentials: no 500.
      await mvc
          .perform(
            MockRequestBuilder(HttpMethod.put, '/api/review/cors')
              ..headers['Origin'] = 'https://shop.example',
          )
          .andExpect(status: 200, body: 'ok');
    });

    test('every answer of a handler with CORS rules gets Vary, a CORS '
        "request or not, as Spring's DefaultCorsProcessor; one without rules "
        'gets none', () async {
      const vary = [
        'Origin',
        'Access-Control-Request-Method',
        'Access-Control-Request-Headers',
      ];
      // The global rules of /api/** and the handler's @CrossOrigin.
      for (final origin in [null, 'http://localhost', 'https://shop.example']) {
        final request = MockRequestBuilder(HttpMethod.put, '/api/review/cors');
        if (origin != null) {
          request.headers['Origin'] = origin;
        }
        final result = await app.mockMvc.perform(request);
        expect(result.response.statusCode, 200, reason: '$origin');
        expect(result.response.headers.getAll('Vary'), vary, reason: '$origin');
      }
      // Refused: Vary too.
      final refused = await app.mockMvc.perform(
        MockRequestBuilder(HttpMethod.put, '/api/review/cors')
          ..headers['Origin'] = 'https://evil.example',
      );
      expect(refused.response.statusCode, 403);
      expect(refused.response.headers.getAll('Vary'), vary);
      // No rules for /misc/**.
      for (final origin in [null, 'https://shop.example']) {
        final request = MockRequestBuilder(HttpMethod.get, '/misc/text');
        if (origin != null) {
          request.headers['Origin'] = origin;
        }
        final result = await app.mockMvc.perform(request);
        expect(result.response.statusCode, 200);
        expect(result.response.headers.getAll('Vary'), isEmpty);
      }
    });

    test('processCors adds each Vary name once, with the values already '
        'there in any case or list, and none to Vary: *', () {
      final config = CorsConfiguration(allowedOrigins: ['https://a.example']);
      final request = MockServerHttpRequest(HttpMethod.get, '/x');
      final response = MockServerHttpResponse()
        ..headers.add('Vary', 'accept-encoding, ORIGIN');
      expect(processCors(config, request, response, preFlight: false), isTrue);
      expect(processCors(config, request, response, preFlight: false), isTrue);
      expect(response.headers.getAll('Vary'), [
        'accept-encoding, ORIGIN',
        'Access-Control-Request-Method',
        'Access-Control-Request-Headers',
      ]);
      final any = MockServerHttpResponse()..headers.add('Vary', '*');
      processCors(config, request, any, preFlight: false);
      expect(any.headers.getAll('Vary'), ['*']);
    });

    test('@CrossOrigin(allowCredentials: true) without origins stops the '
        'startup, as Spring validates it', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<_Open>(
            name: 'open',
            create: (_) => _Open(),
            annotations: const [
              RestController(),
              CrossOrigin(allowCredentials: true),
            ],
            annotatedMethods: [
              BeanMethod<_Open>(
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
            contains('allowCredentials: true) needs origins'),
          ),
        ),
      );
    });

    test('a pre-flight for a method no handler maps is a 403, not a '
        '405', () async {
      await app.mockMvc
          .perform(
            MockRequestBuilder(HttpMethod.options, '/api/books/1111')
              ..headers['Origin'] = 'https://shop.example'
              ..headers['Access-Control-Request-Method'] = 'PATCH',
          )
          .andExpect(status: 403);
      // Not a pre-flight: still the 405.
      await app.mockMvc
          .perform(MockRequestBuilder(HttpMethod.patch, '/api/books/1111'))
          .andExpect(status: 405);
    });
  });

  group("CORS origins: Spring's CorsConfiguration rules (the sixth "
      'review)', () {
    // Each expected value is what Spring 7.0.10's checkOrigin returned.
    test('port lists, [*] without a port, trailing slashes, commas', () {
      String? check(
        String origin, {
        List<String> origins = const [],
        List<String> patterns = const [],
      }) => CorsConfiguration(
        allowedOrigins: origins,
        allowedOriginPatterns: patterns,
      ).checkOrigin(origin);

      expect(
        check(
          'http://localhost:8080',
          patterns: ['http://localhost:[8080,8081]'],
        ),
        'http://localhost:8080',
      );
      expect(
        check(
          'http://localhost:8082',
          patterns: ['http://localhost:[8080,8081]'],
        ),
        isNull,
      );
      expect(
        check('http://localhost', patterns: ['http://localhost:[*]']),
        'http://localhost',
      );
      expect(
        check('https://shop.example', origins: ['https://shop.example/']),
        'https://shop.example',
      );
      expect(
        check('https://shop.example/', origins: ['https://shop.example']),
        'https://shop.example/',
      );
      expect(
        check(
          'https://b.example',
          origins: ['https://a.example, https://b.example'],
        ),
        'https://b.example',
      );
      // Patterns are compared with case, as Spring.
      expect(
        check('https://a.example.com', patterns: ['https://*.Example.com']),
        isNull,
      );
      for (final origin in [
        'https://a.example.com.evil',
        'http://a.example.com',
      ]) {
        expect(
          check(origin, patterns: ['https://*.example.com']),
          isNull,
          reason: origin,
        );
      }
      // A * matches any text, as Spring's (the eighth review): also what
      // no browser sends as an origin.
      for (final origin in [
        'https://evil.com/.example.com',
        'https://evil.com@a.example.com',
      ]) {
        expect(
          check(origin, patterns: ['https://*.example.com']),
          origin,
          reason: origin,
        );
      }
    });

    test('lists changed after a check are read again', () {
      final config = CorsConfiguration(allowedOrigins: ['https://a.example']);
      expect(config.checkOrigin('https://b.example'), isNull);
      config.allowedOrigins.add('https://b.example/');
      expect(config.checkOrigin('https://b.example'), 'https://b.example');
      config.allowedOriginPatterns.add('http://localhost:[*]');
      expect(config.checkOrigin('http://localhost'), 'http://localhost');
    });

    test('a pre-flight from a port of the list, or with a trailing slash, '
        'is allowed and echoed', () {
      final config = CorsConfiguration(
        allowedOrigins: ['https://shop.example/'],
        allowedOriginPatterns: ['http://localhost:[3000,3001]'],
        allowCredentials: true,
      )..applyPermitDefaultValues();
      for (final origin in ['http://localhost:3001', 'https://shop.example']) {
        final request = MockServerHttpRequest(HttpMethod.options, '/api')
          ..headers.set('Origin', origin)
          ..headers.set('Access-Control-Request-Method', 'POST');
        final response = MockServerHttpResponse();
        expect(
          processCors(config, request, response, preFlight: true),
          isTrue,
          reason: origin,
        );
        expect(response.headers['Access-Control-Allow-Origin'], origin);
      }
    });

    test('@CrossOrigin(allowCredentials: true) with "*" among '
        'comma-separated origins stops the startup, as Spring', () {
      final factory = DefaultListableBeanFactory()
        ..registerBeanDefinition(
          BeanDefinition<_Open>(
            name: 'open',
            create: (_) => _Open(),
            annotations: const [
              RestController(),
              CrossOrigin(
                origins: ['https://a.example, *'],
                allowCredentials: true,
              ),
            ],
            annotatedMethods: [
              BeanMethod<_Open>(
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
            contains('allowCredentials: true) needs origins'),
          ),
        ),
      );
    });
  });

  group('@ControllerAdvice', () {
    test('the first advice bean in @Order with a handler answers, not the '
        'most specific handler of all beans', () async {
      // ReviewFirstErrors (order 1) handles Exception, ReviewSecondErrors
      // (order 2) FormatException: Spring takes the first bean.
      await app.mockMvc
          .get('/api/review/format')
          .andExpect(status: 400, body: 'first');
    });

    test('basePackages, assignableTypes and annotations narrow an '
        'advice', () async {
      // basePackages (ReviewFirstErrors does not handle errors).
      await app.mockMvc
          .get('/api/review/argument')
          .andExpect(status: 400, body: 'second');
      // annotations: ReviewController carries @ReviewApi().
      await app.mockMvc
          .get('/api/review/unsupported')
          .andExpect(status: 400, body: 'third');
      // The same error from another controller is not advised by them.
      await app.mockMvc.get('/misc/boom').andExpect(status: 500);
      // Nor an error raised before a controller method was chosen.
      await app.mockMvc
          .get('/api/review/nothing')
          .andExpect(
            status: 404,
            contentType: MediaType.applicationProblemJson,
          );
    });
  });

  group('ResponseEntity with a stream body', () {
    test('ResponseEntity<EventStream<T>> keeps status and headers', () async {
      final result = await app.mockMvc
          .get('/api/review/entity-events')
          .andReturn();
      await result.completion;
      expect(result.response.statusCode, 202);
      expect(result.response.headers['X-Stream'], 'on');
      expect(
        result.response.headers.contentType,
        startsWith(MediaType.textEventStream),
      );
      expect(
        result.response.events.map((e) => e.data).nonNulls.toList(),
        ['a', 'b'],
      );
    });

    test('ResponseEntity<SseEmitter> writes the emitter', () async {
      final result = await app.mockMvc
          .get('/api/review/entity-emitter')
          .andReturn();
      await result.completion;
      expect(result.response.statusCode, 200);
      expect(result.response.headers['X-Emitter'], 'on');
      expect(
        result.response.events.map((e) => e.data).nonNulls.toList(),
        ['x'],
      );
    });
  });

  // Review before 0.5.0: no limit on the number of parts (the class of
  // CVE-2023-24998: thousands of tiny parts, as many temporary files).
  test('more parts than spring.servlet.multipart.max-part-count is a '
      '413', () async {
    await app.mockMvc
        .multipart(
          '/files/many',
          files: [
            for (var i = 0; i < 51; i++)
              InMemoryMultipartFile('files', [i], originalFilename: '$i.bin'),
          ],
        )
        .andExpect(
          status: 413,
          contentType: MediaType.applicationProblemJson,
          json: containsPair('detail', contains('more than 50 parts')),
        );
    await app.mockMvc
        .multipart(
          '/files/many',
          files: [
            for (var i = 0; i < 50; i++)
              InMemoryMultipartFile('files', [i], originalFilename: '$i.bin'),
          ],
        )
        .andExpect(status: 200);
  });

  test('a body of a type nothing reads is a 415 before it is read', () async {
    await app.mockMvc
        .perform(
          MockRequestBuilder(HttpMethod.post, '/api/books')
            ..headers['Content-Type'] = 'multipart/form-data; boundary=x'
            ..content(List.filled(1024, 0x41)),
        )
        .andExpect(status: 415);
  });
}

final class _Open {}
