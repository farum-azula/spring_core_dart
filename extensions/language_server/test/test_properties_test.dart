// Properties a test sets for its own context (@SpringBootTest(properties:),
// @TestPropertySource, @TestEnvironment, @DynamicPropertySource, args,
// springBootTest(...), withPropertyValues) count as defined in that test
// file: no "Cannot resolve property", and go to definition finds them.
import 'dart:io';

import 'package:dart_spring_language_server/src/workspace.dart';
import 'package:test/test.dart';

const _test = r'''
import 'package:spring_boot_starter_test/spring_boot_starter_test.dart';

@SpringBootTest(
  properties: {'test.inline': 'a'},
  args: ['--test.from-args=b'],
)
@TestPropertySource(properties: {'test.source': 'c'})
@TestEnvironment({'TEST_FROM_ENV': 'd'})
class LifecycleTest {
  @DynamicPropertySource()
  static void server(DynamicPropertyRegistry registry) =>
      registry.add('test.server-url', () => 'http://localhost');

  @Value(r'${test.server-url}')
  late String serverUrl;

  @Value(r'${test.inline}')
  late String inline;

  @Value(r'${test.from-args}')
  late String fromArgs;

  @Value(r'${test.source}')
  late String source;

  @Value(r'${test.from-env}')
  late String fromEnv;

  @Value(r'${test.unknown}')
  late String unknown;
}

void main() {
  springBootTest(app, properties: {'fn.inline': 1}, systemEnvironment: {'FN_ENV': 'x'});
  ApplicationContextRunner().withPropertyValues(['fn.runner=1']);
}

class Uses {
  @Value(r'${fn.inline}')
  late String a;
  @Value(r'${fn.env}')
  late String b;
  @Value(r'${fn.runner}')
  late String c;
}
''';

void main() {
  late Directory root;
  late SpringWorkspace workspace;
  late String testPath;
  late String libPath;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('lsp_test_props_');
    testPath = '${root.path}/test/lifecycle_test.dart';
    libPath = '${root.path}/lib/src/uses.dart';
    File(testPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(_test);
    // The same @Value outside test/: the test's properties do not count.
    File(libPath)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:spring_core_dart/spring_core_dart.dart';\n"
        'class Lib {\n'
        "  @Value(r'\${test.server-url}')\n"
        '  late String url;\n'
        '}\n',
      );
    workspace = SpringWorkspace([root.path])..refresh(force: true);
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  List<String> unresolved(String path) => [
    for (final problem in workspace.problems(path))
      if (problem.message.startsWith('Cannot resolve property'))
        problem.message,
  ];

  test('keys the test sets are resolved in the test file', () {
    expect(unresolved(testPath), [
      "Cannot resolve property 'test.unknown' in any properties file",
    ]);
  });

  test('outside test/ they are not', () {
    expect(unresolved(libPath), [
      "Cannot resolve property 'test.server-url' in any properties file",
    ]);
  });

  test('go to definition jumps to where the test sets the key', () {
    final text = File(testPath).readAsStringSync();
    final lines = text.split('\n');
    int lineOf(String needle) => lines.indexWhere((l) => l.contains(needle));
    final valueLine = lineOf(r"@Value(r'${test.server-url}')");
    final column = lines[valueLine].indexOf('test.server-url') + 2;
    final offset =
        lines.take(valueLine).fold<int>(0, (sum, l) => sum + l.length + 1) +
        column;
    final targets = workspace.definition(testPath, offset);
    expect(targets, hasLength(1));
    expect(targets.single.path, testPath);
    expect(targets.single.startLine, lineOf("registry.add('test.server-url'"));
  });
}
