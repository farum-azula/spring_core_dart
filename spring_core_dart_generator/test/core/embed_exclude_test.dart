// spring.resources.embed.exclude: the files it names are left out of the
// module's resources, the configuration never; a file left out that is no
// Flutter asset is reported with the lines for pubspec.yaml.
import 'package:build_test/build_test.dart';
import 'package:spring_core_dart_generator/src/spring_builder.dart';
import 'package:test/test.dart';

const _main = '''
import 'package:spring_boot_dart/spring_boot_dart.dart';
import 'spring_gen/main.spring.dart';

@SpringBootApplication()
void main(List<String> args) => springApplication.run(args);
''';

Future<(String, List<String>)> _module(String pubspec) async {
  final readerWriter = TestReaderWriter(
    rootPackage: 'pkg',
    flattenOutput: true,
  );
  await readerWriter.testing.loadIsolateSources();
  final logs = <String>[];
  final result = await testBuilder(
    SpringBuilder(),
    {
      'pkg|pubspec.yaml': pubspec,
      'pkg|lib/main.dart': _main,
      'pkg|lib/resources/application.yml': '''
spring:
  resources:
    embed:
      exclude: [content/**, '*.yml']
''',
      'pkg|lib/resources/messages.properties': 'hello=Hello',
      'pkg|lib/resources/content/a.md': '# A',
      'pkg|lib/resources/content/deep/b.md': '# B',
      'pkg|lib/resources/banner.txt': 'BANNER',
    },
    rootPackage: 'pkg',
    readerWriter: readerWriter,
    flattenOutput: true,
    onLog: (record) => logs.add(record.message),
  );
  expect(result.errors, isEmpty);
  return (
    result.readerWriter.testing.readString(
      result.outputs.singleWhere(
        (o) => o.path == 'lib/spring_gen/main.spring.dart',
      ),
    ),
    logs,
  );
}

void main() {
  test('the files named are left out; the configuration stays', () async {
    final (module, _) = await _module('name: pkg\n');
    expect(module, isNot(contains("r'content/a.md'")));
    expect(module, isNot(contains("r'content/deep/b.md'")));
    expect(module, contains("r'banner.txt'"));
    // '*.yml' cannot leave the configuration out.
    expect(module, contains("r'application.yml'"));
    expect(module, contains("r'messages.properties'"));
  });

  test('a file left out that is no Flutter asset is reported', () async {
    final (_, logs) = await _module('''
name: pkg
flutter:
  assets:
    - lib/resources/content/
''');
    final warning = logs.singleWhere(
      (m) => m.contains('spring.resources.embed.exclude'),
    );
    // The subdirectory: an asset directory has its own files only.
    expect(warning, contains('    - lib/resources/content/deep/'));
    expect(warning, isNot(contains('    - lib/resources/content/\n')));
  });

  test('every file left out an asset: no warning', () async {
    final (_, logs) = await _module('''
name: pkg
flutter:
  assets:
    - lib/resources/content/
    - lib/resources/content/deep/
''');
    expect(logs.where((m) => m.contains('embed.exclude')), isEmpty);
  });
}
