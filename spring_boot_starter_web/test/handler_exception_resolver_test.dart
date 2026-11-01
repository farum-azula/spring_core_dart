// HandlerExceptionResolver beans: asked after the @ExceptionHandler methods of
// the controller and of the @ControllerAdvice beans, in @Order, before the
// default answer; the answer is an ErrorResponse written as a problem. The
// beans are described by hand (no generated code).
import 'dart:convert';

import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:test/test.dart';

const _shop = 'https://shop.example';
const _corsVary = [
  'Origin',
  'Access-Control-Request-Method',
  'Access-Control-Request-Headers',
];

// What the resolvers must not send to the client.
const _secret = 'select * from people where ssn = 123-45-6789';

class _DataError implements Exception {
  @override
  String toString() => '_DataError: $_secret';
}

// One error per case; the resolvers below decide what each becomes.
class _Local implements Exception {}

class _Advised implements Exception {}

class _Both implements Exception {}

class _PassOn implements Exception {}

class _Broken implements Exception {}

class _Slow implements Exception {}

class _Unclaimed implements Exception {}

class _Api {
  void fail(Exception error) => throw error;

  ResponseEntity<String> local(_Local error) =>
      ResponseEntity.status(HttpStatus.badRequest).body('local');
}

class _Errors {
  ResponseEntity<String> advised(_Advised error) =>
      ResponseEntity.status(HttpStatus.badRequest).body('advice');
}

// Order 1. Answers more than the others on purpose: the errors that have
// an @ExceptionHandler must never reach it.
final class _First implements HandlerExceptionResolver {
  static final offered = <Object>[];
  static final handlers = <HandlerMethod?>[];

  @override
  ErrorResponse? resolveException(
    ServerHttpRequest request,
    Object error, {
    HandlerMethod? handler,
  }) {
    offered.add(error);
    handlers.add(handler);
    return switch (error) {
      _DataError() => ErrorResponseException(
        HttpStatus.conflict,
        body: ProblemDetail.forStatusAndDetail(
          HttpStatus.conflict,
          'The resource already exists',
        ),
        headers: HttpHeaders()
          ..set('X-Resolved-By', 'first')
          ..set(HttpHeaders.varyHeader, 'Accept-Language'),
      ),
      _Local() || _Advised() => ResponseStatusException(
        HttpStatus.conflict,
        'resolver',
      ),
      _Both() => ResponseStatusException(HttpStatus.conflict, 'first'),
      _Broken() => throw StateError('the resolver is broken'),
      _ => null,
    };
  }
}

// Order 2, asynchronous.
final class _Second implements HandlerExceptionResolver {
  static final offered = <Object>[];

  @override
  Future<ErrorResponse?> resolveException(
    ServerHttpRequest request,
    Object error, {
    HandlerMethod? handler,
  }) async {
    offered.add(error);
    await Future<void>.delayed(Duration.zero);
    return switch (error) {
      _Both() => ResponseStatusException(HttpStatus.badGateway, 'second'),
      _PassOn() => ResponseStatusException(HttpStatus.gone, 'second'),
      _Broken() => ResponseStatusException(HttpStatus.gone, 'after the bug'),
      _Slow() => ResponseStatusException(HttpStatus.tooManyRequests, 'slow'),
      _ => null,
    };
  }
}

// A filter that fails the way a controller would.
final class _FailingFilter implements WebFilter {
  @override
  Future<void> doFilter(
    ServerHttpRequest request,
    ServerHttpResponse response,
    WebFilterChain chain,
  ) {
    if (request.headers.getAll('X-Fail').isNotEmpty) {
      throw _DataError();
    }
    return chain.doFilter(request, response);
  }
}

BeanMethod<T> _method<T extends Object>(
  String name,
  Function Function(T bean) method,
  List<Object> annotations, {
  List<Type> parameterTypes = const [],
  List<BeanParameter> parameters = const [],
  TypeInfo<Object?> returns = const ClassType<String>(),
}) => BeanMethod<T>(
  name,
  parameterTypes: parameterTypes,
  parameters: parameters,
  returnTypeInfo: returns,
  invoke: (bean, arguments) => Function.apply(method(bean), arguments),
  annotations: annotations,
);

