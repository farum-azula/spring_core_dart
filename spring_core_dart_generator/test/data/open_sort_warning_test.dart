// A handler's `Pageable` or `Sort` without @AllowedSortProperties is a
// warning of the build: a DTO does not hide what the order of the rows
// shows. It never stops the build.
import 'package:build_test/build_test.dart';
import 'package:logging/logging.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:test/test.dart';

const _scan = r'''
import 'package:spring_core_dart/spring_core_dart.dart';
import 'package:pkg/spring_gen/src/app.spring.dart';

@ComponentScan()
final BeanModule pkgBeans = $pkgBeans;
''';

String _app(String members) =>
    '''
import 'package:spring_boot_starter_data/spring_boot_starter_data.dart';
import 'package:spring_boot_starter_web/spring_boot_starter_web.dart';

abstract class Base {
  @GetMapping('/base')
  String inherited(Pageable page) => '';
}

@RestController()
class Employees extends Base {
  $members
}
''';

Future<List<String>> _warnings(String members) async {
  final logs = <LogRecord>[];
  final readerWriter = TestReaderWriter(rootPackage: 'pkg');
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    SpringBuilder(generations: packageGenerations),
    {
      'pkg|pubspec.yaml':
          'name: pkg\ndependencies:\n'
          '  spring_boot_starter_data: any\n'
          '  spring_boot_starter_web: any\n',
      'pkg|lib/src/beans.dart': _scan,
      'pkg|lib/src/app.dart': _app(members),
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    onLog: logs.add,
  );
  expect(result.succeeded, isTrue, reason: '${result.errors}');
  return [
    for (final log in logs)
      if (log.level == Level.WARNING &&
          log.message.contains('AllowedSortProperties'))
        log.message,
  ];
}

void main() {
  test('warns about a Pageable, a Sort and an inherited handler', () async {
    final warnings = await _warnings('''
  @GetMapping('/a')
  String paged(Pageable page) => '';

  @GetMapping('/b')
  String sorted(Sort order) => '';
''');
    expect(warnings, hasLength(3));
    expect(
      warnings,
      contains(contains('Employees.paged: the parameter page')),
    );
    expect(
      warnings,
      contains(contains('Employees.sorted: the parameter order')),
    );
    expect(warnings, contains(contains('Employees.inherited:')));
  });

  test('says nothing with the list, or off a handler', () async {
    final warnings = await _warnings('''
  @override
  @GetMapping('/base')
  String inherited(@AllowedSortProperties(['name']) Pageable page) => '';

  @GetMapping('/a')
  String listed(@AllowedSortProperties(['name']) Sort order) => '';

  String notHandler(Pageable page) => '';
''');
    expect(warnings, isEmpty);
  });
}
