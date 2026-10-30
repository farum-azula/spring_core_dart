// Regression tests of the tenth review before 0.5.0, with and without the
// security chain and its CORS filter (`.cors()`, CSRF off, every request
// permitted). The expected values are Spring Security 7.1.2's (Spring MVC
// 7.0.10, spring-websocket 7.0.10 on Tomcat 11, the same beans, October
// 2026).
//
// - A WebSocket handshake is checked against the endpoint's allowed origins
//   only, never against the addCorsMappings rules: the filter asks the
//   handler mappings in the dispatcher's order, as Spring's
//   HandlerMappingIntrospector does, and the WebSocket mapping takes the
//   handshake. Only a corsConfigurationSource bean with rules for its path
//   is checked too (Spring Security applies that bean to every request).
// - The CorsConfigurationSource bean is the one named
//   corsConfigurationSource (Spring Security's CorsConfigurer): another
//   name is ignored, two beans of the type start.
import 'dart:async';

import 'package:spring_boot_starter_security/spring_auto_configuration.dart';
import 'package:spring_boot_starter_security/spring_boot_starter_security.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_websocket/spring_auto_configuration.dart';
import 'package:spring_boot_starter_websocket/spring_boot_starter_websocket.dart';
import 'package:test/test.dart';

const _corsVary = [
  'Origin',
  'Access-Control-Request-Method',
  'Access-Control-Request-Headers',
];
const _chat = 'https://chat.example';
const _app = 'https://app.example';
const _evil = 'https://evil.example';
const _bean = 'https://bean.example';
const _shop = 'https://shop.example';
const _other = 'https://other.example';
// MockMvc's requests go to http://localhost.
const _own = 'http://localhost';

final _chain = BeanDefinition<SecurityFilterChain>(
  name: 'chain',
  types: const [SecurityFilterChain],
  dependencies: const [Dependency(HttpSecurity)],
  create: (r) => r
      .dependency<HttpSecurity>()
      .cors()
      .csrf((c) => c.disable())
      .authorizeHttpRequests((a) => a.anyRequest().permitAll())
      .build(),
);

// The application of [beans]; [secured]: with the security starter and
// [_chain], else without any security filter.
Future<void> _withApp(
  String name,
  List<BeanDefinition<Object>> beans, {
  required bool secured,
  required Future<void> Function(MockMvc mvc) body,
}) {
  var runner = const ApplicationContextRunner()
      .withUserConfiguration(BeanModule(name, [...beans, if (secured) _chain]))
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebsocketAutoConfiguration);
  if (secured) {
    runner = runner
        .withAutoConfiguration(springSecurityCoreAutoConfiguration)
        .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
        .withAutoConfiguration(springBootStarterSecurityAutoConfiguration);
  }
  return runner
      .withPropertyValues([
        'spring.test.web-environment=mock',
        'logging.level.root=off',
        'spring.security.user.password=pw',
      ])
      .runAsync((started) async {
        if (started.startupFailure case final failure?) {
          fail('The application failed to start: $failure');
        }
        await body(MockMvc.of(started.context));
      });
}

// --- the WebSocket handshake (R10Ws) -------------------------------------

final class _Echo extends TextWebSocketHandler {
  @override
  void handleTextMessage(ServerWebSocketSession session, String message) =>
      session.sendMessage('echo: $message');
}

final class _Ws implements WebSocketConfigurer {
  @override
  void registerWebSocketHandlers(WebSocketHandlerRegistry registry) =>
      registry.addHandler(_Echo(), ['/ws']).setAllowedOrigins([_chat]);
}

final class _Global with WebMvcConfigurer {
  @override
  void addCorsMappings(CorsRegistry registry) =>
      registry.addMapping('/**').allowedOrigins([_app]);
}

final class _Api {
  String x() => 'x';
}

final _wsBeans = <BeanDefinition<Object>>[
  BeanDefinition<_Ws>(
    name: 'ws',
    types: const [_Ws, WebSocketConfigurer],
    create: (_) => _Ws(),
    annotations: const [Configuration()],
  ),
  BeanDefinition<_Global>(
    name: 'global',
    types: const [_Global, WebMvcConfigurer],
    create: (_) => _Global(),
    annotations: const [Configuration()],
  ),
  BeanDefinition<_Api>(
    name: 'api',
    types: const [_Api],
    create: (_) => _Api(),
    annotatedMethods: [
      BeanMethod<_Api>(
        'x',
        returnTypeInfo: const ClassType<String>(),
        invoke: (bean, arguments) => Function.apply(bean.x, arguments),
        annotations: const [GetMapping('/api/x')],
      ),
    ],
    annotations: const [RestController()],
  ),
];