BeanMethod<_Api> _route(String path, Exception Function() error) =>
    BeanMethod<_Api>(
      path,
      returnTypeInfo: const ClassType<String>(),
      invoke: (bean, arguments) => bean.fail(error()),
      annotations: [GetMapping('/api/$path')],
    );

BeanMethod<B> _handler<B extends Object, E extends Exception>(
  String name,
  Function Function(B bean) method,
) => _method<B>(
  name,
  method,
  const [ExceptionHandler()],
  parameterTypes: [E],
  parameters: [
    BeanParameter('error', type: ClassType<E>(), isRequired: true),
  ],
  returns: const GenericType<ResponseEntity<String>>([ClassType<String>()]),
);

final _module = BeanModule('handler_exception_resolver', [
  BeanDefinition<_Api>(
    name: 'api',
    types: const [_Api],
    create: (_) => _Api(),
    annotatedMethods: [
      _route('data', _DataError.new),
      _route('local', _Local.new),
      _route('advised', _Advised.new),
      _route('both', _Both.new),
      _route('pass-on', _PassOn.new),
      _route('broken', _Broken.new),
      _route('slow', _Slow.new),
      _route('unclaimed', _Unclaimed.new),
      _route(
        'status',
        () => ResponseStatusException(HttpStatus.iAmATeapot, 'tea'),
      ),
      // The controller's own handler.
      _handler<_Api, _Local>('local', (b) => b.local),
    ],
    annotations: const [
      RestController(),
      CrossOrigin(origins: [_shop]),
    ],
  ),
  BeanDefinition<_Errors>(
    name: 'errors',
    types: const [_Errors],
    create: (_) => _Errors(),
    annotatedMethods: [
      _handler<_Errors, _Advised>('advised', (b) => b.advised),
    ],
    annotations: const [RestControllerAdvice()],
  ),
  // Registered before the first one: the order comes from @Order.
  BeanDefinition<_Second>(
    name: 'second',
    types: const [_Second, HandlerExceptionResolver],
    create: (_) => _Second(),
    order: 2,
  ),
  BeanDefinition<_First>(
    name: 'first',
    types: const [_First, HandlerExceptionResolver],
    create: (_) => _First(),
    order: 1,
  ),
  BeanDefinition<_FailingFilter>(
    name: 'failingFilter',
    types: const [_FailingFilter, WebFilter],
    create: (_) => _FailingFilter(),
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

  setUp(() {
    _First.offered.clear();
    _First.handlers.clear();
    _Second.offered.clear();
  });

  // The records of 'spring.web.mvc' that [body] logs at [level] or above,
  // kept off the console.
  Future<List<SpringLogRecord>> logged(
    SpringLogLevel level,
    Future<void> Function() body,
  ) async {
    const name = 'spring.web.mvc';
    final records = <SpringLogRecord>[];
    final stop = SpringLog.listen((r) {
      if (r.loggerName == name) {
        records.add(r);
      }
    });
    final previous = SpringLog.configuredLevels[name];
    final handler = SpringLog.handler;
    SpringLog.setLevel(name, level);
    SpringLog.handler = (_) {};
    try {
      await body();
    } finally {
      SpringLog.handler = handler;
      SpringLog.setLevel(name, previous);
      stop();
    }
    return records;
  }

  Future<MockServerHttpResponse> get(
    String path, [
    Map<String, String> headers = const {},
  ]) async {
    final request = MockRequestBuilder(HttpMethod.get, path);
    request.headers.addAll(headers);
    return (await app.mockMvc.perform(request)).response;
  }

  group('the answer of a resolver', () {
    test("is a problem with the resolver's status, headers and generic "
        'detail', () async {
      final response = await get('/api/data');
      expect(response.statusCode, 409);
      expect(response.headers.contentType, MediaType.applicationProblemJson);
      expect(jsonDecode(response.bodyText), {
        'type': 'about:blank',
        'title': 'Conflict',
        'status': 409,
        'detail': 'The resource already exists',
        'instance': '/api/data',
      });
      expect(response.headers['X-Resolved-By'], 'first');
      expect(response.bodyText, isNot(contains(_secret)));
      expect(response.bodyText, isNot(contains('_DataError')));
    });

    test('keeps the CORS headers, and its Vary joins the CORS names', () async {
      final response = await get('/api/data', {'Origin': _shop});
      expect(response.statusCode, 409);
      expect(response.headers['Access-Control-Allow-Origin'], _shop);
      expect(response.headers.getAll('Vary'), [
        ..._corsVary,
        'Accept-Language',
      ]);
    });

    test("is asked with the request's handler", () async {
      await get('/api/data');
      expect(_First.handlers.single?.description, '_Api.data');
    });

    test('may be asynchronous', () async {
      final response = await get('/api/slow');
      expect(response.statusCode, 429);
      expect(jsonDecode(response.bodyText), containsPair('detail', 'slow'));
    });
  });

  group('the order', () {
    test("the controller's @ExceptionHandler comes first", () async {
      final response = await get('/api/local');
      expect(response.statusCode, 400);
      expect(response.bodyText, 'local');
      expect(_First.offered, isEmpty);
    });

    test('@ExceptionHandler methods of an advice come next', () async {
      final response = await get('/api/advised');
      expect(response.statusCode, 400);
      expect(response.bodyText, 'advice');
      expect(_First.offered, isEmpty);
    });

    test('the resolvers go by @Order, the first answer wins', () async {
      final response = await get('/api/both');
      expect(response.statusCode, 409);
      expect(jsonDecode(response.bodyText), containsPair('detail', 'first'));
      expect(_Second.offered, isEmpty);
    });

    test('a resolver that returns null passes the error on', () async {
      final response = await get('/api/pass-on');
      expect(response.statusCode, 410);
      expect(jsonDecode(response.bodyText), containsPair('detail', 'second'));
      expect(_First.offered.single, isA<_PassOn>());
      expect(_Second.offered.single, isA<_PassOn>());
    });

    test(
      'an error nobody resolves is the default 500 without details',
      () async {
        final response = await get('/api/unclaimed');
        expect(response.statusCode, 500);
        expect(response.headers.contentType, MediaType.applicationProblemJson);
        expect(jsonDecode(response.bodyText), {
          'type': 'about:blank',
          'title': 'Internal Server Error',
          'status': 500,
          'instance': '/api/unclaimed',
        });
        expect(_First.offered.single, isA<_Unclaimed>());
        expect(_Second.offered.single, isA<_Unclaimed>());
      },
    );

    test('a resolver that throws is logged and skipped', () async {
      final records = await logged(SpringLogLevel.warning, () async {
        final response = await get('/api/broken');
        expect(response.statusCode, 410);
        expect(
          jsonDecode(response.bodyText),
          containsPair('detail', 'after the bug'),
        );
      });
      final warning = records.single;
      expect(warning.level, SpringLogLevel.warning);
      expect(warning.message, contains('HandlerExceptionResolver _First'));
      expect(warning.error, isA<StateError>());
    });
  });

  group('what the resolvers are not asked', () {
    test("an error that is an ErrorResponse: the controller's, the "
        "router's 404 and 405", () async {
      final status = await get('/api/status');
      expect(status.statusCode, 418);
      expect(jsonDecode(status.bodyText), containsPair('detail', 'tea'));
      final missing = await get('/api/nothing');
      expect(missing.statusCode, 404);
      final post = await app.mockMvc.perform(
        MockRequestBuilder(HttpMethod.post, '/api/data'),
      );
      expect(post.response.statusCode, 405);
      expect(_First.offered, isEmpty);
      expect(_Second.offered, isEmpty);
    });

    test('an error of a filter', () async {
      final response = await get('/api/data', {'X-Fail': '1'});
      expect(response.statusCode, 500);
      expect(_First.offered, isEmpty);
    });
  });

  test('the error is logged at debug level, with the resolver and the '
      'status', () async {
    final records = await logged(SpringLogLevel.debug, () async {
      await get('/api/data');
    });
    final resolved = records.singleWhere(
      (r) => r.message.startsWith('Resolved ['),
    );
    expect(resolved.level, SpringLogLevel.debug);
    expect(resolved.message, contains('_DataError'));
    expect(resolved.message, contains('409'));
    expect(resolved.message, contains('_First'));
  });
}
