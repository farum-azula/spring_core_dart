// @RequestParam and @RequestHeader on a Map take every query parameter or
// header, as Spring's MapMethodProcessor does; the map is built with the
// parameter's own key and value types (Map<String, String>, not
// Map<String, Object?>), so the handler receives what it declares.
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

final class _Api {
  String params(Map<String, String> parameters) =>
      (parameters.keys.toList()..sort())
          .map((k) => '$k=${parameters[k]}')
          .join('&');

  String multi(Map<String, List<String>> parameters) =>
      parameters['tag']!.join(',');

  String counts(Map<String, int> parameters) =>
      '${parameters['a']! + parameters['b']!}';

  // A plain map keeps the names as they came; HttpHeaders is the
  // case-insensitive one, as in Spring.
  String headers(Map<String, String> headers) => headers.entries
      .where((e) => e.key.toLowerCase() == 'x-shop')
      .map((e) => e.value)
      .join();
}

BeanMethod<_Api> _route(
  String name,
  Function Function(_Api bean) method,
  Object annotation,
  TypeInfo<Object?> type,
) => BeanMethod<_Api>(
  name,
  parameterTypes: [type.type],
  parameters: [
    BeanParameter(
      'parameters',
      type: type,
      isRequired: true,
      annotations: [annotation],
    ),
  ],
  returnTypeInfo: const ClassType<String>(),
  invoke: (bean, arguments) => Function.apply(method(bean), arguments),
  annotations: [GetMapping('/$name')],
);

final _module = BeanModule('map_parameters', [
  BeanDefinition<_Api>(
    name: 'api',
    types: const [_Api],
    create: (_) => _Api(),
    annotatedMethods: [
      _route(
        'params',
        (b) => b.params,
        const RequestParam(),
        const MapType<String, String>(ClassType<String>(), ClassType<String>()),
      ),
      _route(
        'multi',
        (b) => b.multi,
        const RequestParam(),
        const MapType<String, List<String>>(
          ClassType<String>(),
          ListType<String>(ClassType<String>()),
        ),
      ),
      _route(
        'counts',
        (b) => b.counts,
        const RequestParam(),
        const MapType<String, int>(ClassType<String>(), ClassType<int>()),
      ),
      _route(
        'headers',
        (b) => b.headers,
        const RequestHeader(),
        const MapType<String, String>(ClassType<String>(), ClassType<String>()),
      ),
    ],
    annotations: const [RestController()],
  ),
]);

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

  Future<MockServerHttpResponse> get(
    String path, [
    Map<String, String> headers = const {},
  ]) async {
    final request = MockRequestBuilder(HttpMethod.get, path);
    request.headers.addAll(headers);
    return (await app.mockMvc.perform(request)).response;
  }

  test('Map<String, String> gets every query parameter', () async {
    final response = await get('/params?q=dune&page=2');
    expect(response.statusCode, 200);
    expect(response.bodyText, 'page=2&q=dune');
  });

  test('Map<String, List<String>> keeps repeated parameters', () async {
    final response = await get('/multi?tag=a&tag=b');
    expect(response.statusCode, 200);
    expect(response.bodyText, 'a,b');
  });

  test('Map<String, int> converts the values', () async {
    final response = await get('/counts?a=2&b=3');
    expect(response.statusCode, 200);
    expect(response.bodyText, '5');
  });

  test('a value that does not convert is a 400', () async {
    final response = await get('/counts?a=two&b=3');
    expect(response.statusCode, 400);
  });

  test('@RequestHeader Map<String, String> gets the headers', () async {
    final response = await get('/headers', {'X-Shop': 'neon'});
    expect(response.statusCode, 200);
    expect(response.bodyText, 'neon');
  });
}