// Rules for the handshake's path: GET from chat.example and bean.example.
final _wsSource = BeanDefinition<UrlBasedCorsConfigurationSource>(
  name: 'corsConfigurationSource',
  types: const [UrlBasedCorsConfigurationSource, CorsConfigurationSource],
  create: (_) => UrlBasedCorsConfigurationSource()
    ..registerCorsConfiguration(
      '/ws',
      CorsConfiguration(
        allowedOrigins: [_chat, _bean],
        allowedMethods: ['GET'],
      ),
    ),
);

Future<MockServerHttpResponse> _handshake(MockMvc mvc, String origin) async =>
    (await mvc.perform(
      MockRequestBuilder(HttpMethod.get, '/ws')
        ..headers.addAll({
          'Upgrade': 'websocket',
          'Connection': 'Upgrade',
          'Sec-WebSocket-Version': '13',
          'Origin': origin,
        }),
    )).response;

Future<void> _expectOpens(MockMvc mvc, String origin) async {
  final session = await mvc.webSocket('/ws', headers: {'Origin': origin});
  final replies = StreamIterator(session.messages);
  session.sendMessage('hi');
  expect(await replies.moveNext(), isTrue);
  expect(replies.current, 'echo: hi');
  await session.close();
}

// --- the CorsConfigurationSource bean's name (R10Sec) ---------------------

final class _S {
  String ox() => 'o';
  String oput() => 'op';
  String ax() => 'a';
  String aput() => 'ap';
}

BeanMethod<_S> _m(
  String name,
  Function Function(_S) method,
  List<Object> annotations,
) => BeanMethod<_S>(
  name,
  returnTypeInfo: const ClassType<String>(),
  invoke: (bean, arguments) => Function.apply(method(bean), arguments),
  annotations: annotations,
);

final _controllers = BeanDefinition<_S>(
  name: 's',
  types: const [_S],
  create: (_) => _S(),
  annotatedMethods: [
    _m('ox', (b) => b.ox, const [
      GetMapping('/other/x'),
      CrossOrigin(origins: [_other]),
    ]),
    _m('oput', (b) => b.oput, const [
      PutMapping('/other/put'),
      CrossOrigin(origins: [_other]),
    ]),
    _m('ax', (b) => b.ax, const [
      GetMapping('/api/x'),
      CrossOrigin(origins: [_other]),
    ]),
    _m('aput', (b) => b.aput, const [PutMapping('/api/put')]),
  ],
  annotations: const [RestController()],
);

// Rules for /api/** only: GET from the shop, with private network access.
BeanDefinition<Object> _apiSource(String name, {String origin = _shop}) =>
    BeanDefinition<UrlBasedCorsConfigurationSource>(
      name: name,
      types: const [UrlBasedCorsConfigurationSource, CorsConfigurationSource],
      create: (_) =>
          UrlBasedCorsConfigurationSource()..registerCorsConfiguration(
            '/api/**',
            CorsConfiguration(
              allowedOrigins: [origin],
              allowedMethods: ['GET'],
              allowPrivateNetwork: true,
              maxAge: const Duration(seconds: 100),
            ),
          ),
    );

// One request of the reviewer's table: method, path, Origin, the method a
// pre-flight announces (and whether it asks for private network access).
typedef _Case = (
  String name,
  HttpMethod method,
  String path,
  String origin,
  String? preFlightMethod,
);

// Spring's answer: status, Access-Control-Allow-Origin,
// Access-Control-Allow-Methods, Access-Control-Allow-Private-Network, Vary.
typedef _Answer = (int, String?, String?, String?, bool);

const HttpMethod _get = HttpMethod.get;
const HttpMethod _put = HttpMethod.put;
const HttpMethod _head = HttpMethod.head;
const HttpMethod _options = HttpMethod.options;

const _cases = <_Case>[
  ('other GET other', _get, '/other/x', _other, null),
  ('other GET shop', _get, '/other/x', _shop, null),
  ('other PUT other', _put, '/other/put', _other, null),
  ('other PF other', _options, '/other/x', _other, 'GET'),
  ('other PF PUT other', _options, '/other/put', _other, 'PUT'),
  ('api GET other (@CrossOrigin)', _get, '/api/x', _other, null),
  ('api GET shop', _get, '/api/x', _shop, null),
  ('api HEAD shop', _head, '/api/x', _shop, null),
  ('api PUT shop (bean GET only)', _put, '/api/put', _shop, null),
  ('api PF PUT shop', _options, '/api/put', _shop, 'PUT'),
  ('api PF GET shop pna', _options, '/api/x', _shop, 'GET pna'),
  ('api PF GET other', _options, '/api/x', _other, 'GET'),
  ('api PF unmapped', _options, '/api/nope', _shop, 'GET'),
  ('api GET unmapped', _get, '/api/nope', _shop, null),
  ('so PUT api', _put, '/api/put', _own, null),
  ('so PUT other', _put, '/other/put', _own, null),
  ('so PF api PUT', _options, '/api/put', _own, 'PUT'),
];

