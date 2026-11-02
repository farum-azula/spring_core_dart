// The resolver of the web/data glue runs: the generator output for an
// application that depends on both starters is written next to its sources
// and started in a separate process against the real starters, so the
// answers the test expects are the answers the generated code really gives.
@TestOn('vm')
@Tags(['integration'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:build_test/build_test.dart';
import 'package:package_config/package_config.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _pubspec = '''
name: pkg
dependencies:
  spring_boot_starter_data: any
  spring_boot_starter_web: any
''';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/src/beans.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

// A controller with Pageable and Sort parameters, started on a real server.
const _books = r'''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

@Introspected()
class Book {
  Book(this.title);
  String title;
}

@RestController()
@RequestMapping('/books')
class BookController {
  @GetMapping()
  Future<Page<Book>> list(
    @PageableDefault(size: 2, sort: ['title']) Pageable pageable,
  ) async => PageImpl(
    [Book('Dune'), Book('Emma')],
    pageable,
    41,
  );

  @GetMapping('/sorted')
  Future<String> sorted(Sort sort) async => '$sort';

  @GetMapping('/page')
  Future<String> page(Pageable pageable) async =>
      '${pageable.pageNumber}/${pageable.pageSize}/${pageable.sort}';

  @GetMapping('/unknown')
  Future<String> unknown() async =>
      throw PropertyReferenceException('nope', 'Book');

  @GetMapping('/value')
  Future<String> value() async =>
      throw InvalidDataArgumentException('secret 123-45-6789');
}
''';

// The generated module in a context, the resolver asked about errors.
const _main = r'''
import 'dart:convert';

import 'dart:io';

import 'package:pkg/src/beans.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'package:spring_boot_starter_web/spring_auto_configuration.dart';
import 'package:spring_web_dart/testing.dart';

// Never used by the resolver.
class _Request implements ServerHttpRequest {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SubclassOfDuplicateKey extends DuplicateKeyException {
  _SubclassOfDuplicateKey() : super('subclass');
}

// An application's own resolver, under the name of the generated one.
class _Teapot implements HandlerExceptionResolver {
  @override
  ErrorResponse? resolveException(
    ServerHttpRequest request,
    Object error, {
    HandlerMethod? handler,
  }) => ResponseStatusException(HttpStatus.iAmATeapot, 'mine');
}

Map<String, Object?>? describe(ErrorResponse? answer, Object error) {
  if (answer == null) {
    return null;
  }
  return {
    'status': answer.statusCode,
    'json': answer.body.toJson(),
    'headers': answer.headers.isEmpty,
    'cause': answer is ErrorResponseException && identical(answer.cause, error),
  };
}

Future<List<Object?>> ask(
  HandlerExceptionResolver resolver,
  List<Object> errors,
) async => [
  for (final error in errors)
    describe(await resolver.resolveException(_Request(), error), error),
];

// The paging resolver of the glue: a configurer bean made from the
// environment, asked about parameters of a fake controller method.
final class _NoBeans implements BeanFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

List<MethodParameter> parameters(List<(TypeInfo<Object?>, List<Object>)> all) =>
    HandlerMethod(
      beanName: 'controller',
      beanTypeName: 'Controller',
      method: BeanMethod<Object>(
        'handle',
        invoke: (bean, arguments) => null,
        parameters: [
          for (final (i, (type, annotations)) in all.indexed)
            BeanParameter('p$i', type: type, annotations: annotations),
        ],
      ),
      classAnnotations: const [],
      beanFactory: _NoBeans(),
    ).parameters;

HandlerMethodArgumentResolver pagingResolver(ApplicationContext context) {
  final resolvers = <HandlerMethodArgumentResolver>[];
  for (final configurer in context.getBeansOfType<WebMvcConfigurer>().values) {
    configurer.addArgumentResolvers(resolvers);
  }
  return resolvers.single;
}

Object? resolve(
  HandlerMethodArgumentResolver resolver,
  MethodParameter parameter,
  String query,
) => resolver.resolveArgument(
  parameter,
  MockServerHttpRequest(HttpMethod.get, '/books?$query'),
  MockServerHttpResponse(),
);

String show(Object? value) => switch (value) {
  Pageable() => 'page ${value.pageNumber} size ${value.pageSize} '
      'sort ${value.sort}',
  Sort() => 'sort $value',
  _ => '$value',
};

Map<String, Object?> pagingResults() {
  ConfigurableApplicationContext start(Map<String, Object?> properties) {
    final environment = StandardEnvironment();
    environment.propertySources.addFirst(
      MapPropertySource('test', properties),
    );
    return AnnotationConfigApplicationContext(
      [pkgBeans],
      environment: environment,
    )..refresh();
  }

  final context = start({});
  final resolver = pagingResolver(context);
  const pageable = ClassType<Pageable>();
  const sort = ClassType<Sort>();
  MethodParameter one(TypeInfo<Object?> type, [List<Object> annotations = const []]) =>
      parameters([(type, annotations)]).single;
  final plain = one(pageable);
  final withDefault = one(pageable, const [
    PageableDefault(size: 5, sort: ['title']),
  ]);
  final sortDefault = one(pageable, const [
    SortDefault(sort: ['year'], direction: Direction.desc),
    SortDefault(sort: ['title']),
  ]);
  final forSort = one(sort, const [SortDefault(sort: ['id'])]);
  final other = one(const ClassType<String>());
  final first = one(pageable, const [Qualifier('first')]);
  final second = one(pageable, const [Qualifier('second')]);
  final result = <String, Object?>{
    'supports': [
      for (final parameter in [plain, forSort, other])
        resolver.supportsParameter(parameter),
    ],
    'defaults': show(resolve(resolver, plain, '')),
    'asked': show(resolve(resolver, plain, 'page=3&size=7&sort=title,desc&sort=year')),
    'capped': show(resolve(resolver, plain, 'size=100000')),
    'negative': show(resolve(resolver, plain, 'page=-4&size=-1')),
    'garbage': show(resolve(resolver, plain, 'page=x&size=y')),
    'annotation': show(resolve(resolver, withDefault, '')),
    'annotationSize': show(resolve(resolver, withDefault, 'size=2&page=1')),
    'sortDefaults': show(resolve(resolver, sortDefault, '')),
    'sortOverrides': show(resolve(resolver, sortDefault, 'sort=id,desc')),
    'sortOnly': show(resolve(resolver, forSort, '')),
    'sortParam': show(resolve(resolver, forSort, 'sort=a,b,desc&sort=c,ignorecase')),
    'emptySort': show(resolve(resolver, forSort, 'sort=')),
    'qualified': [
      show(resolve(resolver, first, 'first_page=1&first_size=3&second_page=9')),
      show(resolve(resolver, second, 'first_page=1&second_size=4')),
    ],
  };
  // Two Pageable parameters without a qualifier are ambiguous, as in Spring.
  final both = parameters([(pageable, const []), (pageable, const [])]);
  try {
    resolver.supportsParameter(both.first);
    result['ambiguous'] = 'no error';
  } on StateError catch (error) {
    result['ambiguous'] = error.message;
  }
  context.close();

  final configured = start({
    'spring.data.web.pageable.default-page-size': '7',
    'spring.data.web.pageable.max-page-size': '50',
    'spring.data.web.pageable.one-indexed-parameters': 'true',
    'spring.data.web.pageable.page-parameter': 'p',
    'spring.data.web.pageable.size-parameter': 'n',
    'spring.data.web.pageable.prefix': 'q.',
    'spring.data.web.pageable.qualifier-delimiter': '-',
    'spring.data.web.sort.sort-parameter': 'order',
  });
  final custom = pagingResolver(configured);
  final plain2 = one(pageable);
  final forSort2 = one(sort);
  final first2 = one(pageable, const [Qualifier('x')]);
  result['configured'] = [
    show(resolve(custom, plain2, '')),
    show(resolve(custom, plain2, 'q.p=1&q.n=500&order=a,desc')),
    show(resolve(custom, plain2, 'page=4&size=9&sort=a')),
    show(resolve(custom, forSort2, 'order=z')),
    show(resolve(custom, first2, 'q.x-p=2&q.x-n=3')),
  ];
  configured.close();
  return result;
}

// The controllers answer over HTTP: the glue's resolvers and error mapping
// together with the starters' own server.
Future<Map<String, Object?>> serverResults() async {
  final out = <String, Object?>{};
  await const ApplicationContextRunner()
      .withUserConfiguration(pkgBeans)
      .withAutoConfiguration(springBootAutoConfiguration)
      .withAutoConfiguration(springBootStarterLoggingAutoConfiguration)
      .withAutoConfiguration(springBootStarterWebAutoConfiguration)
      .withPropertyValues([
        'spring.test.web-environment=random-port',
        'server.address=127.0.0.1',
        'logging.level.root=warn',
      ])
      .runAsync((context) async {
        final server = await context
            .getBean<WebServerStartStopLifecycle>()
            .started;
        final client = HttpClient();
        Future<Object?> get(String path) async {
          final request = await client.getUrl(
            Uri.parse('http://127.0.0.1:${server!.port}$path'),
          );
          final response = await request.close();
          final text = await utf8.decodeStream(response);
          return [response.statusCode, text];
        }

        out['page'] = await get('/books?page=1&size=2');
        out['default'] = await get('/books');
        out['sorted'] = await get('/books/sorted?sort=title,desc&sort=year');
        out['echo'] = await get('/books/page?page=-3&size=99999&sort=a');
        out['unknown'] = await get('/books/unknown');
        out['value'] = await get('/books/value');
        client.close(force: true);
      });
  return out;
}

Future<void> main() async {
  final context = AnnotationConfigApplicationContext([pkgBeans])..refresh();
  final resolver = context.getBean<HandlerExceptionResolver>();
  // The messages are what a store would give: SQL and a value.
  const message = 'insert into people (ssn) values (?) -- 123-45-6789';
  final result = {
    'bean': context.containsBean('dataAccessExceptionResolver'),
    'mapped': await ask(resolver, [
      OptimisticLockingFailureException(message, sql: 'update people set x'),
      DuplicateKeyException(message, sql: 'insert into people'),
      EmptyResultDataAccessException(1, message: message),
      _SubclassOfDuplicateKey(),
    ]),
    // What a request can ask for wrongly: a sort property with a line
    // break, a direction, a page past the offsets a database counts.
    'invalid': await ask(resolver, [
      PropertyReferenceException('title\r\nFORGED', 'Book'),
      InvalidPagingRequestException(-1, 'page', 'must not be negative'),
      () {
        try {
          PageRequest.of(1 << 61, 8);
        } on InvalidPagingRequestException catch (error) {
          return error;
        }
        throw StateError('no error');
      }(),
      () {
        try {
          Direction.fromString('up\nFORGED');
        } on InvalidPagingRequestException catch (error) {
          return error;
        }
        throw StateError('no error');
      }(),
    ]),
    // A value of the caller the database cannot take; the message holds
    // the value, the answer must not.
    'argument': await ask(resolver, [
      InvalidDataArgumentException('bad value 123-45-6789'),
    ]),
    'passed': await ask(resolver, [
      InvalidDataAccessApiUsageException('developer mistake 123-45-6789'),
      DataIntegrityViolationException(message),
      IncorrectResultSizeDataAccessException(1, 2),
      CannotAcquireLockException(message),
      PessimisticLockingFailureException(message),
      QueryTimeoutException(message),
      BadSqlGrammarException(message),
      StateError(message),
      ResponseStatusException(HttpStatus.badGateway),
    ]),
  };
  // A bean of the same name registered before the glue replaces it.
  final own = AnnotationConfigApplicationContext([
    BeanModule('own', [
      BeanDefinition<HandlerExceptionResolver>(
        name: 'dataAccessExceptionResolver',
        create: (_) => _Teapot(),
      ),
    ]),
    pkgBeans,
  ])..refresh();
  result['replaced'] = await ask(own.getBean<HandlerExceptionResolver>(), [
    DuplicateKeyException(message),
  ]);
  result['resolvers'] =
      own.getBeansOfType<HandlerExceptionResolver>().length;
  result['paging'] = pagingResults();
  result['server'] = await serverResults();
  print('RESULT ${jsonEncode(result)}');
  context.close();
  own.close();
}
''';

/// Builds the application, runs its `bin/main.dart` and returns the JSON
/// value it prints after `RESULT `.
Future<Map<String, Object?>> _run() async {
  final sources = {
    'pubspec.yaml': _pubspec,
    'lib/src/beans.dart': _scan,
    'lib/src/books.dart': _books,
    'bin/main.dart': _main,
  };
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(),
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  final directory = await Directory.systemTemp.createTemp('spring_web_glue_');
  addTearDown(() => directory.delete(recursive: true));
  final files = {
    ...sources,
    for (final output in result.outputs)
      output.path: readerWriter.testing.readString(output),
  };
  for (final MapEntry(:key, :value) in files.entries) {
    final file = File('${directory.path}/$key');
    await file.parent.create(recursive: true);
    await file.writeAsString(value);
  }
  final workspace = await loadPackageConfigUri((await Isolate.packageConfig)!);
  await savePackageConfig(
    PackageConfig([
      ...workspace.packages,
      Package(
        'pkg',
        directory.uri,
        packageUriRoot: directory.uri.resolve('lib/'),
      ),
    ]),
    directory,
  );
  final process = await Process.run(Platform.resolvedExecutable, [
    '--packages=${directory.path}/.dart_tool/package_config.json',
    '${directory.path}/bin/main.dart',
  ]);
  final output = '${process.stdout}';
  final line = LineSplitter.split(
    output,
  ).where((line) => line.startsWith('RESULT ')).firstOrNull;
  expect(line, isNotNull, reason: '$output\n${process.stderr}');
  return jsonDecode(line!.substring('RESULT '.length)) as Map<String, Object?>;
}

// The problem a mapped error becomes: the status, the generic detail, no
// headers, the error as the cause (not sent).
Matcher _problem(int status, String title, String detail) => equals({
  'status': status,
  'json': {
    'type': 'about:blank',
    'title': title,
    'status': status,
    'detail': detail,
  },
  'headers': true,
  'cause': true,
});

void main() {
  late Map<String, Object?> result;

  setUpAll(() async => result = await _run());

  test('the glue registers the bean', () {
    expect(result['bean'], isTrue);
  });

  test('a version conflict, a duplicate key and an empty result are the '
      'statuses and the generic details of the roadmap', () {
    expect(result['mapped'], [
      _problem(409, 'Conflict', 'The resource was changed by someone else'),
      _problem(409, 'Conflict', 'The resource already exists'),
      _problem(404, 'Not Found', 'Not found'),
      // A subtype of a mapped exception is mapped too.
      _problem(409, 'Conflict', 'The resource already exists'),
    ]);
  });

  test('an invalid sort property, page or direction is a 400 with a fixed '
      'detail', () {
    expect(result['invalid'], [
      _problem(400, 'Bad Request', 'Invalid sort property'),
      _problem(400, 'Bad Request', 'Invalid page or sort request'),
      _problem(400, 'Bad Request', 'Invalid page or sort request'),
      _problem(400, 'Bad Request', 'Invalid page or sort request'),
    ]);
    expect(jsonEncode(result['invalid']), isNot(contains('FORGED')));
  });

  test('a bad argument value is a 400 with a fixed detail; the plain '
      'InvalidDataAccessApiUsageException stays unmapped', () {
    expect(result['argument'], [
      _problem(400, 'Bad Request', 'Invalid request value'),
    ]);
    expect(jsonEncode(result['argument']), isNot(contains('123-45')));
  });

  test('the details are fixed: nothing of the exception reaches the '
      'answer', () {
    final text = jsonEncode(result['mapped']);
    for (final leak in ['insert into', 'update people', '123-45-6789', '?']) {
      expect(text, isNot(contains(leak)));
    }
  });

  test('other errors are left alone: null, so they stay what they are '
      'today', () {
    expect(result['passed'], everyElement(isNull));
    expect(result['passed']! as List, hasLength(9));
  });

  group('the Pageable and Sort parameters', () {
    late Map<String, Object?> paging;

    setUpAll(() => paging = result['paging']! as Map<String, Object?>);

    test('Pageable and Sort are filled, other types are not', () {
      expect(paging['supports'], [true, true, false]);
    });

    test('without query parameters: page 0 of 20, unsorted', () {
      expect(paging['defaults'], 'page 0 size 20 sort UNSORTED');
    });

    test('page, size and several sort parameters', () {
      expect(
        paging['asked'],
        'page 3 size 7 sort title: desc, year: asc',
      );
    });

    test('the size is capped at 2000, a negative page or size is the '
        'default, text is 0', () {
      expect(paging['capped'], 'page 0 size 2000 sort UNSORTED');
      expect(paging['negative'], 'page 0 size 20 sort UNSORTED');
      expect(paging['garbage'], 'page 0 size 20 sort UNSORTED');
    });

    test('@PageableDefault gives size, page and order; the request wins', () {
      expect(paging['annotation'], 'page 0 size 5 sort title: asc');
      expect(paging['annotationSize'], 'page 1 size 2 sort title: asc');
    });

    test('@SortDefault adds up, a requested order replaces it', () {
      expect(
        paging['sortDefaults'],
        'page 0 size 20 sort year: desc, title: asc',
      );
      expect(paging['sortOverrides'], 'page 0 size 20 sort id: desc');
    });

    test('a Sort parameter: the default, the request, ignorecase, an empty '
        'sort= is the default', () {
      expect(paging['sortOnly'], 'sort id: asc');
      expect(
        paging['sortParam'],
        'sort a: desc, b: desc, c: asc, ignoring case',
      );
      expect(paging['emptySort'], 'sort id: asc');
    });

    test('a @Qualifier prefixes the names', () {
      expect(paging['qualified'], [
        'page 1 size 3 sort UNSORTED',
        'page 0 size 4 sort UNSORTED',
      ]);
    });

    test('two unqualified Pageable parameters are an error at startup', () {
      expect(paging['ambiguous'], contains('Ambiguous Pageable arguments'));
    });

    test('the spring.data.web properties change the defaults, the bounds '
        'and the names', () {
      expect(paging['configured'], [
        'page 0 size 7 sort UNSORTED',
        // One-indexed: page 1 is the first; size cut to 50.
        'page 0 size 50 sort a: desc',
        // The prefix applies: unprefixed names are not read.
        'page 0 size 7 sort UNSORTED',
        'sort z: asc',
        'page 1 size 3 sort UNSORTED',
      ]);
    });
  });

  group('end to end, over HTTP', () {
    late Map<String, Object?> server;

    setUpAll(() => server = result['server']! as Map<String, Object?>);

    test('a returned Page is the stable JSON of Spring Data', () {
      final [status, body] = server['page']! as List;
      expect(status, 200);
      expect(jsonDecode(body as String), {
        'content': [
          {'title': 'Dune'},
          {'title': 'Emma'},
        ],
        'page': {
          'size': 2,
          'number': 1,
          'totalElements': 41,
          'totalPages': 21,
        },
      });
      // @PageableDefault(size: 2): no query parameters, the default.
      expect(
        (jsonDecode((server['default']! as List)[1] as String) as Map)['page'],
        containsPair('size', 2),
      );
    });

    test('Sort and Pageable parameters are filled from the query', () {
      expect(server['sorted'], [200, 'title: desc, year: asc']);
      expect(server['echo'], [200, '0/2000/a: asc']);
    });

    test('errors of the data starter keep their statuses', () {
      final [unknown, value] = [server['unknown'], server['value']];
      expect((unknown! as List)[0], 400);
      expect((value! as List)[0], 400);
      expect((value as List)[1], contains('Invalid request value'));
      expect(value[1], isNot(contains('123-45')));
    });
  });

  test('an application bean of the same name replaces the glue', () {
    expect(result['replaced'], [
      {
        'status': 418,
        'json': {
          'type': 'about:blank',
          'title': "I'm a teapot",
          'status': 418,
          'detail': 'mine',
        },
        'headers': true,
        'cause': false,
      },
    ]);
    expect(result['resolvers'], 1);
  });
}
