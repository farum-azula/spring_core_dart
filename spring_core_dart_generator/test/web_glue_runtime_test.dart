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

// The generated module in a context, the resolver asked about errors.
const _main = r'''
import 'dart:convert';

import 'package:pkg/src/beans.dart';
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

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
    'passed': await ask(resolver, [
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
    expect(result['passed']! as List, hasLength(8));
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
