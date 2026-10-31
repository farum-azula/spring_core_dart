// Regression tests of the tenth review before 0.5.0 that need no socket.
//
// - The CorsConfigurationSource bean is the one named
//   corsConfigurationSource, as Spring Security's CorsConfigurer takes it
//   (CORS_CONFIGURATION_SOURCE_BEAN_NAME): a bean of the type with another
//   name is ignored, and two such beans no longer fail the start with a
//   NoUniqueBeanDefinitionException (Spring MVC itself reads none).
// - DispatcherHandler.corsConfigurationFor asks the handler mappings in the
//   dispatcher's order, as Spring's HandlerMappingIntrospector: a request
//   another mapping takes (a WebSocket handshake) never gets the
//   addCorsMappings rules.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

const _shop = 'https://shop.example';
const _other = 'https://other.example';
const _library = 'https://library.example';

final class _Api {
  String x() => 'x';
}

// Rules for /api/** and /ws: GET from [origin].
UrlBasedCorsConfigurationSource _source(String origin) =>
    UrlBasedCorsConfigurationSource()
      ..registerCorsConfiguration(
        '/api/**',
        CorsConfiguration(allowedOrigins: [origin], allowedMethods: ['GET']),
      )
      ..registerCorsConfiguration(
        '/ws',
        CorsConfiguration(allowedOrigins: [origin], allowedMethods: ['GET']),
      );

BeanDefinition<Object> _sourceBean(String name, String origin) =>
    BeanDefinition<UrlBasedCorsConfigurationSource>(
      name: name,
      types: const [UrlBasedCorsConfigurationSource, CorsConfigurationSource],
      create: (_) => _source(origin),
    );

// GET /api/x with @CrossOrigin(origins: other.example).
final _api = BeanDefinition<_Api>(
  name: 'api',
  types: const [_Api],
  create: (_) => _Api(),
  annotatedMethods: [
    BeanMethod<_Api>(
      'x',
      returnTypeInfo: const ClassType<String>(),
      invoke: (bean, arguments) => Function.apply(bean.x, arguments),
      annotations: const [
        GetMapping('/api/x'),
        CrossOrigin(origins: [_other]),
      ],
    ),
  ],
  annotations: const [RestController()],
);

Future<void> _withApp(
  List<BeanDefinition<Object>> beans,
  Future<void> Function(ConfigurableApplicationContext context, MockMvc mvc)
  body,
) => const ApplicationContextRunner()
    .withUserConfiguration(BeanModule('cors_tenth_review', [_api, ...beans]))
    .withAutoConfiguration(springBootAutoConfiguration)
    .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
    .withAutoConfiguration(springBootStarterWebAutoConfiguration)
    .withPropertyValues([
      'spring.test.web-environment=mock',
      'logging.level.root=off',
    ])
    .runAsync((started) async {
      if (started.startupFailure case final failure?) {
        fail('The application failed to start: $failure');
      }
      await body(started.context, MockMvc.of(started.context));
    });

Future<MockServerHttpResponse> _get(MockMvc mvc, String origin) async =>
    (await mvc.perform(
      MockRequestBuilder(HttpMethod.get, '/api/x')..headers['Origin'] = origin,
    )).response;

// A handler mapping besides the router: it takes [paths], answering 200.
final class _Mapping implements HandlerMapping, Ordered {
  _Mapping(this.order, this.paths);

  @override
  final int order;
  final List<String> paths;

  @override
  HttpHandler? getHandler(ServerHttpRequest request) =>
      paths.contains(request.path)
      ? FunctionHttpHandler((request, response) => response.send(200, 'ws'))
      : null;
}

final class _Global with WebMvcConfigurer {
  @override
  void addCorsMappings(CorsRegistry registry) =>
      registry.addMapping('/**').allowedOrigins(['https://app.example']);
}