Future<void> _expectAnswers(MockMvc mvc, Map<String, _Answer> answers) async {
  for (final (name, method, path, origin, preFlight) in _cases) {
    final answer = answers[name];
    if (answer == null) {
      continue;
    }
    final request = MockRequestBuilder(method, path)
      ..headers['Origin'] = origin;
    if (preFlight != null) {
      request.headers['Access-Control-Request-Method'] = preFlight.split(
        ' ',
      )[0];
      if (preFlight.endsWith('pna')) {
        request.headers['Access-Control-Request-Private-Network'] = 'true';
      }
    }
    final response = (await mvc.perform(request)).response;
    final (status, allowOrigin, allowMethods, privateNetwork, vary) = answer;
    expect(response.statusCode, status, reason: name);
    expect(
      response.headers['Access-Control-Allow-Origin'],
      allowOrigin,
      reason: name,
    );
    expect(
      response.headers['Access-Control-Allow-Methods'],
      allowMethods,
      reason: name,
    );
    expect(
      response.headers['Access-Control-Allow-Private-Network'],
      privateNetwork,
      reason: name,
    );
    expect(
      response.headers.getAll('Vary'),
      vary ? _corsVary : isEmpty,
      reason: name,
    );
  }
}

// Spring Security with a bean of another name (apiCors): ignored; the
// handlers' @CrossOrigin decide, through the introspector.
const _otherNameAnswers = <String, _Answer>{
  'other GET other': (200, _other, null, null, true),
  'other GET shop': (403, null, null, null, true),
  'other PUT other': (200, _other, null, null, true),
  'other PF other': (200, _other, 'GET', null, true),
  'other PF PUT other': (200, _other, 'PUT', null, true),
  'api GET other (@CrossOrigin)': (200, _other, null, null, true),
  'api GET shop': (403, null, null, null, true),
  'api HEAD shop': (403, null, null, null, true),
  'api PUT shop (bean GET only)': (200, null, null, null, false),
  'api PF PUT shop': (200, null, null, null, false),
  'api PF GET shop pna': (403, null, null, null, true),
  'api PF GET other': (200, _other, 'GET', null, true),
  'api PF unmapped': (200, null, null, null, false),
  'api GET unmapped': (404, null, null, null, false),
  'so PUT api': (200, null, null, null, false),
  'so PUT other': (200, null, null, null, true),
  'so PF api PUT': (200, null, null, null, false),
};

// Spring Security with the bean named corsConfigurationSource: its rules
// alone on /api/**. (A pre-flight to /other/** gets the @CrossOrigin
// answer here; Spring's filter ends it without CORS headers: left out.)
const _namedAnswers = <String, _Answer>{
  'other GET other': (200, _other, null, null, true),
  'other GET shop': (403, null, null, null, true),
  'other PUT other': (200, _other, null, null, true),
  'api GET other (@CrossOrigin)': (403, null, null, null, true),
  'api GET shop': (200, _shop, null, null, true),
  'api HEAD shop': (403, null, null, null, true),
  'api PUT shop (bean GET only)': (403, null, null, null, true),
  'api PF PUT shop': (403, null, null, null, true),
  'api PF GET shop pna': (200, _shop, 'GET', 'true', true),
  'api PF GET other': (403, null, null, null, true),
  'api PF unmapped': (200, _shop, 'GET', null, true),
  'api GET unmapped': (404, _shop, null, null, true),
  'so PUT api': (200, null, null, null, true),
  'so PUT other': (200, null, null, null, true),
  'so PF api PUT': (200, null, null, null, true),
};

