// Every Dart file the generator writes is what `dart format` makes of it
// in its package: the language version of the package (the tall style
// from 3.7, the short one before), and the `formatter:` options of the
// nearest analysis_options.yaml (page width, trailing commas, through its
// includes).
import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dart_style/dart_style.dart';
import 'package:package_config/package_config.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:spring_core_dart_generator/src/core/builder/dart_format.dart';
import 'package:spring_core_dart_generator/src/core/builder/package_directory.dart';
import 'package:spring_core_dart_generator/src/core/builder/spring_builder.dart';
import 'package:spring_core_dart_generator/src/packages.dart';
import 'package:spring_core_dart_generator/src/test/test_builder.dart';
import 'package:test/test.dart';

import '../support/spring_builder.dart';

// An application with a file of every kind: a module with descriptions
// (an @Introspected class, object methods), the binding of a
// @ConfigurationProperties class, proxies (an aspect), the debug part.
const Map<String, String> _sources = {
  'bin/main.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => runApplication(args);
''',
  'lib/src/beans.dart': scanRoot,
  'lib/src/service.dart': '''
import 'package:spring_boot_dart/spring_boot_dart.dart';

@ConfigurationProperties('shop')
class ShopProperties {
  String name = 'NEON Books';
  int pageSize = 20;
}

@Introspected()
@EqualsAndHashCode()
@ToString(mask: ['payment'])
@CopyWith()
class Order with IntrospectedObject {
  const Order({required this.id, required this.lines, this.payment});
  final int id;
  final List<String> lines;
  final String? payment;
}

@Service()
class OrderService {
  Future<Order> place(Order order, {bool express = false}) async => order;
  int count(String customer, [int limit = 100]) => limit;
}

@Aspect()
@Component()
class Timing {
  @Around('execution(* OrderService.*(..))')
  Object? time(ProceedingJoinPoint point) => point.proceed();
}
''',
};

// A test file with a @SpringBootTest class, for the test builder.
const _testFile = '''
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';
import 'spring_gen/order.test.spring.dart';

@SpringBootTest()
class OrderTest {
  @Test()
  void places() {}
}

void main() => runSpringTests();
''';

// The package config of the isolate with `pkg` at [version].
Future<PackageConfig> _packageConfig(LanguageVersion? version) async {
  final isolate = await loadPackageConfigUri((await Isolate.packageConfig)!);
  return PackageConfig([
    for (final package in isolate.packages)
      if (package.name != 'pkg') package,
    Package(
      'pkg',
      Uri.parse('file:///pkg/'),
      packageUriRoot: Uri.parse('file:///pkg/lib/'),
      languageVersion: version,
    ),
  ]);
}

// The Dart files [builder] writes for [sources] in `pkg` at [version].
Future<Map<String, String>> _outputs(
  Builder builder,
  Map<String, String> sources, {
  LanguageVersion? version,
}) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final result = await testBuilder(
    builder,
    {for (final MapEntry(:key, :value) in sources.entries) 'pkg|$key': value},
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    packageConfig: await _packageConfig(version),
    flattenOutput: true,
  );
  expect(result.errors, isEmpty);
  return {
    for (final id in result.outputs)
      if (id.path.endsWith('.dart'))
        id.path: readerWriter.testing.readString(id),
  };
}

SpringBuilder _springBuilder() =>
    SpringBuilder(generations: packageGenerations);

void main() {
  group('the files of a module', () {
    late Map<String, String> outputs;

    setUpAll(() async => outputs = await _outputs(_springBuilder(), _sources));

    test('are formatted, a file of every kind', () {
      expect(
        outputs.keys,
        containsAll([
          'bin/spring_gen/main.spring.dart',
          'bin/spring_gen/main.spring.debug.dart',
          'bin/spring_gen/main.spring.env.dart',
          'lib/spring_gen/src/beans.spring.dart',
          'lib/spring_gen/src/beans.spring.introspection.dart',
          'lib/spring_gen/src/beans.spring.properties.dart',
          'lib/spring_gen/src/beans.spring.proxies.dart',
        ]),
      );
      final formatter = DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      );
      for (final MapEntry(key: path, value: code) in outputs.entries) {
        expect(formatter.format(code), code, reason: path);
        // The comments too, which the formatter leaves as written.
        expect(
          [
            for (final line in code.split('\n'))
              if (line.trimLeft().startsWith('//') && line.length > 80) line,
          ],
          isEmpty,
          reason: path,
        );
      }
    });

    test('are formatted at the language version of their package: the '
        'short style before 3.7', () async {
      final root = Directory.systemTemp.createTempSync('dart_format');
      addTearDown(() => root.deleteSync(recursive: true));
      File('${root.path}/.dart_tool/package_config.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
{"configVersion": 2, "packages": [
  {"name": "old_app", "rootUri": "../", "packageUri": "lib/",
   "languageVersion": "3.6"}
]}
''');
      final directories = PackageDirectories(workingDirectory: root);
      final format = await DartFormat.forFile(
        directories.file(AssetId('old_app', 'lib/spring_gen/main.spring.dart')),
        languageVersion: directories.languageVersionOf('old_app'),
        directories: directories,
      );
      expect(format.languageVersion, Version(3, 6, 0));
      final short = DartFormatter(languageVersion: Version(3, 6, 0));
      final module = outputs['bin/spring_gen/main.spring.dart']!;
      final formatted = format.format(module);
      expect(formatted, isNot(module));
      expect(short.format(formatted), formatted);
    });
  });

  test('the test builder formats what it writes', () async {
    final outputs = await _outputs(SpringTestBuilder(), {
      'bin/main.dart': _sources['bin/main.dart']!,
      'test/order_test.dart': _testFile,
    });
    final code = outputs['test/spring_gen/order.test.spring.dart']!;
    expect(
      DartFormatter(
        languageVersion: DartFormatter.latestLanguageVersion,
      ).format(code),
      code,
    );
  });

  group('comments', () {
    test('a doc comment with a long line is wrapped to the page', () {
      const code =
          '/// The descriptions of the classes the module '
          '`aVeryLongModuleNameIndeed` uses: its\n'
          '/// `@Introspected` classes.\n'
          'class A {\n'
          '  /// place: `@PreAuthorize("hasRole(\'USER\') and #order.customer '
          '== authentication.name")`, `@Around Audit.time`\n'
          '  void place() {}\n'
          '}\n';
      expect(
        DartFormat.wrapDocComments(code, 80),
        '/// The descriptions of the classes the module '
        '`aVeryLongModuleNameIndeed` uses:\n'
        '/// its `@Introspected` classes.\n'
        'class A {\n'
        '  /// place:\n'
        '  /// `@PreAuthorize("hasRole(\'USER\') and #order.customer == '
        'authentication.name")`,\n'
        '  /// `@Around Audit.time`\n'
        '  void place() {}\n'
        '}\n',
      );
    });

    test(
      'short paragraphs, code blocks, lists and tables stay as they are',
      () {
        const long =
            'a list item whose text is longer than the page, so it is wrapped '
            'with a hanging indent';
        const code =
            '/// Short.\n'
            '///\n'
            '/// ```dart\n'
            '/// final aVeryLongVariableNameThatGoesOnAndOn = '
            'someFunctionWithALongName(argument);\n'
            '/// ```\n'
            '/// | a table row that is longer than the page width, as tables '
            'are | x |\n'
            '/// - $long\n';
        expect(
          DartFormat.wrapDocComments(code, 80),
          '/// Short.\n'
          '///\n'
          '/// ```dart\n'
          '/// final aVeryLongVariableNameThatGoesOnAndOn = '
          'someFunctionWithALongName(argument);\n'
          '/// ```\n'
          '/// | a table row that is longer than the page width, as tables are '
          '| x |\n'
          '/// - a list item whose text is longer than the page, so it is '
          'wrapped with a\n'
          '///   hanging indent\n',
        );
      },
    );

    test('a header line is wrapped as // lines', () {
      expect(
        DartFormat.lineComment(
          'Generated by spring_core_dart_generator from the @SpringBootTest '
          'classes of a_long_name_test.dart.',
        ),
        '// Generated by spring_core_dart_generator from the @SpringBootTest '
        'classes of\n'
        '// a_long_name_test.dart.\n',
      );
    });
  });

  group('the options of analysis_options.yaml', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('dart_format'));
    tearDown(() => root.deleteSync(recursive: true));

    File write(String path, String text) => File('${root.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    test('the nearest file above the output, with what it includes', () async {
      write('app/analysis_options.yaml', '''
include: shared.yaml
formatter:
  trailing_commas: preserve
''');
      write('app/shared.yaml', '''
formatter:
  page_width: 100
  trailing_commas: automate
''');
      final format = await DartFormat.forFile(
        File('${root.path}/app/lib/spring_gen/main.spring.dart'),
        languageVersion: Version(3, 13, 0),
      );
      expect(format.pageWidth, 100);
      expect(format.trailingCommas, TrailingCommas.preserve);
      expect(format.languageVersion, Version(3, 13, 0));
      // 100 columns: a call that 80 would split stays on one line.
      const call =
          'final value = compute(firstArgument, secondArgument, '
          'thirdArgument, fourth);\n';
      expect(format.format('void f() { $call }'), 'void f() {\n  $call}\n');
    });

    test('a package: include, through the package directories', () async {
      write('lints/lib/strict.yaml', 'formatter:\n  page_width: 120\n');
      write('lints/.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": [
  {"name": "lints", "rootUri": "../", "packageUri": "lib/"}
]}
''');
      write(
        'lints/app/analysis_options.yaml',
        'include: package:lints/strict.yaml\n',
      );
      final format = await DartFormat.forFile(
        File('${root.path}/lints/app/bin/spring_gen/main.spring.dart'),
        directories: PackageDirectories(
          workingDirectory: Directory('${root.path}/lints'),
        ),
      );
      expect(format.pageWidth, 120);
      expect(format.trailingCommas, isNull);
      expect(format.languageVersion, DartFormatter.latestLanguageVersion);
    });

    test('none: the formatter defaults', () async {
      final format = await DartFormat.forFile(
        File('${root.path}/nothing/lib/spring_gen/main.spring.dart'),
      );
      expect(format.pageWidth, isNull);
      expect(format.trailingCommas, isNull);
    });
  });
}
