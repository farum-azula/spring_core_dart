// Regression tests of the eighth review before 0.5.0 over real sockets:
// CORS values outside visible US-ASCII, which dart:io cannot send back in
// a header. Echoed, they gave any client a 500 and an ERROR log with a
// stack trace; they are refused with a 403 now, as Tomcat and Spring
// refuse such an Origin.
@Tags(['integration'])
library;

import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

import 'server_review_test.dart' show raw, statusOf;

void main() {
  late ConfigurableApplicationContext context;
  late int port;
  final errors = <SpringLogRecord>[];
  late void Function() stopListening;

  setUpAll(() async {
    context =
        await SpringApplication(
          [_module],
          autoConfigurations: [
            springBootAutoConfiguration,
            springBootStarterLoggingAutoConfiguration,
            springBootStarterWebAutoConfiguration,
          ],
        ).runAsync([
          '--server.port=0',
          '--server.address=127.0.0.1',
          '--spring.main.banner-mode=off',
          '--logging.level.root=error',
        ]);
    port = (await context.getBean<WebServerStartStopLifecycle>().started)!.port;
    stopListening = SpringLog.listen((record) {
      if (record.level.index >= SpringLogLevel.error.index) {
        errors.add(record);
      }
    });
  });

  tearDownAll(() async {
    stopListening();
    await context.closeAsync();
  });

  setUp(errors.clear);

  // The request head, in Latin-1 as raw() sends it: `\u00e9` is the byte
  // 0xE9, which dart:io reads back as U+00E9.
  String head(String method, String path, Map<String, String> headers) => [
    '$method $path HTTP/1.1',
    'Host: 127.0.0.1',
    'Connection: close',
    for (final MapEntry(:key, :value) in headers.entries) '$key: $value',
    '\r\n',
  ].join('\r\n');

  // The CORS headers of [answer], their names in lower case.
  List<String> corsHeaders(String answer) => [
    for (final line in answer.split('\r\n\r\n').first.split('\r\n'))
      if (line.toLowerCase().startsWith('access-control-'))
        line.replaceRange(
          0,
          line.indexOf(':'),
          line.split(':').first.toLowerCase(),
        ),
  ];

  test('an Origin with a byte above 0x7E that a pattern matches: 403, no '
      'error logged; the same host in punycode: allowed', () async {
    for (final origin in [
      'https://\u00e9.example.com',
      'https://a\u0085b.example.com',
    ]) {
      final answer = await raw(
        port,
        head('GET', '/pattern', {'Origin': origin}),
      );
      expect(statusOf(answer), 403, reason: Uri.encodeComponent(origin));
      expect(answer, endsWith('Invalid CORS request'));
      expect(corsHeaders(answer), isEmpty);
    }
    final punycode = await raw(
      port,
      head('GET', '/pattern', {'Origin': 'https://xn--9ca.example.com'}),
    );
    expect(statusOf(punycode), 200);
    expect(corsHeaders(punycode), [
      'access-control-allow-origin: https://xn--9ca.example.com',
    ]);
    expect(errors, isEmpty);
  });

  test('a pre-flight asking for such a header or method where * allows '
      'any: 403, no error logged', () async {
    for (final (method, headers) in [
      ('GET', 'x-\u00e9'),
      ('G\u00e9T', 'x-a'),
    ]) {
      final answer = await raw(
        port,
        head('OPTIONS', '/star/x', {
          'Origin': 'https://shop.example',
          'Access-Control-Request-Method': method,
          'Access-Control-Request-Headers': headers,
        }),
      );
      expect(statusOf(answer), 403, reason: Uri.encodeComponent(method));
      expect(corsHeaders(answer), isEmpty);
    }
    final plain = await raw(
      port,
      head('OPTIONS', '/star/x', {
        'Origin': 'https://shop.example',
        'Access-Control-Request-Method': 'GET',
        'Access-Control-Request-Headers': 'x-a',
      }),
    );
    expect(statusOf(plain), 200);
    expect(
      corsHeaders(plain),
      containsAll([
        'access-control-allow-origin: https://shop.example',
        'access-control-allow-methods: GET',
        'access-control-allow-headers: x-a',
      ]),
    );
    expect(errors, isEmpty);
  });
}

final class _Pattern {
  String plain() => 'p';
}

final class _Star {
  String plain() => 's';
}

final class _Cors with WebMvcConfigurer {
  @override
  void addCorsMappings(CorsRegistry registry) => registry
      .addMapping('/star/**')
      .allowedOrigins(['https://shop.example'])
      .allowedMethods(['*'])
      .allowedHeaders(['*']);
}

final _module = BeanModule('server_eighth_review', [
  BeanDefinition<_Pattern>(
    name: 'pattern',
    types: const [_Pattern],
    create: (_) => _Pattern(),
    annotatedMethods: [
      BeanMethod<_Pattern>(
        'plain',
        returnTypeInfo: const ClassType<String>(),
        invoke: (bean, arguments) => Function.apply(bean.plain, arguments),
        annotations: const [GetMapping('/pattern')],
      ),
    ],
    annotations: const [
      RestController(),
      CrossOrigin(originPatterns: ['https://*.example.com']),
    ],
  ),
  BeanDefinition<_Star>(
    name: 'star',
    types: const [_Star],
    create: (_) => _Star(),
    annotatedMethods: [
      BeanMethod<_Star>(
        'plain',
        returnTypeInfo: const ClassType<String>(),
        invoke: (bean, arguments) => Function.apply(bean.plain, arguments),
        annotations: const [GetMapping('/star/x')],
      ),
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