void main() {
  group('a WebSocket handshake: the endpoint allows chat.example, the '
      'addCorsMappings rules for /** app.example (Spring: 101, 403, 403)', () {
    for (final secured in [true, false]) {
      final label = secured ? 'with security' : 'without security';

      test('$label: chat.example opens; app.example and evil.example are '
          'refused by the endpoint, without CORS headers', () {
        return _withApp(
          'ws_$secured',
          _wsBeans,
          secured: secured,
          body: (mvc) async {
            await _expectOpens(mvc, _chat);
            for (final origin in [_app, _evil]) {
              final response = await _handshake(mvc, origin);
              expect(response.statusCode, 403, reason: origin);
              expect(response.bodyText, 'Origin not allowed', reason: origin);
              expect(
                response.headers['Access-Control-Allow-Origin'],
                isNull,
                reason: origin,
              );
              expect(response.headers.getAll('Vary'), isEmpty, reason: origin);
            }
            // The controllers keep the addCorsMappings rules.
            final api = await mvc.perform(
              MockRequestBuilder(HttpMethod.get, '/api/x')
                ..headers['Origin'] = _app,
            );
            expect(api.response.statusCode, 200);
            expect(api.response.headers['Access-Control-Allow-Origin'], _app);
          },
        );
      });
    }

    test('with security and a corsConfigurationSource bean with rules for '
        '/ws (chat.example, bean.example): the filter checks them too, as '
        'Spring Security applies the bean (101; 403 by the filter; 403 by '
        'the endpoint with the CORS headers)', () {
      return _withApp(
        'ws_bean_secured',
        [..._wsBeans, _wsSource],
        secured: true,
        body: (mvc) async {
          await _expectOpens(mvc, _chat);
          for (final origin in [_app, _evil]) {
            final response = await _handshake(mvc, origin);
            expect(response.statusCode, 403, reason: origin);
            expect(response.bodyText, 'Invalid CORS request', reason: origin);
            expect(response.headers.getAll('Vary'), _corsVary, reason: origin);
          }
          final bean = await _handshake(mvc, _bean);
          expect(bean.statusCode, 403);
          expect(bean.bodyText, 'Origin not allowed');
          expect(bean.headers['Access-Control-Allow-Origin'], _bean);
        },
      );
    });

    test('without security the bean is not consulted for a handshake '
        '(Spring MVC reads no such bean)', () {
      return _withApp(
        'ws_bean_plain',
        [..._wsBeans, _wsSource],
        secured: false,
        body: (mvc) async {
          await _expectOpens(mvc, _chat);
          for (final origin in [_app, _evil, _bean]) {
            final response = await _handshake(mvc, origin);
            expect(response.statusCode, 403, reason: origin);
            expect(response.bodyText, 'Origin not allowed', reason: origin);
            expect(
              response.headers['Access-Control-Allow-Origin'],
              isNull,
              reason: origin,
            );
          }
        },
      );
    });
  });

  group('the CorsConfigurationSource bean named corsConfigurationSource, as '
      "Spring Security's CorsConfigurer takes it", () {
    test("a bean of another name (apiCors) is ignored: the reviewer's "
        'cases as Spring answers them', () {
      return _withApp(
        'sec_api_cors',
        [_controllers, _apiSource('apiCors')],
        secured: true,
        body: (mvc) => _expectAnswers(mvc, _otherNameAnswers),
      );
    });

    test('the bean named corsConfigurationSource: its rules alone where it '
        'has some, as Spring answers', () {
      return _withApp(
        'sec_named',
        [_controllers, _apiSource('corsConfigurationSource')],
        secured: true,
        body: (mvc) => _expectAnswers(mvc, _namedAnswers),
      );
    });

    test('two beans of the type start (Spring: the named one is used; was a '
        'NoUniqueBeanDefinitionException)', () {
      return _withApp(
        'sec_two',
        [
          _controllers,
          _apiSource('corsConfigurationSource'),
          _apiSource('libraryCors', origin: 'https://library.example'),
        ],
        secured: true,
        body: (mvc) async {
          await _expectAnswers(mvc, _namedAnswers);
          final library = await mvc.perform(
            MockRequestBuilder(HttpMethod.get, '/api/x')
              ..headers['Origin'] = 'https://library.example',
          );
          expect(library.response.statusCode, 403);
        },
      );
    });

    test('a bean of that name that is no CorsConfigurationSource fails the '
        'start, as in Spring (BeanNotOfRequiredTypeException)', () async {
      await const ApplicationContextRunner()
          .withUserConfiguration(
            BeanModule('sec_wrong_type', [
              _controllers,
              _chain,
              BeanDefinition<String>(
                name: 'corsConfigurationSource',
                types: const [String],
                create: (_) => 'not CORS rules',
              ),
            ]),
          )
          .withAutoConfiguration(springBootAutoConfiguration)
          .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
          .withAutoConfiguration(springBootStarterWebAutoConfiguration)
          .withAutoConfiguration(springSecurityCoreAutoConfiguration)
          .withAutoConfiguration(springBootStarterOauth2ClientAutoConfiguration)
          .withAutoConfiguration(springBootStarterSecurityAutoConfiguration)
          .withPropertyValues([
            'spring.test.web-environment=mock',
            'logging.level.root=off',
            'spring.security.user.password=pw',
          ])
          .runAsync((started) async {
            expect(
              '${started.startupFailure}',
              contains('BeanNotOfRequiredTypeException'),
            );
          });
    });
  });
}