void main() {
  group('the CorsConfigurationSource bean named corsConfigurationSource, '
      'as Spring Security takes it', () {
    test('a bean of the type with another name is ignored: the '
        "handler's @CrossOrigin decides (Spring MVC reads no such bean)", () {
      return _withApp([_sourceBean('apiCors', _shop)], (context, mvc) async {
        final other = await _get(mvc, _other);
        expect(other.statusCode, 200);
        expect(other.headers['Access-Control-Allow-Origin'], _other);
        final shop = await _get(mvc, _shop);
        expect(shop.statusCode, 403);
        expect(shop.headers['Access-Control-Allow-Origin'], isNull);
      });
    });

    test('two beans of the type start (no NoUniqueBeanDefinitionException); '
        'the one named corsConfigurationSource decides alone', () {
      return _withApp(
        [
          _sourceBean('corsConfigurationSource', _shop),
          _sourceBean('libraryCors', _library),
        ],
        (context, mvc) async {
          for (final (origin, status) in [
            (_shop, 200),
            (_other, 403),
            (_library, 403),
          ]) {
            final response = await _get(mvc, origin);
            expect(response.statusCode, status, reason: origin);
            expect(
              response.headers['Access-Control-Allow-Origin'],
              status == 200 ? origin : null,
              reason: origin,
            );
          }
        },
      );
    });

    test('the bean named corsConfigurationSource alone: its rules', () {
      return _withApp([_sourceBean('corsConfigurationSource', _shop)], (
        context,
        mvc,
      ) async {
        expect((await _get(mvc, _shop)).statusCode, 200);
        expect((await _get(mvc, _other)).statusCode, 403);
      });
    });

    test('a bean of that name that is no CorsConfigurationSource is not '
        'taken for rules', () {
      return _withApp(
        [
          BeanDefinition<String>(
            name: 'corsConfigurationSource',
            types: const [String],
            create: (_) => 'not CORS rules',
          ),
        ],
        (context, mvc) async {
          expect((await _get(mvc, _other)).statusCode, 200);
          expect((await _get(mvc, _shop)).statusCode, 403);
        },
      );
    });
  });

  group("DispatcherHandler.corsConfigurationFor: the dispatcher's mappings in "
      "order, as Spring's HandlerMappingIntrospector", () {
    final global = BeanDefinition<_Global>(
      name: 'global',
      types: const [_Global, WebMvcConfigurer],
      create: (_) => _Global(),
      annotations: const [Configuration()],
    );
    BeanDefinition<Object> mapping(
      String name,
      int order,
      List<String> paths,
    ) => BeanDefinition<_Mapping>(
      name: name,
      types: const [_Mapping, HandlerMapping, Ordered],
      create: (_) => _Mapping(order, paths),
    );

    Future<List<String>?> originsFor(
      ConfigurableApplicationContext context,
      HttpMethod method,
      String path,
    ) async => (await context.getBean<DispatcherHandler>().corsConfigurationFor(
      MockServerHttpRequest(method, path)
        ..headers.set('Origin', 'https://app.example'),
    ))?.allowedOrigins;

    test('a request another mapping takes (a WebSocket handshake) gets no '
        'addCorsMappings rules; the router and a 404 do', () {
      return _withApp(
        [
          global,
          mapping('ws', 1, ['/ws']),
        ],
        (
          context,
          mvc,
        ) async {
          expect(await originsFor(context, HttpMethod.get, '/ws'), isNull);
          expect(await originsFor(context, HttpMethod.get, '/api/x'), [
            'https://app.example',
            _other,
          ]);
          expect(await originsFor(context, HttpMethod.get, '/nope'), [
            'https://app.example',
          ]);
          // The router refuses a POST (405): passed over, as the
          // introspector ignores the exception; no other mapping takes it.
          expect(await originsFor(context, HttpMethod.post, '/api/x'), [
            'https://app.example',
          ]);
        },
      );
    });

    test('a mapping ordered before the router takes its requests first, as '
        'in dispatch', () {
      return _withApp(
        [
          global,
          mapping('first', -1, ['/api/x']),
        ],
        (
          context,
          mvc,
        ) async {
          expect(await originsFor(context, HttpMethod.get, '/api/x'), isNull);
          final response = await _get(mvc, _other);
          expect(response.bodyText, 'ws');
          expect(response.headers['Access-Control-Allow-Origin'], isNull);
        },
      );
    });

    test("another mapping's request gets the corsConfigurationSource "
        "bean's rules where it has some", () {
      return _withApp(
        [
          global,
          mapping('ws', 1, ['/ws', '/ws2']),
          _sourceBean('corsConfigurationSource', _shop),
        ],
        (context, mvc) async {
          expect(await originsFor(context, HttpMethod.get, '/ws'), [_shop]);
          expect(await originsFor(context, HttpMethod.get, '/ws2'), isNull);
        },
      );
    });
  });
}
