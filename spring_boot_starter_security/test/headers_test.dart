// The cache headers on their own: when the writer leaves the application's
// headers alone, and when the Pragma and Expires it wrote go because the
// application chose its own Cache-Control (however the body is sent); and
// the CorsFilter by itself: which requests it answers, refuses or passes.
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_web_dart/testing.dart';
import 'package:test/test.dart';

const _ours = 'no-cache, no-store, max-age=0, must-revalidate';

final class _Chain implements WebFilterChain {
  _Chain(this.body);

  final Future<void> Function(ServerHttpResponse response) body;

  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
  ) => body(response);
}

// A response that never counts as committed, like a buffered one.
final class _Buffered extends ServerHttpResponseDecorator {
  _Buffered(super.delegate);

  @override
  bool get isCommitted => false;
}

void main() {
  group('CacheControlHeadersWriter', () {
    Map<String, String?> written(void Function(HttpHeaders headers) before) {
      final response = MockServerHttpResponse();
      before(response.headers);
      const CacheControlHeadersWriter().writeHeaders(
        MockServerHttpRequest(HttpMethod.get, '/'),
        response,
      );
      return {
        'cache-control': response.headers['cache-control'],
        'pragma': response.headers['pragma'],
        'expires': response.headers['expires'],
      };
    }

    test('writes all three on a bare response', () {
      expect(written((_) {}), {
        'cache-control': _ours,
        'pragma': 'no-cache',
        'expires': '0',
      });
    });

    for (final (name, value) in [
      ('Cache-Control', 'max-age=60'),
      ('Pragma', 'x'),
      ('Expires', 'Wed, 21 Oct 2026 07:28:00 GMT'),
    ]) {
      test('writes nothing when the response has $name already', () {
        final result = written((headers) => headers.set(name, value));
        expect(result[name.toLowerCase()], value);
        expect(
          result.values.where((v) => v != null),
          hasLength(1),
          reason: 'the others are not added',
        );
      });
    }
  });

  group("HeaderWriterFilter and the application's Cache-Control", () {
    Future<MockServerHttpResponse> run(
      List<HeaderWriter> writers,
      Future<void> Function(ServerHttpResponse response) body,
    ) async {
      final response = MockServerHttpResponse();
      await HeaderWriterFilter(writers).doFilter(
        MockServerHttpRequest(HttpMethod.get, '/'),
        response,
        _Chain(body),
      );
      return response;
    }

    const writers = [CacheControlHeadersWriter()];

    test('our Cache-Control keeps Pragma and Expires', () async {
      final response = await run(writers, (r) async => r.write('x'));
      expect(response.headers['cache-control'], _ours);
      expect(response.headers['pragma'], 'no-cache');
      expect(response.headers['expires'], '0');
    });

    test(
      'its own Cache-Control removes the Pragma and Expires we wrote',
      () async {
        final response = await run(writers, (r) async {
          r.headers.set('Cache-Control', 'max-age=60');
          r.write('x');
        });
        expect(response.headers['cache-control'], 'max-age=60');
        expect(response.headers['pragma'], isNull);
        expect(response.headers['expires'], isNull);
      },
    );

    test('its own Pragma and Expires stay', () async {
      final response = await run(writers, (r) async {
        r.headers
          ..set('Cache-Control', 'max-age=60')
          ..set('Pragma', 'custom')
          ..set('Expires', 'Wed, 21 Oct 2026 07:28:00 GMT');
        r.write('x');
      });
      expect(response.headers['pragma'], 'custom');
      expect(response.headers['expires'], 'Wed, 21 Oct 2026 07:28:00 GMT');
    });

    test('without a Cache-Control nothing is removed', () async {
      final response = await run(const [], (r) async {
        r.headers
          ..set('Pragma', 'no-cache')
          ..set('Expires', '0');
        r.write('x');
      });
      expect(response.headers['pragma'], 'no-cache');
      expect(response.headers['expires'], '0');
    });

    test('the headers are checked once, at the first write', () async {
      final response = MockServerHttpResponse();
      await HeaderWriterFilter(writers).doFilter(
        MockServerHttpRequest(HttpMethod.get, '/'),
        _Buffered(response),
        _Chain((r) async {
          r.headers.set('Cache-Control', 'max-age=60');
          r.write('a');
          r.headers.set('Pragma', 'no-cache');
          r.write('b');
        }),
      );
      expect(response.headers['pragma'], 'no-cache');
    });

    test('nothing changes once the response is committed', () async {
      final response = MockServerHttpResponse();
      await HeaderWriterFilter(writers).doFilter(
        MockServerHttpRequest(HttpMethod.get, '/'),
        response,
        _Chain((r) async {
          await response.flush();
          r.headers.set('Cache-Control', 'max-age=60');
          r.write('x');
        }),
      );
      expect(response.headers['pragma'], 'no-cache');
      expect(response.headers['expires'], '0');
    });
  });

  group("the application's Cache-Control is seen however the body is sent", () {
    Future<MockServerHttpResponse> run(
      Future<void> Function(ServerHttpResponse response) body,
    ) async {
      final response = MockServerHttpResponse();
      await HeaderWriterFilter(const [CacheControlHeadersWriter()]).doFilter(
        MockServerHttpRequest(HttpMethod.get, '/'),
        response,
        _Chain(body),
      );
      return response;
    }

    void expectOwn(MockServerHttpResponse response) {
      expect(response.headers['cache-control'], 'max-age=60');
      expect(response.headers['pragma'], isNull);
      expect(response.headers['expires'], isNull);
    }

    test('flush', () async {
      expectOwn(
        await run((r) async {
          r.headers.set('Cache-Control', 'max-age=60');
          await r.flush();
        }),
      );
    });

    test('addStream', () async {
      expectOwn(
        await run((r) async {
          r.headers.set('Cache-Control', 'max-age=60');
          await r.addStream(Stream.value([104, 105]));
        }),
      );
    });

    test('add (bytes)', () async {
      expectOwn(
        await run((r) async {
          r.headers.set('Cache-Control', 'max-age=60');
          r.add([104, 105]);
        }),
      );
    });

    test('close', () async {
      expectOwn(
        await run((r) async {
          r.headers.set('Cache-Control', 'max-age=60');
          await r.close();
        }),
      );
    });

    test('the body still arrives', () async {
      final response = await run((r) async {
        r
          ..headers.set('Cache-Control', 'max-age=60')
          ..write('he')
          ..add([108, 108]);
        await r.addStream(Stream.value([111]));
      });
      expect(response.bodyText, 'hello');
    });
  });

  group('CorsFilter', () {
    final config = CorsConfiguration(
      allowedOrigins: ['https://app.example'],
      allowedMethods: ['GET', 'POST'],
    );

    Future<({MockServerHttpResponse response, bool reached, int asked})> run(
      CorsConfiguration? Function(ServerHttpRequest request) source,
      MockServerHttpRequest request,
    ) async {
      var asked = 0;
      final response = MockServerHttpResponse();
      var reached = false;
      await CorsFilter((r) {
        asked++;
        return source(r);
      }).doFilter(request, response, _Chain((_) async => reached = true));
      return (response: response, reached: reached, asked: asked);
    }

    MockServerHttpRequest cross({
      HttpMethod method = HttpMethod.get,
      String origin = 'https://app.example',
      String? preFlightFor,
    }) {
      final request = MockServerHttpRequest(method, '/api/x')
        ..headers.set('Origin', origin);
      if (preFlightFor != null) {
        request.headers.set('Access-Control-Request-Method', preFlightFor);
      }
      return request;
    }

    test('a request that is not cross-origin is not looked at', () async {
      final result = await run(
        (_) => config,
        MockServerHttpRequest(HttpMethod.get, '/api/x'),
      );
      expect(result.reached, isTrue);
      expect(result.asked, 0);
      expect(result.response.headers['access-control-allow-origin'], isNull);
    });

    test(
      'an allowed cross-origin request gets the headers and goes on',
      () async {
        final result = await run((_) => config, cross());
        expect(result.reached, isTrue);
        expect(
          result.response.headers['access-control-allow-origin'],
          'https://app.example',
        );
      },
    );

    test('a pre-flight is answered here and goes no further', () async {
      final result = await run(
        (_) => config,
        cross(method: HttpMethod.options, preFlightFor: 'POST'),
      );
      expect(result.reached, isFalse);
      expect(result.response.statusCode, 200);
      expect(
        result.response.headers['access-control-allow-origin'],
        'https://app.example',
      );
    });

    test('an origin that is not allowed is refused with 403', () async {
      final result = await run(
        (_) => config,
        cross(origin: 'https://evil.example'),
      );
      expect(result.reached, isFalse);
      expect(result.response.statusCode, 403);
      expect(result.response.headers['access-control-allow-origin'], isNull);
    });

    test('without a configuration a pre-flight is refused, silently', () async {
      final result = await run(
        (_) => null,
        cross(method: HttpMethod.options, preFlightFor: 'POST'),
      );
      expect(result.reached, isFalse);
      expect(result.response.statusCode, 403);
      expect(result.response.headers['access-control-allow-origin'], isNull);
    });

    test('without a configuration an actual request goes on, with no CORS '
        'headers', () async {
      final result = await run((_) => null, cross());
      expect(result.reached, isTrue);
      expect(result.response.headers['access-control-allow-origin'], isNull);
    });
  });
}
